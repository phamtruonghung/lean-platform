---
status: accepted
---

# Supabase Cloud for data, our own LXC for the API

Date: 2026-09-01

Postgres and authentication come from Supabase Cloud. The API is a Node
service running in an LXC container we operate. The `webapp-k8s-promox` k3s
platform — Proxmox VM, Traefik, in-cluster Postgres, nightly backup CronJobs,
the `lp` CLI — is not used by this product.

## Why not keep k3s

It was a working platform, but it made us the operator of a database, a
certificate story and a backup regime for a product that needs none of that to
be bespoke. Supabase supplies all three, and supplies an identity provider that
retires three of `employee-management`'s ADRs (server-side Google OAuth, scrypt
password hashing, and the custom session model) outright.

## Why not Supabase Edge Functions for the API

Edge Functions are Deno, request-scoped and time-limited. This domain wants long
transactions across 68 tables and scheduled work — PM generation was a Kubernetes
CronJob in the old estate for exactly that reason. A plain Node service on our own
hardware fits the shape of the work, and the LXC is already there.

## Consequences

The database is no longer on our hardware, so the network path from the LXC to
Supabase is a hard runtime dependency. Audit triggers read
`current_setting('app.user_id', true)`; against a transaction-mode pooler that
must be `SET LOCAL` inside an explicit transaction, or the audit trail attributes
writes to whichever request used the pooled connection last.
