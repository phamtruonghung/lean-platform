# A leaner shift-handover form

**Status:** design note (a recommendation, not a decision). The shape proposed
here needs a product decision before anything is built; it is tracked in the
companion GitHub issue (#355). The decision that follows should be recorded as
an ADR.

This is a rewrite of the first draft of this note. That draft described the
handover as "greenfield" — that premise was false. The Platform already ships
the shift-handover form, and the owner's complaint is exactly right about the
real code: the form makes the writer cover every active Asset before it will
submit. This note now cites that code by file and line, and states precisely
what the recommended shape would change.

## The form today

The form this note re-shapes is on `origin/main`, shipped in #348–#351 and
described by ADR-0054 and `docs/research/shift-handover.md`. It is not
hypothetical.

- **The Screen** is `frontend/lib/production/shift_handover_screen.dart`, at
  `/production/sections/:orgUnitId/handover/:shiftInstanceId`. Its header names
  the six blocks, in the order the paper form is walked: the numbers the shift
  closed on, one Machine status line per Asset, the Change points grouped by
  the 4M, the Section's open Actions and their dispositions, the handover
  evidence, and Submit last (`shift_handover_screen.dart:1-18`).
- **The record** is `backend/src/modules/production/handovers.js` — one record
  per Section per shift instance (ADR-0054), with `shift_handover_machine_lines`,
  `shift_handover_change_points` and `shift_handover_actions` beside it
  (`backend/migrations/1802900000000_production-shift-handovers.js:51-174`).
- **The client models and state** are `frontend/lib/production/handover.dart`
  (`SectionAsset`, `MachineLine`, `ShiftHandover`, `HandoverRefusal`),
  `handover_vocabulary.dart`, and `shift_handover_bloc.dart`.
- **The glossary already carries it:** `CONTEXT.md` defines Shift handover
  (`:510`), Machine status line (`:520`), Change point (`:527`), Handover
  acknowledgement (`:536`) and Carried action (`:545`).

## The problem: where the picks are forced

Two concrete places, cited.

**1. The render forces one row per Asset, with no opt-out.**
The Machines block is headed "One line per Asset in the Section"
(`shift_handover_screen.dart:210`), and `:211-221` renders a `_MachineRow` for
every element of `state.assets` — there is no "not applicable / skip" affordance.
That list is "the Section's active Assets: one Machine status line row each"
(`shift_handover_bloc.dart:112-113`), loaded by `fetchSectionAssets`
(`shift_handover_bloc.dart:202`) from `listSectionAssets`
(`handovers.js:1297-1311`) over `SECTION_ASSETS_SQL`, whose predicate is
`WHERE a.is_active AND au.path <@ section.path` (`handovers.js:424-430`).
`SectionAsset` says it outright: "a machine the handover owes a line for"
(`handover.dart:293-306`).

Each `_MachineRow` (`shift_handover_screen.dart:425-584`) is itself a set of
picks: an 8-value state dropdown and a 7-value abnormality dropdown
(`handover_vocabulary.dart:32-54`, mirrored from `handovers.js:204-211`), plus a
note (required the moment the state is not normal running), a "what to watch"
field and a walked checkbox. The scale is real, not a toy: the Self-Closing
section's Cutting MTU area is seeded with 17 active machines
(`dev/seed-relats-vietnam.mjs:122-123`), so a complete handover is 17 machine
picks plus the change points and actions, every shift.

**2. Submit refuses an incomplete handover.**
`submitHandover` calls `requireComplete` before it seals the draft
(`handovers.js:537-540`). `requireComplete` (`handovers.js:438-524`) runs the
anti-join that is the not-lean rule: every active Asset with no row in
`shift_handover_machine_lines` lands in `missingAssets` (`handovers.js:439-447`),
and unless all four gap lists are empty (`handovers.js:496-499`) it throws
`409 INCOMPLETE_HANDOVER` naming everything at once (`handovers.js:521`). The
client renders that as `HandoverRefusal` (`handover.dart:385-430`, `missingAssets`
at `:390`, parsed at `:404-410`), and `_RefusalPanel` puts "No machine status
line for …" at the top of the form (`shift_handover_screen.dart:301-347`, the
message at `:311`).

The rule is also written into the spec, in three places: ADR-0054 — "Every
active Asset in the Section gets a machine status line … The check runs at
submit and refuses with the assets it is missing" (ADR-0054, `:74-79`); the research
— "Submit requires every active Asset in the Section to have a status line"
(`docs/research/shift-handover.md:187`, rule 3); and the glossary — "Every active
Asset in the Section has one, which is what makes 'the machine nobody mentioned'
impossible" (`CONTEXT.md:520-524`).

So "not lean" is precise: the note and the four other blocks wait on 17 machine
picks the writer must make even when nothing changed. The machine status lines
are the one block of the six that is not already lean — the frozen snapshot is
derived, not typed (`SNAPSHOT_SQL`, `handovers.js:316-404`), the change points
are answered by one declaration or a few rows, and only the Section's open
Actions need a disposition. Only the machines demand full coverage.

