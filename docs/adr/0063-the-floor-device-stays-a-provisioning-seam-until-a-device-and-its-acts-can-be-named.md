# 0063 — The floor device stays a provisioning seam until a device and its acts can be named

- **Status:** Accepted
- **Date:** 2026-11-15
- **Issue:** #402 (part of #385)

## Context

ADR-0016 decided the shape of a floor-facing surface: a technician signs in on a
shared device at the machine, and — its own words — "a floor-facing surface is
designed as its own surface, never reached by widening a breakpoint down until a
desktop layout happens to fit a tablet".

What the client carries today is the **seam**, not the surface.
`frontend/lib/platform/floor_device_gateway.dart` reads
`--dart-define=FLOOR_DEVICE_CREDENTIAL` and treats a device that carries none as
not registered; ADR-0047 decides what a wrong floor pin does (a backoff window on
the Employee, not on the Account). That is provisioning: it decides whether this
box is allowed to be a floor device, and it says nothing about what to draw on
one.

What it does not carry:

- the Shell is the desktop one. `docs/design-language.md:71-72` has the two widths
  it chooses between — 260 expanded, 64 as an icon rail below 700 — and the
  narrowest content box the Shell ever leaves a page is **440** (`:78-86`). So
  "narrow" in this repository today means a desktop page on a small window, not a
  surface designed for a hand at a machine;
- every target in the design law is `AppTouchTarget.min`, **44** (`:177`) — a
  pointer target, not a gloved one;
- the **44** destinations render in one grouped list (ADR-0020,
  `frontend/lib/platform/destinations.dart`'s `platformDestinations`), which is a
  sidebar, and ADR-0016's own terms rule the sidebar out of a floor surface.

The per-Screen programme (S1–S10) makes every Screen hold at 700. That is **not**
the same claim as "the floor device works", and the difference is the whole of
this ADR: a Screen that survives a small window is not a surface designed for the
act a technician performs standing at a machine.

## Decision

**The floor surface is out of scope until somebody can name the device and the
acts.** No floor-designed surface is built in this programme, and — the operative
sentence — **no Screen, and no Shell width, is "the floor surface" merely because
it was made to fit a narrow box.** Widening a breakpoint down until the desktop
layout happens to fit a tablet is exactly the move ADR-0016 forbids, and it stays
forbidden whether it arrives as a media query, as a responsive breakpoint, or as a
slice titled "tablet support".

When it is built, it is ADR-0016's shape: its own route tree, no sidebar, and an
identity mechanism re-confirming the person per action rather than per shift
(which one ADR-0016 deliberately leaves to that ticket), with its own targets.

## Consequences

- `floor_device_gateway.dart` and `FLOOR_DEVICE_CREDENTIAL` remain a provisioning
  seam. Nothing here is promoted into a surface story, and a not-registered device
  showing a not-registered state is the seam behaving, not an unfinished Screen.
- The per-Screen programme is unaffected and keeps its own narrower claim — a
  Screen holds at 700 — which this ADR neither widens nor weakens.
- A future card may re-open this only with two things written in its body: **the
  device** (the tablet or terminal at a named line) and **the acts** (the words for
  what the technician does there). With one and not the other it is a guess, and it
  belongs back at this ADR rather than in a worktree.
- `docs/design-language.md` gains nothing from this ADR: its 700/900/1280 breaks
  and its 44px target stay desktop facts and are not re-labelled "floor-ready".

## Alternatives considered

**A — design the floor surface now.** Rejected on the same ground that produced
this issue: a floor surface designed without the acts is a guess about what the
person at the machine needs on the first screen, and that guess is expensive to
unwind because it becomes a route tree the rest of the client then depends on.

**C — the plant has no tablet; ADR-0016 becomes a historical note.** Rejected as a
stronger claim than the evidence supports. ADR-0016 is accepted, and the
provisioning seam shipping in the client — with ADR-0047's wrong-pin backoff behind
it — is real code built for a device the plant has not yet described. Declaring the
whole decision historical would delete somebody's deliberate work on the strength
of "we have not been told about a tablet", which is the absence of evidence rather
than evidence of absence.
