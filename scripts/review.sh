#!/usr/bin/env bash
#
# Build the Platform and bring up everything a reviewer needs to look at it in
# a browser, in one command.
#
#     ./scripts/review.sh [up|down|reset|logs [service]|status|help]
#
# docker-compose.yml is the source of truth for the stack itself (five
# services: postgres, backend, frontend, edge, pgadmin) and this script does not
# duplicate its defaults — it reads .env the same way `docker compose` does.
# What compose does NOT do is migrate the schema: deploy/deploy.sh runs that as
# a one-off container from the backend image before starting anything, and
# this script does the local equivalent so a reviewer lands on a stack that is
# actually usable rather than a backend erroring against an empty database.
#
# What a reviewer needs to know up front:
#   - Sign-in is the Platform's own passwords (ADR-0051, issue #480): there is
#     no identity provider to configure and no SUPABASE_* value to fill in.
#   - Nobody can sign in until an Account with a password exists. Signing in
#     creates no Account, and this script's demo seed deliberately inserts no
#     `app_users` row, so `up` provisions one demo administrator itself
#     (provision_demo_admin, issue #485) and prints the credential pair it
#     created — local development only. Override either half in .env.
#   - A deployment's first administrator is still a person's job, not this
#     script's: README, "The first administrator's password".
# ==============================================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
SEED_FILE="dev/seed-demo.sql"

# Must match docker-compose.yml's own defaults exactly: this is what lets the
# migration step below reach the same Postgres compose is about to start,
# without duplicating docker-compose.yml as a second source of truth for it.
POSTGRES_USER="${POSTGRES_USER:-platform}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-localdev}"
POSTGRES_DB="${POSTGRES_DB:-platform}"

POSTGRES_WAIT_TIMEOUT_SECONDS="${POSTGRES_WAIT_TIMEOUT_SECONDS:-120}"
APP_WAIT_TIMEOUT_SECONDS="${APP_WAIT_TIMEOUT_SECONDS:-120}"
# Separate from APP_WAIT_TIMEOUT_SECONDS because pgAdmin's own first boot —
# initializing its config database, validating the default email, importing
# dev/pgadmin-servers.json — is slower than the backend or the Flutter bundle.
PGADMIN_WAIT_TIMEOUT_SECONDS="${PGADMIN_WAIT_TIMEOUT_SECONDS:-180}"

EDGE_URL="http://localhost:3002"
PGADMIN_URL="http://localhost:5052"

RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

log()  { printf '%s\n' "  $*"; }
ok()   { printf '%s\n' "  ${GREEN}✓${RESET} $*"; }
warn() { printf '%s\n' "  ${YELLOW}!${RESET} $*"; }
die()  { printf '%s\n' "  ${RED}✗${RESET} $*" >&2; exit 1; }

# Quote a value as the inside of a JSON string literal. The login probe below
# sends email and password in a hand-built body, and both are reviewer-supplied
# in .env: a password such as `p@ss"word` would otherwise close the string
# early, provision fine, and then have the probe fail on malformed JSON instead
# of proving the password. Deliberately not `jq`: this script advertises a
# Docker-only reviewer, and jq is one more thing their host might not have.
#
# A raw byte below 0x20 is not legal inside a JSON string either — the
# credential path only enforces a minimum length, so a password can carry one
# (0x0b was measured) — and JSON has no short escape for most of them. The five
# with one (`\b \f \n \r \t`) are escaped by name below; every other C0 byte
# becomes \u00XX. The loop runs after the backslash escape so the backslashes it
# introduces stay single.
json_escape() {
  local s="$1"
  local i c esc
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  for i in $(seq 1 31); do
    case $i in 8 | 9 | 10 | 12 | 13) continue ;; esac
    printf -v c '%b' "\\$(printf '%03o' "$i")"
    printf -v esc '\\u%04x' "$i"
    s=${s//"$c"/$esc}
  done
  printf '%s' "$s"
}

