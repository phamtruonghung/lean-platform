#!/usr/bin/env bash
#
# Deploy the Platform on the LXC, and put the previous version back if the new
# one does not come up healthy.
#
# The k3s platform this replaces got that safety from Helm: a pre-upgrade
# migration Job, and `--atomic` to roll the release back when anything failed.
# Compose has no such thing, so it is written out here. Without it, a bad image
# leaves the box serving nothing and the failure is discovered by a person.
#
#     ./deploy.sh <image-tag> [--no-pull]
#
# --no-pull uses images already on the box, for a tag that is local already: a
# re-deploy after a runner wipe, an air-gapped push, debugging by hand. The
# rollback below has the same need — the previous images are local by
# definition, and a rollback must not depend on the registry being reachable,
# since an unreachable registry is one of the things that makes a deploy fail
# in the first place — but it meets that need inline, with `--pull never` to
# compose, rather than by re-entering this script with this flag.
#
# It does NOT skip the migration step below, and must not: it says where the
# images come from, not that this is a rollback, and a tag re-deployed from the
# box still needs its schema current before it starts.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE_FILE="${COMPOSE_FILE:-compose.yml}"
# Records what is currently deployed. Read at the start of the next deploy to
# know what to go back to; the running containers would also tell us, but not
# once they have failed to start.
STATE_FILE="${STATE_FILE:-.deployed-tag}"
# How long the new version has to report healthy before it is judged a failure.
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-120}"

# Must agree with compose.yml's own default and with the GHCR_OWNER Release
# passes in, so the migration step below runs the exact image compose.yml is
# about to start rather than guessing at a different path.
GHCR_OWNER="${GHCR_OWNER:-phamtruonghung}"
BACKEND_IMAGE="ghcr.io/${GHCR_OWNER}/lean-platform-backend"

RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

log()  { printf '%s\n' "  $*"; }
ok()   { printf '%s\n' "  ${GREEN}✓${RESET} $*"; }
warn() { printf '%s\n' "  ${YELLOW}!${RESET} $*"; }
die()  { printf '%s\n' "  ${RED}✗${RESET} $*" >&2; exit 1; }

NEW_TAG="${1:-}"
[[ -n "$NEW_TAG" ]] || die "usage: ./deploy.sh <image-tag> [--no-pull]"
PULL=1
[[ "${2:-}" == "--no-pull" ]] && PULL=0

command -v docker >/dev/null 2>&1 || die "docker is not installed"
[[ -n "${DATABASE_URL:-}" ]] || die "DATABASE_URL is not set (see .env.production)"

# COMPOSE_PROJECT_NAME is pinned rather than left to default. Compose otherwise
# names the project after the directory it runs from, so a deploy driven from a
# runner workspace would start a SECOND stack alongside the one already serving
# instead of replacing it — two sets of containers, both claiming the same
# network aliases.
#
# It must NOT match the proxy's project name. `--remove-orphans` deletes any
# container in this project that this file does not define, so a shared name
# means the first deploy removes the TLS terminator and takes the site down for
# good. The proxy runs as its own project, `platform-edge`.
compose() {
  IMAGE_TAG="$1" COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-lean-platform}" \
    docker compose -f "$COMPOSE_FILE" "${@:2}"
}

# Every service reports healthy, or we time out. Compose's own --wait would do
# this, but it cannot tell us *which* service failed, and that is the first
# thing anyone asks when a deploy is rejected.
await_healthy() {
  local tag="$1" deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    local ids all_healthy=1 unhealthy=""
    # -qa, not -q: `ps -q` lists only RUNNING containers, so a service that
    # exits on startup simply vanishes from the list and its healthy siblings
    # satisfy the loop. That is the failure this gate exists to catch.
    ids=$(compose "$tag" ps -qa 2>/dev/null || true)

    if [[ -z "$ids" ]]; then
      all_healthy=0
      unhealthy="no containers running"
    else
      while read -r id; do
        [[ -n "$id" ]] || continue
        local name status
        name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's|^/||')
        # A container with no healthcheck reports nothing, so fall back to
        # whether it is running at all. Both of ours define one.
        status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || echo unknown)
        case "$status" in
          healthy|running) ;;
          *) all_healthy=0; unhealthy+="${name}=${status} " ;;
        esac
      done <<< "$ids"
    fi

    if (( all_healthy )); then
      return 0
    fi

    printf '\r  waiting for health: %-60s' "$unhealthy"
    sleep 3
  done

  printf '\n'
  return 1
}

PREVIOUS_TAG=""
[[ -f "$STATE_FILE" ]] && PREVIOUS_TAG=$(<"$STATE_FILE")

