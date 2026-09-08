---
status: accepted
---

# A Work order transition is a route of its own

Date: 2026-09-08

Issue #63 ("Work it: start, complete and cancel") gives a supervisor three
ways to move a Work order forward: start it, complete it with a note of what
was found, or cancel one raised in error. Three decisions made while building
that are recorded here, because without them each reads as an oversight
rather than a choice the next person touching this file might "fix": why
three routes instead of one, why the Employee a Work order is handed to gets
no special standing on these routes, and why cancelling writes to the same
column completing does.

## The decision

### One route per transition, not `PATCH /work-orders/:id { status }`

`POST /work-orders/:id/start`, `POST /work-orders/:id/complete` and
`POST /work-orders/:id/cancel` each do one thing: resolve the Work order
(`requireWorkOrderWriteScope`, shared with `PUT /assignee`), check a write
Grant reaches its Org Unit, and hand off to the matching function in
`work-orders.js`. None of the three reads a `status` field from the request.

The rejected alternative was a single `PATCH /work-orders/:id { status }`.
Each transition has a different precondition (`approved → in_progress`,
`in_progress → completed`, `{approved, in_progress} → cancelled`) and a
different body (none, `{ note }`, `{ reason }`), so one route would need a
three-way branch on a client-chosen string — and a `status` field is an
invitation for a caller to post `'closed'` or `'on_hold'`, statuses this
slice deliberately does not offer, which the route would then have to refuse
by name instead of never accepting in the first place. Three narrow doors
cost three route handlers instead of one; that cost is accepted.

`POST`, not `PUT`: none of the three is an idempotent replacement of a value
the way `PUT /work-orders/:id/assignee` genuinely is. A second `start` on an
already-started Work order is an error, not a no-op that leaves the row
unchanged.

Every transition is guarded inside `work-orders.js`, not in the route and not
by a new database constraint. The route's job is request shape and
authorization; whether `approved → completed` is a legal move is a fact about
a Work order, which belongs to the file that already owns every other fact
about one. A new CHECK constraint would be a migration this ticket does not
need — the two constraints already on `work_orders`
(`work_orders_actual_window`, `work_orders_completed_has_end`) stay backstops
that would refuse a malformed write anyway, not the primary defence. The
primary defence is `SELECT status ... FOR UPDATE` inside the transaction,
exactly the lock-then-check shape `approveAccount`
(`backend/src/modules/people/service.js:290-353`) already uses: two callers
racing `start` on the same row serialize, and the loser reads the
now-current status and gets the 409.

### The assignee holds no privilege of their own — yet

`PUT /work-orders/:id/assignee` (#62) names who a Work order is handed to,
but that Employee gets no special standing on any of the three transition
routes. Starting, completing or cancelling a Work order still requires the
caller to hold a write Grant reaching the Work order's Org Unit, with no
carve-out for "the assignee may act on their own job". A technician acting on
a job assigned to them, with no Grant of their own, is #77's problem — the
floor-facing surface this Platform does not have yet — and ADR-0016 already
anticipates a shared floor device for exactly that case. Building an
assignee-exception into this route now would mean guessing at #77's shape
before it exists.

One consequence worth naming: an unassigned Work order can still be started
and completed. `assigned_to` is never read on any of the three transition
paths, on purpose — the issue that introduced them says so explicitly, and a
named integration test (`an unassigned work order can be started and
completed`) pins it.

### `completeWorkOrder` and `cancelWorkOrder` share one column

`work_orders` has no `cancellation_reason` column and no `cancelled_at`. The
only free text on the row besides `description` (which is filled *before*
the work, not a record of what happened) is `completion_note` — "Diagnosis,
recorded on completion" per its own comment in the baseline migration.

The issue's own brief asks for `cancelWorkOrder(workOrderId, { reason })`.
Two options short of a schema change were considered against accepting and
persisting it:

- Accept `reason` and discard it. Rejected: asking someone to type why a job
  is being cancelled and then throwing the answer away is a lie told by the
  interface.
- Accept no reason at all. Satisfies the acceptance criterion with the least
  code, but contradicts the issue's own brief, which explicitly names a
  reason as part of cancelling.

What was chosen instead: `cancelWorkOrder` accepts an **optional** `reason`
and writes it to `completion_note`. `status` already disambiguates which kind
of closing note a given row's `completion_note` is — `completed` means "what
was found", `cancelled` means "why this was called off" — so one column
carries two related facts rather than the schema growing a second column that
means almost the same thing. `reason` is optional, unlike `completeWorkOrder`'s
`note` (which is required — see the comment on that function): undoing a
mistake should not demand prose, and demanding a reason to cancel a Work
order raised in error is friction a plant does not need. Cancelling never
touches `actual_end`: a cancelled job was never finished, and stamping one
would put a fabricated duration on a row that never did the work.
`COALESCE($2, completion_note)` on the write means cancelling without a
reason never wipes a note that was already there.

## Consequences

A schema change is still available later if #73 or #75 ever need a
dedicated `cancellation_reason` column separate from a completion note — this
decision does not close that door, it just declines to open it before
anything needs it (the Expand-later pattern, ADR-0007). Anyone reading
`cancelWorkOrder` and expecting a `cancellation_reason` column should read
this file rather than "fix" the gap with a migration nobody asked for.

The three routes are, and are expected to stay, the only way a Work order's
`status` moves after it is raised. If a future ticket needs a fourth
transition (moving into `on_hold`, say), the same shape applies: a narrow
route of its own, guarded in `work-orders.js` over a locked row, not a widened
`status` field on an existing route.
