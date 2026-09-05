---
status: accepted
---

# A work order links back to the request that produced it

Date: 2026-09-05

Issue #72. CONTEXT.md's own "Work order" entry already defines itself against
a word it refuses to be: a **request** is what anyone on the floor asks
maintenance for, and maintenance may decline it; a **work order** is the
commitment that follows one, or that maintenance raises for itself. The
baseline schema already carries `maintenance_requests` — its own table, a
`request_no`, a `status` running `new` through `accepted` or `rejected`, a
`duplicate_of_id` for the row it turns out to duplicate — and it has never
held a row: nothing in this Module has read or written it since the migration
that created it. The alternative this ADR considers, and rejects, is the shape
that table's own emptiness has invited so far: accepting a request simply
creates a work order and closes the request out, so the two records ever meet
at the single moment of acceptance, and everything the request was worth
before that is thrown away as soon as its job exists.

## The decision

A work order carries a reference to the request that produced it, when one
did. `work_orders.maintenance_request_id` — already present in the baseline
schema, its own comment reading "Which request, if any, asked for this. A PM
work order has none." — is the join this ADR asks the write path to actually
populate on acceptance, rather than leaving it an unused column the way the
whole table around it has sat unused.

This decision requires no migration. `maintenance_request_id` already exists
in the baseline schema, so this ADR ratifies a shape the schema already
chose rather than introducing a new one. The alternative this ADR rejects,
accept-creates-and-closes, would have left that column permanently null — a
schema does not usually carry a foreign key commented for exactly the write
path this ADR restores and then go on to never populate it, and that
permanent nullness under the rejected alternative is itself evidence the
schema's authors did not intend that shape. Declining a request and
identifying it as a duplicate are already fully modelled elsewhere in the
same table — `status`'s own CHECK constraint running through `rejected` and
`duplicate`, a `rejection_reason` column, and a `duplicate_of_id` pointing at
the request that survives — and none of that modelling is disturbed or
contradicted here: this ADR concerns only what happens to the reference once
a request is accepted, not how a request is declined or deduplicated.

## Why keep the request alive rather than let acceptance close it out

Two things are worth an answer the closed-request alternative cannot give.
The requester who raised something from the floor and never touches the work
order screen still wants to know what happened to what they raised — "what
happened to the thing I raised" is a question a status field answers today
("accepted") and a job number does not; following the reference is what lets
that same person land on the actual job, see who it is assigned to and
whether it is done. And once every accepted request is one hop from the work
order it produced, "how much of our work comes from the floor rather than
from planning" becomes an answerable question rather than a guess — a real
reliability question, and one the planned-versus-unplanned split this schema
already reports (the corrective/preventive/predictive split behind the
Delivery numbers) already gestures at without being able to answer directly,
since a corrective job raised from a request and a corrective job maintenance
decided to raise itself look identical to that split today.

## Consequences

A work order now has two possible origins, and every surface that reads work
orders has to cope with both rather than assuming one shape. One raised
directly by maintenance has no request behind it at all — the reference stays
nullable, exactly as the existing column comment already states, and "raised
directly" is not an error case a nullable reference merely tolerates but the
majority shape a PM schedule or an engineer's own judgement will keep
producing. This is not a parent-child relationship: closing, rejecting or
otherwise disposing of the request does not delete or invalidate the work
order it produced, and nothing about the work order's own lifecycle is
allowed to depend on the request continuing to exist in whatever status it
was in at acceptance. The reference points backward, once, at the moment of
acceptance; it is not a live link the two records keep negotiating
afterward.
