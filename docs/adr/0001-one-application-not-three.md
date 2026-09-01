---
status: accepted
---

# One application, not three

Date: 2026-09-01

The plant's software existed as two deployed apps — `employee-management` and
`maintenance-management` — over a shared schema each vendored into its own
database. This product replaces both with a single application over a single
database. Employees and Maintenance become **Modules**: functional areas of one
codebase, not separately deployed services.

## Why

The separation was never a domain boundary. It produced a bridge migration whose
only purpose was to reattach the two halves of one person
(`employees.directory_user_id`), a one-way replication of master data with an
accepted drift problem, and a rule that vendored migrations stay byte-identical
to an upstream that was never merged. Every one of those costs was paid to keep
apart two things that describe the same plant.

## Consequences

The `employees` table is the rich SQDCP one — job roles, assignments, skills,
attendance — and the four-column directory table is dropped. `work_email` becomes
an ordinary column on it. The bridge migration is not carried across; there is no
directory left to link to.
