#!/bin/sh
# Design/a11y gate for this repo — wrapper only, the engine lives on the host.
# A host without the engine prints a visible SKIP and exits 0: the gate must
# never block a machine that does not have it (GitHub-hosted runners, a fresh
# container). Docs: skill `design-gate`.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENGINE=${DESIGN_GATE:-/root/.hermes/skills/software-development/design-gate/scripts/design_gate.py}
if [ ! -f "$ENGINE" ]; then
  echo "SKIP: design gate not installed (no $ENGINE) — run it on a host that has it"
  exit 0
fi
exec python3 "$ENGINE" --path "$ROOT" "$@"
