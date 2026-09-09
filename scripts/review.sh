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
# Two things a reviewer needs to know up front, both already true of this
# repo's setup rather than invented here:
#   - Sign-in is Supabase (ADR-0002). SUPABASE_URL/SUPABASE_ANON_KEY are baked
#     into the Flutter bundle at build time and have no local default, so on a
#     clean checkout the app builds and serves fine but nobody can sign in
#     until .env points at a real Supabase project.
#   - The very first Account to sign in on an empty database is activated
#     immediately as an administrator (README, "Accounts and sign-in") — that
#     is how a reviewer with a working Supabase project gets in at all.
# ==============================================================================

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

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

usage() {
  cat <<'EOF'
usage: ./scripts/review.sh [command]

commands:
  up             build and start the whole stack, migrate the schema, and
                 wait until it answers — the default if no command is given
  down           stop the stack (docker compose down); data is kept
  reset [-y]     destroy the Postgres volume and bring the stack back up from
                 empty — asks to confirm first unless -y/--yes is given
  logs [service] follow logs for the whole stack, or one service
  status         show container status and the health endpoint
  help           show this message
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
    log "copied .env.example to .env (fill in SUPABASE_* to enable sign-in)"
  fi
}

# Warns, but never blocks: the stack is genuinely useful to review — browsing
# the UI, hitting the API, checking migrations — without a real Supabase
# project wired up. Only sign-in itself needs one. Never echo the values
# themselves; an anon key is public by design, but keeping this output clean
# means nobody has to think about that each time this prints.
check_supabase_config() {
  local url_state="not set" key_state="not set"
  [[ -n "${SUPABASE_URL:-}" ]] && url_state="set"
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && key_state="set"

  if [[ "$url_state" == "not set" || "$key_state" == "not set" ]]; then
    warn "SUPABASE_URL: ${url_state}, SUPABASE_ANON_KEY: ${key_state}"
    warn "the app will build and serve, but sign-in will not work until .env points at a real Supabase project"
  else
    ok "Supabase configured (SUPABASE_URL: ${url_state}, SUPABASE_ANON_KEY: ${key_state})"
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
  check_supabase_config

  log "building and starting the stack — the first Flutter web build is slow (several minutes on a cold cache); this has not hung"
  docker compose -f "$COMPOSE_FILE" up -d --build

  wait_for_postgres
  run_migrations

  wait_for_http_200 "${EDGE_URL}/api/health" "backend, through the edge" "$APP_WAIT_TIMEOUT_SECONDS"
  wait_for_http_200 "${EDGE_URL}/" "the Flutter bundle, through the edge" "$APP_WAIT_TIMEOUT_SECONDS"
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
  if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
    log "Supabase: configured — sign-in works"
  else
    log "Supabase: not configured — sign-in will not work (see the warning above)"
  fi
  log "the first Account to sign in on an empty database becomes an administrator automatically"
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

# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------

command="${1:-up}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$command" in
  up)             cmd_up ;;
  down)           cmd_down ;;
  reset)          cmd_reset "$@" ;;
  logs)           cmd_logs "$@" ;;
  status)         cmd_status ;;
  help|-h|--help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
