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
# --no-pull uses images already on the box. A rollback always uses it: the
# previous images are local by definition, and a rollback must not depend on the
# registry being reachable — the registry being unreachable is one of the things
# that makes a deploy fail in the first place.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE_FILE="${COMPOSE_FILE:-compose.yml}"
# Records what is currently deployed. Read at the start of the next deploy to
# know what to go back to; the running containers would also tell us, but not
# once they have failed to start.
STATE_FILE="${STATE_FILE:-.deployed-tag}"
# How long the new version has to report healthy before it is judged a failure.
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-120}"

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
    ids=$(compose "$tag" ps -q 2>/dev/null || true)

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

log "deploying ${NEW_TAG}"
[[ -n "$PREVIOUS_TAG" ]] && log "currently deployed: ${PREVIOUS_TAG}"

# Pull first and separately. A registry that is unreachable, or a tag that was
# never pushed, must fail here — before anything running has been touched.
if (( PULL )); then
  log "pulling images"
  compose "$NEW_TAG" pull --quiet || die "could not pull ${NEW_TAG}; nothing was changed"
  ok "images present"
fi

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

if (( ROLLBACK )); then
  if [[ -z "$PREVIOUS_TAG" ]]; then
    compose "$NEW_TAG" down --remove-orphans >/dev/null 2>&1 || true
    die "deploy failed and there is no previous version to restore (first deploy)"
  fi

  warn "rolling back to ${PREVIOUS_TAG}"
  # No pull: the previous images are already on this box, and the registry may
  # be exactly what is broken.
  compose "$PREVIOUS_TAG" up -d --remove-orphans \
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
