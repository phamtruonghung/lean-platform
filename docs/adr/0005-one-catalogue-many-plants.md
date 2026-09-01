---
status: accepted
---

# One catalogue across plants, but document numbers are per plant

Date: 2026-09-01

The Platform runs several plants from one database. Reference data — KPI
definitions, downtime reasons, defect codes, injury types, units of measure — is
**global**: one catalogue, identical at every Site. Document numbers are the
exception: their sequence is scoped by Site, so each plant issues its own run.

## Why a shared catalogue

Running one tier board across several plants is only worth doing if the numbers
mean the same thing at each. A KPI or a downtime reason that drifts per site
makes comparison impossible, which removes the reason to have a group board at
all.

The cost is accepted deliberately: a downtime reason list that serves every
plant's equipment cannot be as specific as one written for a single plant's
presses. Codes stay coarse enough to be shared.

## Why document numbers are not shared

`next_document_number` originally scoped its counter as prefix and year, with no
Site. With several plants that means one global run of work order numbers shared
between them: the numbers interleave, and `WO-2026-000123` does not say which
plant issued it. Site is added to the scope in the baseline, giving
`WO-<site>-<year>-<n>`.

This had to be settled before the first document exists. Numbers get printed,
emailed and quoted on the floor, and re-numbering work orders that have already
been issued is not an option.