usage() {
  cat <<'EOF'
usage: ./scripts/review.sh [command]

commands:
  up                     build and start the whole stack, migrate the schema,
                         seed the demo data, provision the demo
                         administrator and wait until it answers — the
                         default if no command is given
  down                   stop the stack (docker compose down); data is kept
  reset [-y]             destroy the Postgres volume and bring the stack back
                         up from empty — asks to confirm first unless
                         -y/--yes is given
  logs [service]         follow logs for the whole stack, or one service
  status                 show container status and the health endpoint
  promote-admin <email>  promote an Account that has already signed in once
                         to admin/approved, the way the app's own Approval
                         screen does — local dev convenience only
  seed                   re-apply the demo dataset (dev/seed-demo.sql) to the
                         running stack, without rebuilding it
  grant-account <email> <org-unit-code> [--write]
                         give an Account that has signed in a Grant on a Demo
                         Org Unit (--write for a write Grant), for testing the
                         Org-Unit-scoped behaviour
  help                   show this message
EOF
}

# ------------------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------------------

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed"
  docker compose version >/dev/null 2>&1 || die "docker compose (the v2 plugin) is not available"
  docker info >/dev/null 2>&1 || die "the Docker daemon is not reachable — is it running?"
}

ensure_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    [[ -f .env.example ]] || die ".env is missing and there is no .env.example to copy it from"
    cp .env.example "$ENV_FILE"
    log "copied .env.example to .env"
  fi
}

# ------------------------------------------------------------------------------
# Waiting
# ------------------------------------------------------------------------------

# Polls docker inspect rather than `compose ps`'s own text, for the same
# reason deploy.sh does: it is the one place that can say *which* container is
# unhealthy, which is the first thing anyone asks when this times out.
wait_for_postgres() {
  local deadline=$((SECONDS + POSTGRES_WAIT_TIMEOUT_SECONDS)) id status
  log "waiting for postgres to report healthy (up to ${POSTGRES_WAIT_TIMEOUT_SECONDS}s)"

  while (( SECONDS < deadline )); do
    id=$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)
    if [[ -n "$id" ]]; then
      status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || echo unknown)
      if [[ "$status" == "healthy" ]]; then
        ok "postgres is healthy"
        return 0
      fi
    fi
    sleep 2
  done

  die "postgres did not become healthy within ${POSTGRES_WAIT_TIMEOUT_SECONDS}s — run './scripts/review.sh logs postgres' to see why"
}

# curl -fsS -o /dev/null -w '%{http_code}' against a URL, retried until it
# answers 200 or the deadline passes. curl runs on the host, not in a
# container: every URL checked here is one the edge (or, for pgAdmin, its own
# published port) already publishes to localhost, so there is no
# container-network case to fall back to.
#
# `on_fail` chooses what a timeout does, and defaults to `die` so the two
# existing callers (backend and the Flutter bundle, both through the edge —
# the actual app under review) keep aborting loudly exactly as before. Pass
# `warn` for a check whose failure should not block the rest of the stack —
# see the pgAdmin call in cmd_up, which is a convenience on top of the review,
# not the thing being reviewed.
wait_for_http_200() {
  local url="$1" label="$2" timeout="$3" on_fail="${4:-die}"
  local deadline=$((SECONDS + timeout)) code

  log "waiting for ${label} (${url}) to answer (up to ${timeout}s)"
  while (( SECONDS < deadline )); do
    code=$(curl -fsS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
    if [[ "$code" == "200" ]]; then
      ok "${label} is up (200)"
      return 0
    fi
    sleep 2
  done

  if [[ "$on_fail" == "warn" ]]; then
    warn "${label} (${url}) did not answer 200 within ${timeout}s — run './scripts/review.sh logs' to see why"
  else
    die "${label} (${url}) did not answer 200 within ${timeout}s — run './scripts/review.sh logs' to see why"
  fi
}

# ------------------------------------------------------------------------------
# Migrate
# ------------------------------------------------------------------------------

# The local equivalent of what deploy/deploy.sh does against production: run
# the schema migration as a one-off container from the already-built backend
# image, before anything depending on that schema is trusted. `--no-deps` so
# this doesn't also (re)start postgres/backend as a side effect — they are
# already up by the time this runs. It joins the compose network by service
# name, so `postgres` resolves exactly as it does for the backend container
# itself.
#
# The backend image is built with NODE_ENV=production and `npm ci --omit=dev`,
# but node-pg-migrate is a runtime dependency (backend/package.json), not a
# devDependency, so `npm run migrate` is present and works inside it.
run_migrations() {
  log "running migrations"
  docker compose -f "$COMPOSE_FILE" run --rm --no-deps \
    -e DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}" \
    backend npm run migrate \
    || die "migration failed — the stack is up but the schema is not current; run './scripts/review.sh logs backend' or fix the migration and re-run 'up'"
  ok "schema is current"
}