## What a handover is for

Two things, and only two:

1. **Continuity** — the incoming shift knows what happened while they were not
   there.
2. **Attention** — the incoming shift knows what to watch: an open Breakdown, an
   Asset running badly, a Quality issue being contained, carry-over work.

Both are carried by what the writer says. The machine list is the *evidence*
behind it, and the Platform already records most of that evidence itself —
`downtime_events` keyed by `shift_instance_id` and `asset_id`, with a `source`
that already anticipates a machine feed (`1756000000000_baseline.js:1826,1844`),
and the frozen snapshot the form already shows. The writer should not be asked
to transcribe it back.

## Candidate shapes

The question is now narrower than the first draft posed: it is not "what should
a whole new handover form look like", it is "how should the Machines block
work". The three candidate shapes re-shape that one block.

### Shape 1 — Note first, machine tags optional

Drop the mandatory per-Asset rows. The note is the only required input, rendered
first and full width; an optional "Assets referenced" field below it is a
search-as-you-type pick (the shared widget, per ADR-0023) the writer may skip.
An empty machine list is a valid, complete handover.

- **Pros:** the leanest possible form; the note is never blocked.
- **Cons:** loses the structured per-Asset trail entirely; an Asset can quietly
  fall out of every handover.

### Shape 2 — Note first, with the machine context derived (recommended)

Shape 1's note, plus a read-only **breakdown summary** attached to the same
shift. The writer never types machine status: it is already there. The summary
lists, for the shift just ended, the Assets that actually mattered — the
open/unclassified Downtime and Breakdowns from the Platform's own
`downtime_events` for that shift instance, and (optionally) the produced/scrapped
pieces and abnormal-stop ranking that mtu-dashboard already computes per machine
and shift. A machine with nothing to report does not appear; a machine that
appears can carry a one-line comment if the writer has something to add, and the
note stays the only required input.

- **Pros:** removes the machine picks entirely *and* gives the incoming shift
  real context; the summary is a durable part of the Platform's own record; the
  core of it is already in-platform (`downtime_events`).
- **Cons:** the most build effort of the three; a read-only dependency on
  mtu-dashboard's API for the enrichment half (the Platform's own
  `downtime_events` half has no such dependency).

The leanest form of Shape 2 is **exception-driven**: only Assets with something
abnormal last shift appear, so a normal shift is one note and an empty summary.
That is the version recommended below.

### Shape 3 — Note, with a link/embed to the mtu-dashboard breakdown

Shape 1's note, plus a deep-link (or iframe) to the mtu-dashboard shift
breakdown for that production day. Zero machine entry, lowest integration cost.

- **Pros:** cheapest possible link to the rich per-machine breakdown.
- **Cons:** the machine context never lands in the Platform's own record, so the
  handover history and search lose it; the wall-screen page shows the *current*
  shift rather than the one being handed over, so the writer is back to typing
  machine status by hand.

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

- **Phase 1 (no new data source):** the Machines block stops rendering a
  mandatory row per active Asset and instead renders the Assets that had
  something to hand over, derived from the Platform's own `downtime_events` for
  that shift instance. The note never waits on a machine.

- **Phase 2 (the mtu-dashboard link):** a read-only fetch that enriches the
  summary with what mtu-dashboard computes but the Platform does not yet hold —
  produced/scrapped pieces and the abnormal-stop ranking per machine and shift.
  Fetch at handover time (`/api/analysis?day=…`, `/api/wincc/history`), store the
  snapshot, and fail soft: if mtu-dashboard is unreachable, the form says
  "machine summary unavailable — retry or enter it" and the note still submits.

Why exception-driven: a handover's machine context matters only where something
was abnormal. A machine that ran clean has nothing to hand over. Deriving the
context means the writer confirms and annotates rather than transcribes, which
is the lean definition of the job.

## What changes, precisely

Under the recommended shape, against the code cited above:

**`machineLines`** — the frontend `ShiftHandover.machineLines`
(`handover.dart:216`) and the backend `shift_handover_machine_lines` table —
stop being one row per active Asset. A row exists only for an Asset with
something to hand over, seeded from `downtime_events` for the shift instance
(open/unclassified/classified stops, keyed by `shift_instance_id`/`asset_id`),
optionally enriched by the mtu-dashboard abnormal-stop ranking. A normally
running machine produces no row; its silence is the record. The writer confirms
and annotates the derived rows rather than transcribing 17 states.
`lineFor(assetId)` (`handover.dart:230-235`) stays, but looks up a sparser list.

