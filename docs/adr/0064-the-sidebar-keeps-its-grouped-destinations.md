# 0064 — The sidebar keeps its grouped destinations; the guide is the index, not a palette

- **Status:** Accepted
- **Date:** 2026-11-15
- **Issue:** #403 (part of #385)

## Context

The Shell offers every admitted Account a sidebar of destinations grouped by Module
(ADR-0020), and that list has grown: `frontend/lib/platform/destinations.dart`'s
`platformDestinations` holds **44 entries** today. The issue that produced this ADR
was filed at 42, so the count drifted up by two while the question sat open —
Settings among them, the personal-choices Destination added for the language
switch.

ADR-0020's table still lists the ten destinations it was written about; its
actual decision — a Module heading is a label and nothing more, it carries no
address and opens nothing — has not changed, and this ADR leaves it standing.

The per-Screen programme improves each destination's own Screen and does not touch
how a person finds one, so "42 destinations is a lot" was never going to be
answered by that programme. The honest options were a jump-to surface (A), leaving
it (B), or collapsing to Module landings (C).

## Decision

**Leave it (B).** The 44 grouped destinations stay in one list, under ADR-0020's
grouping and its prohibition: a heading never gains an address and never becomes a
landing page.

The discoverability question gets a different answer than a new surface, and that
answer already shipped: `docs/user-guide/README.md` §2 — "Mục lục — 44 màn hình vào
từ cửa" — is an index of **44 screens**, one row per destination, each card
answering *what is this for* and *who may act here* (§1's role matrix, derived from
the permission codes rather than from guesswork). A person who does not know where
a thing lives reads the index and is told which door it is behind.

That is the affordance option A was going to build, in documentation rather than in
a new surface: no Screen, no new route, no keyboard shortcut to maintain, and it
works for the trainer standing next to somebody rather than only for the person at
a keyboard.

## Consequences

- Nothing changes in the Shell, the router or `destinations.dart`.
- The guide's index becomes load-bearing rather than decorative: **a new
  destination ships with its row in `docs/user-guide/README.md` §2 in the same
  pull request**, the way a new Screen already ships with its agent docs. An index
  that falls behind the sidebar is worse than no index, because it is read as
  complete.
- Option A is unfunded rather than rejected: the trigger to revisit is a
  **reported hunt** — the person who reads this list daily saying he looked for a
  named destination and did not find it — and not a count. A palette built on "44
  feels like a lot" would answer a complaint nobody has made.
- ADR-0020's table is left as the record of the destinations that existed when the
  grouping was decided; it is not re-counted here. Its rule about headings is the
  part that still binds, and it is unchanged.

## Alternatives considered

**A — a command palette (Cmd/Ctrl-K) over destinations plus the things a person
names.** Deferred, not rejected. It is one card and one new surface, and it becomes
the right card the moment somebody reports hunting for a destination. Until then it
is a keyboard shortcut nobody asked for, on a floor where the readers are standing
up, and it would ship as a second way to do what the index already does.

**C — collapse to a Module landing per group.** Rejected, and by ADR-0020's own
test. Its "What this costs" section names this exact failure mode: "a later change
that gives a heading an address, or collapses a group behind a click that lands
somewhere, would cross back over #39's original objection while appearing to
respect this ADR." Option C is that sentence. It also makes every destination two
clicks and leaves ADR-0020's grouping justifying nothing at all.
