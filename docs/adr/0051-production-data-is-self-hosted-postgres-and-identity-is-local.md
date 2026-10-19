---
status: accepted
---

# Production data is self-hosted PostgreSQL, and identity is local passwords

Date: 2026-10-19

Partly supersedes ADR-0002, which put Postgres and authentication in Supabase
Cloud. That is no longer how production runs, and the docs saying so misled an
operator.

## What production is

The production deployment ("VIProd") runs the API and the frontend on LXC
CT102 from `deploy/compose.yml`. Its PostgreSQL is self-hosted on LXC CT100,
not Supabase. The API reaches it through `DATABASE_URL`, which the Release
workflow takes from the repository secret of that name. The database on CT100
is the identity store; Supabase is out of the picture for this deployment.

Sign-in uses the Platform's own passwords (issue #267; ADR-0022 for the
Employee link, ADR-0045 for the administrator who has none). The repository
variable `AUTH_PASSWORD_MODE` is `local`. The `SUPABASE_*` repository
variables are still set but nothing reads them while the mode is `local`.

## What stays true of ADR-0002

The API is still a Node service in an LXC container we operate, and the k3s
platform is still not used. The Supabase code paths are kept on purpose:
`AUTH_PASSWORD_MODE=supabase` (the default when unset) verifies a Supabase
JWT, and a second deployment, the home LXC 150 box named in issue #267, still
runs that way against Supabase. Both doors are supported; production is the
`local` one on self-hosted Postgres.

## What this reverses from ADR-0002

ADR-0002 chose Supabase so that we would not operate a database, a backup
regime or an identity provider. For production we now operate the database
(CT100) and hold the credentials (`account_credentials`, scrypt hashes,
revocable sessions). Backups, upgrades and recovery of CT100 are ours.

## Not recorded

These facts are not in the repository and are deliberately not guessed here.
Confirm them on CT100 and amend this ADR or the docs that point at it.

- PostgreSQL major version on CT100: not recorded. CI pins `postgres:17-alpine`
  to match Supabase Cloud, not CT100.
- `pg_cron` on CT100: not recorded. The nightly `sqdcp_maintenance()` job is
  only scheduled where the migration found `pg_cron` available. Whether it
  is scheduled on CT100 must be checked, because if it is not, partitions
  stop being created and `mv_daily_oee` goes stale without any error.
- CT100's backup arrangement: not recorded.
- Whether `powerbi_reader` is reachable on CT100, and by what host: not recorded.
- Whether the Supabase-provisioned roles `anon` and `authenticated` exist on
  CT100: not recorded.

## Consequences

Migrations are unchanged and remain immutable history; several migration
comments still say "Supabase Cloud" and describe the world as it was when they
were written. They are not edited.
