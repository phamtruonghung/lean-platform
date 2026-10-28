# A leaner shift-handover form

**Status:** design note (a recommendation, not a decision). The shape proposed
here needs a product decision before anything is built; it is tracked in the
companion GitHub issue (#355, "Leaner shift-handover form: note first, derive
the machine context, don't pick it"). The decision that follows should be
recorded as an ADR.

## The problem

The shift-handover form is not lean: a supervisor must choose a lot of machines
before they are allowed to write a note. That is the wrong way round. The note
is the whole point of a handover — it carries what the outgoing shift needs the
incoming shift to know. The machines are only context, and making the note wait
on them turns a one-minute handover into a walk down the machine list.

One finding worth stating plainly, because it changes the shape of the work: the
Platform has **no "shift handover" form today**. There is no handover route,
Screen, table or `CONTEXT.md` entry. What the ask calls a handover form is
something the plant does today elsewhere (a paper form or another system), and
this note is a recommendation for the lean shape it should take when it lands
here — not a fix to an existing form. If there is an existing form this note
has missed, the shape below still applies: it describes how the machine context
should be *derived*, not picked.

## What a handover is for

Two things, and only two:

1. **Continuity** — the incoming shift knows what happened while they were not
   there.
2. **Attention** — the incoming shift knows what to watch: an open Breakdown, an
   Asset running badly, a Quality issue being contained, carry-over work.

Both are carried by the note. The machine list is the *evidence* behind the
note, and the Platform already records most of that evidence itself.

## Candidate shapes

### Shape 1 — Note first, machine tags optional

A single required free-text note, rendered first and full width, plus an
optional "Assets referenced" field below it. The supervisor writes the note and
submits; tagging an Asset is a search-as-you-type pick (the shared widget, per
ADR-0023) they may skip entirely. An empty Asset list is a valid, complete
handover.

- **Pros:** the leanest possible form; ships with no new data dependency; the
  note is never blocked.
- **Cons:** loses the structured per-Asset trail the forced pick-and-acknowledge
  produced; an Asset can quietly fall out of every handover.

### Shape 2 — Note first, with the machine context derived (recommended)

Shape 1's note, plus a read-only **breakdown summary** attached to the same
shift. The supervisor never types machine status: it is already there. The
summary lists, for the shift just ended, the Assets that actually mattered —
open/unclassified Downtime and Breakdowns from the Platform's own
`downtime_events`, and (optionally) the produced/scrapped pieces and abnormal
stops that mtu-dashboard already computes per machine and shift. A machine with
nothing to report does not appear; a machine that appears can carry a one-line
comment if the supervisor has something to add, and the note stays the only
required input.

- **Pros:** removes the machine picks entirely *and* gives the incoming shift
  real context; the summary is a durable part of the Platform's own record; the
  Platform already records the core of it (`downtime_events`, keyed by
  `shift_instance_id` and `asset_id`, with a `source` of `plc`/`scada`/`api`
  that already anticipates a machine feed).
- **Cons:** the most build effort of the three; a read-only dependency on
  mtu-dashboard's API for the enrichment half (the Platform's own `downtime_events`
  half has no such dependency).

The leanest form of Shape 2 is **exception-driven**: only Assets with something
abnormal last shift appear, so a normal shift is one note and an empty summary.
That is the version recommended below.

### Shape 3 — Note, with a link/embed to the mtu-dashboard breakdown

Shape 1's note, plus a deep-link (or iframe) to the mtu-dashboard shift
breakdown for that production day. Zero machine entry, lowest integration cost.

- **Pros:** cheapest possible link to the rich per-machine breakdown.
- **Cons:** the machine context never lands in the Platform's own record, so the
  handover history and search lose it; the wall-screen page shows the *current*
  shift rather than the one being handed over, so the supervisor is back to
  typing machine status by hand.

## Trade-offs