# A reviewer landing on a freshly-migrated database otherwise sees an empty
# Platform — no Site, no Org Unit, nothing to click into. This applies
# dev/seed-demo.sql — the versioned, idempotent demo dataset (the Demo Plant's
# Org Units, Employees, Assets, inventory, maintenance work, and the plant's
# shifts and production) — through the already-running postgres container, the
# same way `promote-admin` does, rather than a fresh `docker compose run`,
# since postgres is already up by the time this runs.
#
# The file wraps every insert in one transaction and keys each row on a fixed
# demo identifier, so this is safe to run on every `up` — including the `up`
# that `reset` chains into — and on demand via the `seed` command, without
# duplicating a row. Only the expected conflict is ignored: ON_ERROR_STOP makes
# a real failure (a typo'd column, a broken constraint) fail the whole file and
# roll it back, rather than leaving a half-populated plant.
seed_demo_data() {
  [[ -f "$SEED_FILE" ]] || die "${SEED_FILE} is missing from the repo root"
  log "seeding demo data from ${SEED_FILE}"
  docker compose -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
    psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$SEED_FILE" \
    || die "seeding demo data failed — run './scripts/review.sh logs postgres' to see why"
  ok "demo data ready (Demo Plant: Org Units, Employees, Assets, inventory, maintenance and production)"
}