**`missingAssets`** — this is the refusal field that makes the form not lean. It
is removed: delete the `NOT EXISTS` anti-join in `requireComplete`
(`handovers.js:439-447`) and its `missingAssets` clause in the refusal
(`handovers.js:502-504`), and remove `HandoverRefusal.missingAssets`
(`handover.dart:390`, `:404-410`) and the "No machine status line for …" line in
`_RefusalPanel` (`shift_handover_screen.dart:311`). The completeness rule narrows
from "every active Asset has a line" to "the note is written, and every Asset
with an open abnormality shown in the summary is disposed of (or confirmed
normal)". The other three gap lists — `incompleteLines`, `unansweredBlocks`,
`undispositionedActions` — stay, because they are already exception-driven: a
non-normal-running line still owes a note and a reference, the 4M block still
owes an answer or "none this shift", and the open Actions still owe a
disposition.

**ADR 0054** — the decision "Every active Asset in the Section gets a machine
status line … refuses with the assets it is missing" (ADR-0054, `:74-79`) is
amended by a new ADR that records the exception-driven completeness rule. The
half of that decision about a non-normal-running line carrying a reason and a
reference survives (it is the `incompleteLines` rule); the half about every
active Asset getting a line is the part that goes. The same amendment lands in
two other places: `docs/research/shift-handover.md:187` (rule 3) and the
glossary entry "Machine status line" — "Every active Asset in the Section has
one …" (`CONTEXT.md:520-524`) drops that sentence in favour of "an Asset with an
abnormality has one".

**Untouched:** the frozen snapshot block is already the "numbers derived, not
typed" shape (`SNAPSHOT_SQL`, `handovers.js:316-404`), and the change points,
carried actions and evidence blocks keep their own — already exception-driven —
completeness.

## Where it lives

Correction to the first draft: the handover does **not** need a new home. It
already lives on the shift instance — `shift_handovers.shift_instance_id`, "one
record per Section per shift instance" (ADR-0054), reached by its own
Destination and Screen. This is a re-shape of an existing record, not a new
record, and the schema change is narrower than the first draft implied: no new
table is necessarily required, because the change is to the completeness rule
and to how the machine lines are derived. A migration is still a one-way door,
so this note remains a recommendation rather than a ticket to change the schema
— but the change it recommends is smaller, not larger, than the first draft
suggested.

## Product decisions to make

1. Is exception-driven acceptable — a normally running machine produces no line
   (recommended) — or must every active Asset still be shown so nothing is
   skipped without notice?
2. Should the machine context come from the Platform's own `downtime_events`
   only (Phase 1), or also from mtu-dashboard (Phase 2)? If the latter, is a
   read-only fetch acceptable, or must it be a sync?
3. What does completeness require once `missingAssets` goes: the note only, or
   the note plus a disposition for each derived abnormal Asset?
4. Glossary wording: the "Machine status line" entry must lose "Every active
   Asset in the Section has one" — confirm the replacement wording and its
   `_Avoid_` list (the first draft's "handover note" term is not needed; the
   record already has a name).

## References

- `frontend/lib/production/shift_handover_screen.dart` — the six blocks
  (`:1-18`); the forced per-Asset render (`:210-221`); `_MachineRow` and its
  picks (`:425-584`); `_RefusalPanel` ("No machine status line for …", `:301-347`).
- `frontend/lib/production/handover.dart` — `SectionAsset` ("a machine the
  handover owes a line for", `:293-306`); `lineFor` (`:230-235`); `HandoverRefusal`
  (`:385-430`).
- `frontend/lib/production/shift_handover_bloc.dart` — `assets` ("one Machine
  status line row each", `:112-113`); `fetchSectionAssets` (`:202`).
- `frontend/lib/production/handover_vocabulary.dart` — 8 states, 7 abnormality
  types (`:32-54`).
- `backend/src/modules/production/handovers.js` — `SECTION_ASSETS_SQL`
  (`:424-430`); `requireComplete` (`:438-524`) and its `missingAssets` anti-join
  (`:439-447`); `submitHandover` (`:537-540`); `listSectionAssets`
  (`:1297-1311`); `SNAPSHOT_SQL` (`:316-404`).
- `backend/migrations/1802900000000_production-shift-handovers.js` —
  `shift_handover_machine_lines` and its `asset_unique UNIQUE (handover_id,
  asset_id)` (`:120-146`).
- `backend/migrations/1756000000000_baseline.js` — `downtime_events` keyed by
  `shift_instance_id` and `asset_id`, with `source`
  (`manual`/`plc`/`scada`/`import`/`api`, default `manual`) (`:1826,1844`).
- `dev/seed-relats-vietnam.mjs` — the Self-Closing section's 17 Cutting MTU
  machines, all active (`:122-123`).
- `CONTEXT.md` — Shift handover (`:510`), Machine status line (`:520`), Change
  point (`:527`), Handover acknowledgement (`:536`), Carried action (`:545`).
- ADR-0054 (`:74-79`), `docs/research/shift-handover.md` (`:187`), ADR-0023 (a
  value with a known set is chosen, never typed).
- mtu-dashboard README — `/api/analysis`, `/api/wincc/history`, `/api/shift`,
  `/api/maintenance`; the per-machine, per-shift breakdown.