# The state file can be missing on a fresh runner, a rebuilt box, or after a
# deploy done by hand. The containers that are serving right now still know
# which tag they came from, and asking them is far better than concluding there
# is nothing to roll back to — that conclusion tears down a working Platform.
if [[ -z "$PREVIOUS_TAG" ]]; then
  running_image=$(docker ps \
    --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-lean-platform}" \
    --filter "label=com.docker.compose.service=backend" \
    --format '{{.Image}}' | head -1)
  if [[ -n "$running_image" ]]; then
    PREVIOUS_TAG="${running_image##*:}"
    warn "no recorded tag; recovered ${PREVIOUS_TAG} from the running containers"
  fi
fi

log "deploying ${NEW_TAG}"
[[ -n "$PREVIOUS_TAG" ]] && log "currently deployed: ${PREVIOUS_TAG}"

# Pull first and separately. A registry that is unreachable, or a tag that was
# never pushed, must fail here — before anything running has been touched.
if (( PULL )); then
  log "pulling images"
  compose "$NEW_TAG" pull --quiet || die "could not pull ${NEW_TAG}; nothing was changed"
  ok "images present"
fi

# This is the deploy step the spec asks for, and what replaces the k3s
# platform's pre-upgrade migration Job: the schema changes, and is proven to
# apply cleanly, before a single new container exists — let alone takes
# traffic. It runs from the NEW backend image, not whatever happens to be
# checked out on the runner, because that image is what carries
# node-pg-migrate and the migrations directory (see backend/Dockerfile); the
# runner's checkout is not guaranteed to match it. No --network flag: this
# talks to DATABASE_URL over the same public internet path the pull above
# just used, not to anything reachable only via container networking.
#
# Deliberately NOT gated on PULL. --no-pull means "the images are already on
# the box", not "this is a rollback" — the rollback path below never re-enters
# this script, it restores the previous image inline. A tag re-deployed with
# --no-pull still needs its schema current before it starts, so this runs on
# every invocation. `node-pg-migrate up` against an already-current schema is a
# no-op — it reads its migrations table and applies nothing — so running it
# unconditionally costs one container start and is safe to repeat.
#
# Ordering matters beyond this script. Migrations land before the new code
# does, so for the length of this step plus however long the new containers
# take to report healthy, the OLD version is still the one serving requests —
# now against the NEW schema. That is only safe if every migration is
# backward-compatible with the version it is replacing: add a column and
# start filling it in one deploy, drop what nothing reads any more only in a
# LATER deploy once nothing depends on it. Expand now, contract later. A
# migration that isn't safe for the old code to run against — dropping a
# column it still selects, renaming one it still writes — breaks the running
# Platform in this window even though the deploy itself goes on to succeed.
#
# A failure here `die`s with nothing running touched yet: at most the pull
# happened, but no container has been started or stopped. The old version,
# whatever it was, is still serving exactly as it was before this script ran.
log "running migrations"
docker run --rm \
  -e DATABASE_URL="$DATABASE_URL" \
  "${BACKEND_IMAGE}:${NEW_TAG}" \
  npm run migrate \
  || die "migration for ${NEW_TAG} failed; nothing was changed"
ok "schema is current for ${NEW_TAG}"

log "starting ${NEW_TAG}"
if ! compose "$NEW_TAG" up -d --remove-orphans; then
  warn "failed to start ${NEW_TAG}"
  ROLLBACK=1
elif ! await_healthy "$NEW_TAG"; then
  warn "${NEW_TAG} did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s"
  ROLLBACK=1
else
  ROLLBACK=0
fi

# Rollback puts the previous IMAGE back. It does not, and must not, touch the
# schema — there is no `node-pg-migrate down` anywhere in this script. Running
# one automatically, under deploy-failure pressure, would be more dangerous
# than the forward state it was undoing: it can drop a column or table the
# previous version's own queries still reference, or discard data written under
# the new schema in the meantime. The expand/contract rule above is what makes
# this safe instead of reckless — because a migration is never a breaking
# change for the version it replaces, the previous image can simply keep
# serving the migrated schema, which is exactly what rollback is about to ask it
# to do. Migrations are forward-only; the only way back from a bad one is a
# further migration that fixes it forward, deployed like any other change.
if (( ROLLBACK )); then
  if [[ -z "$PREVIOUS_TAG" ]]; then
    compose "$NEW_TAG" down --remove-orphans >/dev/null 2>&1 || true
    die "deploy failed and there is no previous version to restore (first deploy)"
  fi

  warn "rolling back to ${PREVIOUS_TAG}"
  # No pull: the previous images are already on this box, and the registry may
  # be exactly what is broken.
  compose "$PREVIOUS_TAG" up -d --remove-orphans --pull never \
    || die "ROLLBACK FAILED — the Platform is down and needs a person"

  if await_healthy "$PREVIOUS_TAG"; then
    ok "rolled back to ${PREVIOUS_TAG}, which is serving"
  else
    die "ROLLBACK FAILED — ${PREVIOUS_TAG} is not healthy either; the Platform is down"
  fi

  die "deploy of ${NEW_TAG} rejected; ${PREVIOUS_TAG} is still serving"
fi

printf '%s' "$NEW_TAG" > "$STATE_FILE"
ok "deployed ${NEW_TAG}"