| | Shape 1 · note-first, tags optional | Shape 2 · note-first, context derived *(recommended)* | Shape 3 · note + link/embed |
|---|---|---|---|
| **Required inputs** | the note | the note | the note |
| **Machine picks** | none (optional tags) | none (context derived) | none |
| **Machine context** | only what the writer types | Platform `downtime_events` + optional mtu-dashboard breakdown | mtu-dashboard page, not stored |
| **Durable in the Platform's record** | note + tags | note + summary snapshot | note only |
| **Incoming shift gets machine context** | no | yes, pre-filled | yes, but only by following the link |
| **Build effort** | low | highest | lowest |
| **Data coupling** | none | read-only API call to mtu-dashboard (enrichment half only) | none in the data model, a runtime embed |
| **Fails when mtu-dashboard is down** | n/a | soft — summary marked "unavailable, retry or type it"; note still submits | hard — blank/broken embed |
| **Signal lost** | structured per-Asset coverage | nothing, if the summary is complete | structured per-Asset coverage |

## Recommendation

**Shape 2, exception-driven, delivered in two phases.**

- **Phase 1 (no new data source):** a handover note attached to the shift
  instance, note-first with optional Asset tags, drawn from the Platform's own
  `downtime_events` for that shift. This alone removes the "pick machines before
  you can note" problem, because the note never waits on a machine.

- **Phase 2 (the mtu-dashboard link):** a read-only fetch that enriches the
  summary with what mtu-dashboard computes but the Platform does not yet hold —
  produced/scrapped pieces and the abnormal-stop ranking per machine and shift.
  Fetch at handover time (`/api/analysis?day=…`, `/api/wincc/history`), store
  the snapshot, and fail soft: if mtu-dashboard is unreachable, the form says
  "machine summary unavailable — retry or enter it" and the note still submits.

Why exception-driven: a handover's machine context matters only where something
was abnormal. A machine that ran clean has nothing to hand over. Deriving the
context means the supervisor confirms and annotates rather than transcribes,
which is the lean definition of the job.

## Where it lives

The handover belongs to the **shift instance**, not a new Screen and not the
Org Unit or Site. The Attendance sheet is already "one record per shift
instance" and `attendance_sheets.shift_instance_id` is `UNIQUE`
(ADR-0040); a handover is the outgoing shift's note about that same instance, so
it should sit on that record, keyed the same way — a `shift_handovers` note (or
a handover column on the sheet) rather than a new Destination with its own
route, Screen and Bloc. The incoming supervisor already opens the Attendance
sheet for their shift; the previous shift's handover is the next thing they
need, reachable through the same picker.

This is a **schema change** (a new table or column, keyed by
`shift_instance_id`), so it is deliberately *not* made in this note's own change
— a migration is a one-way door and this note is a recommendation, not a ticket
to change the schema.

## Product decisions to make

1. Is the handover a note on the shift instance (recommended), or a new
   Destination?
2. Should machine context come from the Platform's own `downtime_events` only,
   or also from mtu-dashboard (Phase 2)? If the latter, is a read-only fetch
   acceptable, or must it be a sync?
3. Exception-driven (only abnormal Assets appear) — acceptable, or must every
   Asset be shown so nothing is skipped without notice?
4. A new glossary entry is needed: "handover note" (and its Vietnamese label,
   *bàn giao ca*) — confirm the term and its `_Avoid_` list.

## References

- `CONTEXT.md` — Site, Org Unit, shift instance, Asset, Downtime, Breakdown,
  Attendance sheet.
- ADR-0016 (floor device), ADR-0017 (production day), ADR-0040 (Attendance
  confirmed once per shift instance), ADR-0023 (a value with a known set is
  chosen, never typed).
- `backend/migrations/1756000000000_baseline.js` — `downtime_events` keyed by
  `shift_instance_id` and `asset_id`, with `source` (`plc`/`scada`/`api`/
  `import`).
- mtu-dashboard README — `/api/analysis`, `/api/wincc/history`, `/api/shift`,
  `/api/maintenance`; the per-machine, per-shift breakdown.
