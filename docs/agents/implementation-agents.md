# Implementation agents

Implementation work in this repo is delegated, not done inline by the main
session.

## The pair

- **`coder`** (Sonnet) — writes, edits and debugs code. Defined at user scope in
  `~/.claude/agents/coder.md`.
- **`advisor`** (Opus) — read-only. Diagnoses and directs when the coder is
  stuck. Defined in `~/.claude/agents/advisor.md`.

The coder holds the `Agent` tool and calls the advisor itself, so escalation is
a real tool call rather than a convention. Its hard ceiling is **two** failed
attempts at the same error; it also escalates for genuine design trade-offs and
for changes touching a public interface, schema, migration, or auth. The
expensive model is therefore paid for only at the moments where reasoning pays.

## Skills do not suspend this

Skills — including the `mattpocock-skills:*` set (tdd, diagnosing-bugs,
prototype, codebase-design, …) — supply a procedure. The procedure describes
**what** work happens, not **who** does it. Hand the procedure to the `coder`
agent and have it carry the steps out.

## What the main session keeps

Planning and task splitting, reading code to answer questions, reviewing the
coder's output, and all git, GitHub, issue and deploy work. Trivial one-liners
may be done directly, but that should be stated rather than left implicit.
