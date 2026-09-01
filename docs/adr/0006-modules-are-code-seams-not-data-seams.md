---
status: accepted
---

# Modules are code seams, not data seams

Date: 2026-09-01

The Platform's Modules — People, Maintenance, Tier Board — are folders in one
backend over one schema. A Module owns its routes and its domain services, and
never imports another Module's internals: it calls that Module's service. No
Module owns a private set of tables, and cross-module reads are ordinary joins.

## Why not give each Module its own data

Because that is the boundary ADR-0001 removed. The schema is one connected
graph — Maintenance reads `employees`, `org_units`, `shift_instances` and
`downtime_events` constantly — so data seams would turn foreign keys into
function calls and give up referential integrity to enforce a separation the
domain does not have.

## Consequences

The rule is a convention, so it needs enforcing: an import-boundary lint rule in
the backend, not code review alone. It is also cheap to reverse, which is the
point — if a Module ever genuinely needs to be extracted, having kept its
services distinct is what makes that possible.
