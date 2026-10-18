#!/usr/bin/env bash
#
# Run the pinned Flutter image's three checks — pub get, analyze, test — against
# a copy of frontend/, under CPU and memory caps.
#
#     ./scripts/flutter-ci.sh                            # the full run
#     ./scripts/flutter-ci.sh test/accounts_test.dart     # args go to `flutter test`
#     ./scripts/flutter-ci.sh --update-goldens            # see WORK_DIR below
#     CPUS=8 MEMORY=6g JOBS=4 ./scripts/flutter-ci.sh
#
# Why this exists instead of the bare `docker run` it replaces: uncapped, a run
# takes the whole machine with it. `flutter test` runs its suites in parallel —
# package:test's default concurrency is `max(1, Platform.numberOfProcessors ~/ 2)`,
# which is six concurrent Dart VMs on a 12-core host — and each suite is a full VM
# boot of the Flutter test framework, layered on a `frontend_server` compile that
# holds close to 1 GB. Inside a container with no limits that borrows every core it
# can, the run starves everything else on the machine. Measured on the repo's
# 12-vCPU dev container: load average 139 and ~1,260 tasks during a full run, with
# an interactive agent session losing its WebSocket heartbeat (45 s deadline) and
# reporting a dropped connection for the duration.
#
# The caps default low on purpose; raise them on a machine that is otherwise idle.
#
# Env:
#   CPUS=4                    --cpus for the container
#   MEMORY=4g                 --memory and --memory-swap for the container
#   JOBS=2                    `flutter test -j`: suites allowed to run at once
#   IMAGE=ghcr.io/cirruslabs/flutter:3.44.0
#                             keep this pinned — goldens are Skia-version-sensitive
#                             (frontend/test/GOLDENS.md)
#   FRONTEND=frontend         app directory, relative to the repo root
#   PUB_CACHE_VOLUME=lean-platform-pub-cache
#                             named volume for ~/.pub-cache so `pub get` is not
#                             re-downloading every run; set to "" to use the image's
#                             own (throwaway) cache
#   WORK_DIR=<dir>            put the working copy in <dir>/app and DO NOT delete it
#                             afterwards — use this when the run produces files to
#                             copy back out (`--update-goldens`)
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-4g}"
JOBS="${JOBS:-2}"
IMAGE="${IMAGE:-ghcr.io/cirruslabs/flutter:3.44.0}"
FRONTEND="${FRONTEND:-frontend}"
PUB_CACHE_VOLUME="${PUB_CACHE_VOLUME-lean-platform-pub-cache}"
WORK_DIR="${WORK_DIR:-}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

if [ ! -d "$FRONTEND" ]; then
  echo "no $FRONTEND/ under $(pwd) — run this from the repo root" >&2
  exit 1
fi

# Work against a COPY. `flutter pub get` pointed at a live bind-mount of
# frontend/ rewrites pubspec.lock to whatever the container's SDK resolves, which
# can break the next real build (AGENTS.md §3).
keep_copy=0
if [ -n "$WORK_DIR" ]; then
  work="$WORK_DIR"
  mkdir -p "$work"
  keep_copy=1
else
  work="$(mktemp -d "${TMPDIR:-/tmp}/flutter-ci.XXXXXX")"
fi
app="$work/app"

if [ -e "$app" ]; then
  echo "$app already exists — remove it, or point WORK_DIR somewhere else" >&2
  exit 1
fi
if [ "$keep_copy" = 0 ]; then
  trap 'rm -rf "$work"' EXIT
fi

echo "== copying $FRONTEND/ -> $app (never bind-mount the real tree)"
cp -r "$FRONTEND/." "$app"

volume_args=()
if [ -n "$PUB_CACHE_VOLUME" ]; then
  volume_args=(-v "$PUB_CACHE_VOLUME:/root/.pub-cache")
fi

echo "== caps: cpus=$CPUS memory=$MEMORY test-jobs=$JOBS image=$IMAGE"
[ "$keep_copy" = 1 ] && echo "== working copy kept at $app"

# The container's own bash takes "$1" as the job count and forwards the rest to
# `flutter test`, so quoted args (a glob, a test name) survive intact.
docker run --rm \
  --cpus="$CPUS" \
  --memory="$MEMORY" --memory-swap="$MEMORY" \
  -v "$app:/app" \
  ${volume_args[@]+"${volume_args[@]}"} \
  -w /app \
  "$IMAGE" \
  bash -c '
    set -euo pipefail
    timeout 900 flutter pub get
    timeout 900 flutter analyze
    timeout 2700 flutter test -j "$1" "${@:2}"
  ' _ "$JOBS" "$@"
