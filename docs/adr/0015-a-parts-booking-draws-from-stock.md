---
status: accepted
---

# A parts booking draws from stock

Date: 2026-09-05

Issue #75. The baseline schema's own comment on `work_order_parts` states its
scope plainly: "Deliberately not an inventory. There is no stock on hand, no
reorder point and no storeroom: a part here is what was fitted and what it
cost." That is the alternative this ADR reconsiders — a booking that only
records consumption, a line against a work order carrying a quantity and a
cost and nothing upstream of it, `sourced` doing the work of distinguishing
"taken off a shelf" from "bought for this job" without there being a shelf
anywhere in the schema to check against.

## The decision

A parts booking decrements stock — when it draws from stock at all. The
table's own `sourced` column already distinguishes how a part reached the
job, `CHECK (sourced IN ('stores', 'purchased', 'refurbished',
'cannibalised'))`, and this decision applies to exactly one of those four
values. A `stores`-sourced booking is a withdrawal against a quantity the
Platform now keeps, and that quantity has to exist somewhere before the
booking can be checked against it — booking a part this way is no longer
only a cost line recorded after the fact. A `purchased`, `refurbished` or
`cannibalised` booking has no shelf behind it to draw from: nothing was
sitting in this Site's stock to begin with, whether because it was bought
for this job specifically, reconditioned rather than stocked, or lifted off
another Asset entirely, so there is nothing for the booking to decrement.
Those three keep exactly the cost-line-after-the-fact shape the table
already had; only `stores` gains the new behaviour this ADR decides.

## What this pulls into the Platform

This is not a small addition next to the line it replaces, for the `stores`
path. It requires stock levels held per Site, or per store within a Site if
a Site keeps more than one, which is a new kind of record with its own write
surface — receiving stock in, adjusting a count, deciding what a negative
balance even means. It requires an answer for the booking that wants a part
not on hand: refuse it, or let it go negative and treat the shortfall as its
own signal, and either answer is a real design decision this ADR does not
settle by itself. None of this touches a `purchased`, `refurbished` or
`cannibalised` booking, which keeps behaving exactly as it did before this
ADR — a cost line with nothing upstream to check it against, because for
each of those three there genuinely is no shelf to check. And for the
`stores` path it means inventory — stock counts, receipts, reorder
behaviour, whatever the storeroom side of this eventually needs — is now a
substantial body of behaviour that Maintenance depends on, not a side effect
of the parts line staying where it already was. The baseline comment's own
reason for stopping short — that a real inventory "would roughly double this
schema" — was a correct estimate of the cost, not a barrier this ADR fails
to notice; it decides that cost is worth paying for the bookings that
actually draw from stock.

## Getting cost composition right matters more here than it looks

The schema already carries a warning about exactly this kind of mistake, on
the sibling table this decision sits beside. `work_order_labour`'s own
comment: "Maintenance labour cost is therefore a SLICE of COST_LABOUR, never
an addition to it." Labour hours booked against a job are not new money — the
same technician's shift is already costed once, from attendance, and a view
that adds the two together double-counts every technician in the plant.
Parts have always been the schema's one exception to that warning, its own
comment naming them "the one component of maintenance cost that adds"
precisely because nothing upstream costs a part anywhere else. Standing up
stock does not change which side of that line parts sit on — a part booked
against a job, however it was sourced, is still new money against the plant,
not a slice of a number already reported elsewhere. But the `stores` path
alone now carries an extra obligation the other three do not: stock has its
own valuation, its own cost basis per unit on hand, and a booking that
decrements stock has to draw its cost from that basis correctly or it will
report a number that has nothing to do with what actually left the shelf. A
`purchased`, `refurbished` or `cannibalised` booking carries no such
obligation — its cost comes from what was paid or logged for it directly,
with no stock basis in between for that number to drift away from. Getting
the `stores` composition wrong either double-counts, the mistake the schema
already warns against for labour, or misreports what a job actually cost the
plant — and either is worse than the honest gap the current design leaves,
because a wrong number is trusted the way a missing one never is.

## What this does not settle

Whether inventory eventually becomes its own Module, rather than a body of
behaviour Maintenance grows internally, is left open. ADR-0006 already treats
that as a code-seam question — a Module boundary can move without moving any
data, since Modules are code seams and not data seams — not a
data-modelling one, so nothing about where stock levels live today forecloses
moving the behaviour that manages them later.
