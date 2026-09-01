---
status: accepted
---

# Inherit the schema, squash the history, keep node-pg-migrate

Date: 2026-09-01

The 68-table SQDCP schema is carried over from `maintenance-management`; none of
the application code is. The 33 inherited migration files are squashed into a
single clean baseline for this repo, and `node-pg-migrate` remains the migration
tool rather than the Supabase CLI's SQL migrations.

## Why squash

No production data exists anywhere in the estate, so this is free exactly once,
and now is that once. The inherited files encode a world that has ended: a
shared/vendored split with no upstream on `main`, a bridge migration to an app
that no longer exists, and a drift-checking procedure documenting a relationship
that is over. Carrying them preserves constraints that no longer apply.

## Why not the Supabase CLI

Its migrations are SQL files driven by `db push` and `db diff`, and adopting them
buys branching and diffing we do not need yet. The schema is already expressed in
`node-pg-migrate` JavaScript and the API that runs it is ours. The Supabase CLI is
still used for local development.

## What the baseline drops

The `attachments` table does not survive the squash. The product records text
only for now, its `storage_key` column was waiting on an object-storage decision
that was never made, and its owner constraint could not hold a Work Order
anyway. Adding file attachments later is an ordinary migration; carrying a table
nothing writes to is the inherited cruft this decision exists to shed.
