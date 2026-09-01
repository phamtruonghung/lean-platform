---
status: accepted
---

# Deny-all RLS, with two database clients

Date: 2026-09-01

Row Level Security is enabled on every table with **no policies** — a deny-all
floor. Two clients reach the database: the Node API, using the service role, which
owns every write; and Power BI, using a dedicated read-only `powerbi_reader` role
with `SELECT` granted across the schema, connecting through the session pooler.

## Why a floor rather than real policies

Supabase publishes an anon key to the browser and PostgREST is reachable from the
internet. With RLS off, one leaked key exposes all 68 tables. Writing genuine
per-table policies is the other extreme: it would duplicate in SQL the invariants
the API already owns — the PM generation guard, document numbering, "a second
breakdown report joins the open Downtime Event rather than starting another" —
and those are not row-visibility rules.

## Consequences

Views do not set `security_invoker`, so they execute as their owner and read
straight through RLS; granted base tables are read under the reader's own rights.
Because the reader is granted `SELECT` across the schema deliberately, **every
table is now a reporting contract**: a column rename can break a Power BI report
with no signal from this repo. A `reporting` schema of views is the preferred
surface for anything that will be maintained long-term.