# Provision one demo administrator, end to end, so a reviewer who runs only
# Docker can sign in (issue #485). `POST /api/auth/login` creates no Account —
# it resolves an existing `app_users` row with a credential — and the demo seed
# deliberately inserts none, so without this `up` leaves a stack that answers
# health checks and refuses every sign-in.
#
# The work happens inside the already-running backend container: it carries
# both `pg` and the hashing path sign-in verifies against
# (src/platform/secrets.js), so this needs no Node on the host and no
# `backend/node_modules` on the host — which is what dev/set-a-password.mjs
# needs and a reviewer running only Docker does not have. The password arrives
# on stdin, never argv or the environment, the same rule that script follows.
#
# On a re-run the Account row is re-promoted and its password replaced with
# the one `up` prints, stored temporary (`must_change_password`), exactly as a
# reset does (#270). That is what makes `up` reproducible: a reviewer who
# changed the demo administrator's password, or never wrote it down, can
# always get back in by reading the block `up` prints at the end.
provision_demo_admin() {
  local email="$1" password="$2" result

  log "provisioning the demo administrator ${email}"
  result=$(printf '%s' "$password" | docker compose -f "$COMPOSE_FILE" exec -T \
    -e DEMO_ADMIN_EMAIL="$email" backend node -e "$(cat <<'JS'
const pg = require('pg');
const { hashSecret } = require('./src/platform/secrets');
// people/passwords.js's own floor, imported rather than copied.
const { MIN_PASSWORD_LENGTH } = require('./src/modules/people/passwords');

async function readPassword() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8').replace(/\r?\n$/, '');
}

async function main() {
  const email = process.env.DEMO_ADMIN_EMAIL;
  if (!email) throw new Error('DEMO_ADMIN_EMAIL is not set');
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is not set in the backend container');

  const password = await readPassword();
  if (password.length < MIN_PASSWORD_LENGTH) {
    throw new Error(`The demo administrator password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
  }

  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
  try {
    await pool.query('BEGIN');
    // `email` is CITEXT, so this matches case-insensitively. An existing row is
    // re-promoted rather than replaced: its id keys any Grant a reviewer has
    // already given it with `grant-account`.
    const { rows: [account] } = await pool.query(
      `INSERT INTO app_users (email, display_name, role, is_active, approval_status)
       VALUES ($1, 'Demo Admin', 'admin', TRUE, 'approved')
       ON CONFLICT (email) DO UPDATE
         SET role = 'admin', is_active = TRUE, approval_status = 'approved'
       RETURNING id, email`,
      [email]
    );
    const { rows: [credential] } = await pool.query(
      `INSERT INTO account_credentials (app_user_id, password_hash, must_change_password)
       VALUES ($1, $2, TRUE)
       ON CONFLICT (app_user_id) DO UPDATE
         SET password_hash = EXCLUDED.password_hash,
             must_change_password = TRUE,
             updated_at = now()
       RETURNING must_change_password`,
      [account.id, await hashSecret(password)]
    );
    await pool.query('COMMIT');
    process.stdout.write(`demo administrator id=${account.id} email=${account.email} must_change_password=${credential.must_change_password}`);
  } catch (error) {
    await pool.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(`FAILED: ${error.message}`);
  process.exit(1);
});
JS
)") \
    || die "provisioning the demo administrator failed — run './scripts/review.sh logs backend' to see why"

  ok "${result} (local development only)"
}

# ------------------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------------------

cmd_up() {
  require_docker
  ensure_env_file
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a

  log "building and starting the stack — the first Flutter web build is slow (several minutes on a cold cache); this has not hung"
  docker compose -f "$COMPOSE_FILE" up -d --build

  wait_for_postgres
  run_migrations
  seed_demo_data

  # Both resolved after .env is sourced, so a reviewer can override the demo
  # administrator's address or password there. The defaults are local
  # development furniture — a stack on 127.0.0.1 — never a deployment's door;
  # a deployment's first administrator is set by hand per README.
  local demo_admin_email="${DEMO_ADMIN_EMAIL:-admin@demo.local}"
  local demo_admin_password="${DEMO_ADMIN_PASSWORD:-demo-admin}"
  provision_demo_admin "$demo_admin_email" "$demo_admin_password"

  wait_for_http_200 "${EDGE_URL}/api/health" "backend, through the edge" "$APP_WAIT_TIMEOUT_SECONDS"
  wait_for_http_200 "${EDGE_URL}/" "the Flutter bundle, through the edge" "$APP_WAIT_TIMEOUT_SECONDS"

  # The stack answering /api/health is not the same as a reviewer being able to
  # get into it: that is the exact failure this provisioning exists to prevent,
  # so the sign-in itself is checked, from the host, over the same edge the
  # browser uses. A successful sign-in mints a session row in this local
  # database; harmless, and it is what proves the password verifies.
  local sign_in_status
  local sign_in_body
  sign_in_body="{\"email\":\"$(json_escape "$demo_admin_email")\",\"password\":\"$(json_escape "$demo_admin_password")\"}"
  sign_in_status=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${EDGE_URL}/api/auth/login" \
    -H 'content-type: application/json' \
    -d "$sign_in_body" \
    2>/dev/null || echo 000)
  [[ "$sign_in_status" == "200" ]] \
    || die "the stack is up, but signing in as ${demo_admin_email} answered ${sign_in_status}, not 200 — run './scripts/review.sh logs backend' to see why"
  # warn, not die: pgAdmin is a convenience for browsing Postgres, not the app
  # under review, so a slow or failed pgAdmin boot should never stop a
  # reviewer from reaching the actual stack above. /misc/ping is pgAdmin's own
  # unauthenticated health endpoint — confirmed against the pinned tag to
  # return a bare 200 with no redirect, unlike `/`, which 302s to /browser/
  # (or /login) and would never satisfy curl's `-fsS` without `-L`.
  wait_for_http_200 "${PGADMIN_URL}/misc/ping" "pgAdmin" "$PGADMIN_WAIT_TIMEOUT_SECONDS" warn

  printf '\n'
  ok "ready to review at ${EDGE_URL}"
  log "backend direct:  http://localhost:8002"
  log "postgres direct: localhost:5434 (user ${POSTGRES_USER}, db ${POSTGRES_DB})"
  # No credentials printed here on purpose: PGADMIN_CONFIG_SERVER_MODE is
  # 'False' in docker-compose.yml, which puts pgAdmin in desktop mode and
  # skips its login screen entirely — / lands straight on /browser/. Printing
  # an email and password a reviewer is never asked for would just be
  # confusing. The Postgres password is still needed when opening the
  # pre-registered server, so that one is worth naming.
  log "pgAdmin: ${PGADMIN_URL} (no login; the pre-registered server asks for the Postgres password above)"
  # The one credential pair a reviewer needs, printed because `up` created it.
  # Say plainly that it is local development furniture: the same words appear on
  # a deployment's screen would be a security incident, not a convenience.
  log "sign-in (local development only — not a deployment credential):"
  log "  email:    ${demo_admin_email}"
  log "  password: ${demo_admin_password}"
  log "  POST ${EDGE_URL}/api/auth/login -> ${sign_in_status} (verified just now; stored as temporary, so the app asks for a change on first sign-in)"
}

cmd_down() {
  require_docker
  log "stopping the stack (data is kept)"
  docker compose -f "$COMPOSE_FILE" down
  ok "stopped"
}

cmd_reset() {
  require_docker
  local yes=0
  for arg in "$@"; do
    case "$arg" in
      -y|--yes) yes=1 ;;
    esac
  done

  if (( ! yes )); then
    warn "this destroys the Postgres volume — every Account, Site, and Asset in it — plus pgAdmin's saved connections and sessions"
    read -r -p "  type 'yes' to continue: " reply
    [[ "$reply" == "yes" ]] || die "aborted; nothing was changed"
  fi

  log "tearing down the stack and its data"
  docker compose -f "$COMPOSE_FILE" down -v
  ok "volume removed"
  cmd_up
}

cmd_logs() {
  require_docker
  docker compose -f "$COMPOSE_FILE" logs -f "$@"
}

cmd_status() {
  require_docker
  docker compose -f "$COMPOSE_FILE" ps
  printf '\n'
  local code
  code=$(curl -fsS -o /dev/null -w '%{http_code}' "${EDGE_URL}/api/health" 2>/dev/null || echo 000)
  if [[ "$code" == "200" ]]; then
    ok "${EDGE_URL}/api/health -> 200"
  else
    warn "${EDGE_URL}/api/health -> ${code} (not up, or not ready yet)"
  fi
}

# Re-apply the demo dataset without rebuilding the stack — the same seed `up`
# runs, for when a reviewer has deleted or edited demo rows and wants the Demo
# Plant back. Requires the stack to already be up.
cmd_seed() {
  require_docker
  local id
  id=$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)
  [[ -n "$id" ]] || die "postgres is not running — run './scripts/review.sh up' first"
  seed_demo_data
}

# A local-only shortcut for what an administrator does through the app's own
# Approval screen (POST /accounts/:id/approval in
# backend/src/modules/people/routes.js) — promote an Account that has already
# signed in once (sitting pending/operator in the queue) to admin/approved.
#
# An `app_users` row is a person's credential, never demo plant data: password
# sign-in (backend/src/modules/people/sign-in.js, ADR-0051) resolves an
# existing row that holds a credential and creates none — a person who has
# never been given a password cannot sign in at all, so there is no
# first-sign-in INSERT for a pre-created row to collide with. `up` provisions
# its own row (provision_demo_admin); this command therefore only ever
# re-promotes a row that already exists, and dies loudly when nothing matches.
cmd_promote_admin() {
  [[ $# -eq 1 ]] || die "usage: ./scripts/review.sh promote-admin <email>"
  local email="$1" id result

  require_docker

  id=$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)
  [[ -n "$id" ]] || die "postgres is not running — run './scripts/review.sh up' first"

  # email is CITEXT, so this match is already case-insensitive. The email goes
  # in as a psql variable (:'email' quotes it as a literal), never spliced into
  # the SQL text; psql only interpolates variables from stdin or -f, not -c.
  # -q on top of -t -A: without it, psql still prints its own "UPDATE n"
  # command tag to stdout, which would make $result non-empty even when the
  # UPDATE matched nothing and RETURNING produced no row — silently promoting
  # nobody while reporting success.
  result=$(docker compose -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
    psql -v ON_ERROR_STOP=1 -q -t -A -v "email=${email}" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f - <<'SQL'
UPDATE app_users SET role = 'admin', approval_status = 'approved', is_active = TRUE WHERE email = :'email' RETURNING id;
SQL
  ) \
    || die "promoting ${email} failed — run './scripts/review.sh logs postgres' to see why"

  [[ -n "$result" ]] || die "no Account found for ${email} — signing in creates no Account since #480, so insert its app_users row first ('up' provisions only the demo administrator)"
  ok "${email} is now an approved admin"
}

# Give an Account that has already signed in a Grant on a Demo Org Unit, so a
# reviewer can see the Org-Unit-scoped behaviour (Home's awaiting-assignment
# count, the per-row Assign affordance) without hand-editing the database. A
# Grant row lives in `app_user_org_units`; `--write` sets `can_write` so the
# Account gets a write Grant as well as a read one. The Org Unit is resolved by
# code within the Demo Site.
#
# The Account must already exist, for the same reason `promote-admin` only
# updates: an `app_users` row belongs to a person's credential, never to the
# demo seed. `up` provisions the demo administrator's row itself; on a
# deployment the roster load (`dev/seed-relats-vietnam.mjs`) creates people's
# rows, and `dev/set-a-password.mjs` only gives an existing row a password. A
# Grant hangs off that row, so there is nothing to grant before it exists —
# this never INSERTs an `app_users` row, and the person signs in with the
# password their row already carries.
cmd_grant_account() {
  local write=0 email="" code="" can_write="FALSE"
  for arg in "$@"; do
    case "$arg" in
      --write) write=1 ;;
      *)
        if [[ -z "$email" ]]; then email="$arg"
        elif [[ -z "$code" ]]; then code="$arg"
        fi
        ;;
    esac
  done
  [[ -n "$email" && -n "$code" ]] || die "usage: ./scripts/review.sh grant-account <email> <org-unit-code> [--write]"
  (( write )) && can_write="TRUE"

  local id result
  require_docker

  id=$(docker compose -f "$COMPOSE_FILE" ps -q postgres 2>/dev/null || true)
  [[ -n "$id" ]] || die "postgres is not running — run './scripts/review.sh up' first"

  # email is CITEXT, so the match is already case-insensitive. The values go in
  # as psql variables (:'email' quotes them as literals), never spliced into
  # the SQL text; psql only interpolates variables from stdin or -f, not -c.
  # -q -t -A so RETURNING gives one bare id per matched row and
  # nothing else; an empty result means the Account or the Org Unit code did
  # not resolve.
  result=$(docker compose -f "$COMPOSE_FILE" exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
    psql -v ON_ERROR_STOP=1 -q -t -A -v "email=${email}" -v "code=${code}" -v "can_write=${can_write}" \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f - <<'SQL'
INSERT INTO app_user_org_units (app_user_id, org_unit_id, can_write)
SELECT au.id, ou.id, :can_write
  FROM app_users au
  JOIN org_units ou ON ou.code = :'code'
  JOIN sites s ON s.id = ou.site_id AND s.code = 'DEMO'
 WHERE au.email = :'email'
ON CONFLICT (app_user_id, org_unit_id) DO UPDATE SET can_write = EXCLUDED.can_write
RETURNING app_user_id;
SQL
  ) \
    || die "granting ${email} on ${code} failed — run './scripts/review.sh logs postgres' to see why"

  [[ -n "$result" ]] || die "no Account for ${email} or no Demo Org Unit '${code}' — sign in through the app once, check the code, then run this again"
  ok "${email} now holds a $([[ "$can_write" == "TRUE" ]] && echo "write" || echo "read") Grant on ${code}"
}

# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------

command="${1:-up}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$command" in
  up)                    cmd_up ;;
  down)                  cmd_down ;;
  reset)                 cmd_reset "$@" ;;
  logs)                  cmd_logs "$@" ;;
  status)                cmd_status ;;
  promote-admin)         cmd_promote_admin "$@" ;;
  seed)                  cmd_seed ;;
  grant-account)         cmd_grant_account "$@" ;;
  help|-h|--help)        usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
