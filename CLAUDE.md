# CLAUDE.md

## Agent skills

### Issue tracker

Issues live as GitHub issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles are used verbatim as label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Implementation agents

Implementation work is delegated to the `coder` subagent (Sonnet), which
escalates to the `advisor` subagent (Opus) when stuck. This holds even when
another skill is driving the work — a skill's procedure says what happens, not
who does it. See `docs/agents/implementation-agents.md`.
