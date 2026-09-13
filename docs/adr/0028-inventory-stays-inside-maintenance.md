---
status: accepted
---

# Inventory stays inside Maintenance

Date: 2026-09-13

Issue #80 builds a parts catalogue, stores and stock levels, implementing
ADR-0015's decision that a `stores`-sourced parts booking draws from stock.
ADR-0015 left open whether that behaviour would become a Module of its own or
grow inside Maintenance ("Whether inventory eventually becomes its own Module,
rather than a body of behaviour Maintenance grows internally, is left open").
This records the answer for this slice: it stays inside Maintenance.

## The decision

`parts`, `stores` and `stock_movements`, their domain service (`inventory.js`)
and their routes (`inventory-routes.js`) live under
`backend/src/modules/maintenance/`, mounted at `/api/maintenance`. The client
mirrors the shape under `frontend/lib/maintenance/`. No new Module boundary is
drawn; Maintenance's entry point still exposes only `router` because no other
Module consumes it.

## Why, given ADR-0015 leaned the other way

ADR-0015's own framing anticipated eventual extraction, and on its face the
behaviour is substantial enough to deserve its own seam. The deciding fact is
the write inventory exists to serve. Booking a `stores`-sourced part against a
work order (#75) writes a `work_order_parts` row — Maintenance's record — and
a `stock_movements` row — inventory's record — as one fact. A shelf that
decremented while the cost line vanished, or the reverse, is exactly the
disagreement that makes a stock level untrustworthy, so the two writes have to
share one transaction.

ADR-0006's first clause forecloses the split: an entry point exposes read-only
lookups and predicates, never a write — "a second Module changes its own
records, never another Module's." Were Inventory its own Module, Maintenance
could not record the withdrawal through Inventory's entry point, and Inventory
could not write the booking line through Maintenance's. No placement lets one
Module own both halves of an atomic write that spans the boundary. Keeping
both tables under Maintenance makes the booking a single same-Module
transaction, the same shape `downtime.js`'s `reportBreakdown` already has for
a stoppage and the Work order it raises.

## Consequences

This decides the shape of one slice, not of inventory forever. ADR-0006 makes
a Module boundary a code seam and explicitly cheap to move — no data moves
with it — so if a consumer that does not also write a Maintenance record
appears, Inventory can be extracted then, with its tables already in place.
Until that happens, Maintenance's own internal convention keeps the seam
visible: inventory's domain logic and routes are separate files from its
Assets, Work orders, Requests, Downtime, Job plans and PM schedules, so the
extraction is a move of folders rather than a rewrite.
