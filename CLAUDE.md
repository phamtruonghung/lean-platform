# CLAUDE.md

Read `AGENTS.md` at the repo root first. It holds the conventions that apply
to every agent working in this repo, regardless of harness — domain
vocabulary, layout, how to run the checks, hard rules, the two test seams,
module shape, and workflow. Nothing in this file duplicates it.

## Agent skills

### Implementation agents

Implementation work is delegated to the `coder` subagent (Sonnet), which
escalates to the `advisor` subagent (Opus) when stuck. This holds even when
another skill is driving the work — a skill's procedure says what happens, not
who does it. See `docs/agents/implementation-agents.md`.

### Issue tracker

Issues live as GitHub issues, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles are used verbatim as label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.
