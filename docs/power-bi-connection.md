# Power BI connection

`migrations/1756000000002_deny-all-rls.js` creates `powerbi_reader`: a
dedicated, read-only Postgres role that can `SELECT` from every table and
view in `public` and nothing else — no INSERT, no UPDATE, no DELETE, no
membership in any role that has one. See
[ADR-0004](./adr/0004-deny-all-rls-with-two-database-clients.md) for why this
role exists at all rather than a per-table policy for Power BI.

## Connection string

Use the Supabase **session pooler**, not the direct connection and not the
transaction pooler. This repository already makes this choice once, for the
API's own `DATABASE_URL` — see `scripts/setup-deployment.sh`, around the
string `SESSION POOLER`, for the reasoning this doc borrows: the direct
connection resolves over IPv6 only unless the IPv4 add-on is purchased, and a
Power BI installation (typically on-prem, behind whatever network the analyst
runs it from) is no more likely to have IPv4-only reachability solved for it
than the LXC this Platform's API runs on. The session pooler is the one entry
point that doesn't make that a precondition.

The transaction pooler is the wrong alternative for a different reason: it
does not hold a session open for the lifetime of a connection, and things
Power BI's connector may reasonably do — a multi-statement session, `SET
ROLE` semantics, whatever a given version of the connector actually issues —
are exactly the class of thing a transaction-scoped pooler is not built to
guarantee across. The session pooler behaves like a direct Postgres
connection from the client's point of view, which is the safer default for a
third-party connector this repository does not control the SQL for.

Find the session pooler connection string in Supabase: **Project Settings →
Database → Connection string → Session pooler**.

## Username

Supavisor takes the project reference as part of the username, after a dot:
the role name, then `.`, then the project reference. So `powerbi_reader`
connects as `powerbi_reader.<project-ref>`, where `<project-ref>` is the same
reference that appears in the project's URL and in the direct-connection
hostname.

This is the documented behaviour rather than an inference — Supabase's own
pooler documentation states that the project reference is included in the
username following a `.`, giving `postgres.<project-ref>` for the default
role. The rule is about the username, not about which role it names.

The host follows the session-pooler form `aws-<region>.pooler.supabase.com`
on port `5432`. Region and exact string come from the dashboard: **Project
Settings → Database → Connection string → Session pooler**. If that string
ever disagrees with this document, the dashboard is authoritative.

## Password

No password for `powerbi_reader` exists anywhere in this repository, and none
ever will — see the comment on `ALTER ROLE powerbi_reader WITH PASSWORD '...'`
in `migrations/1756000000002_deny-all-rls.js` for why: a password committed to
a migration is a password permanently readable in git history, including
after it is rotated. An operator sets one by hand, directly against the
production database, once the migration has created the role, and gives it to
whoever configures Power BI out of band from this repository entirely.

## What Power BI can and cannot do

`powerbi_reader` reads every table and view in `public` — deliberately, per
ADR-0004's "every table is a reporting contract" — and writes nothing,
anywhere. Row Level Security is enabled with no policies on every table in
this schema; `powerbi_reader` reads through that by holding `BYPASSRLS`
rather than by any policy granting it rows, because a role with no policy and
no BYPASSRLS reads *nothing* from a table under deny-all RLS, not merely a
restricted view of it. What actually bounds this role is the `SELECT`-only
grant, not RLS.

That breadth has a real cost, called out directly in ADR-0004's Consequences:
none of the views in this schema set `security_invoker`, so a view executes
with its *owner's* privileges and reads straight through RLS regardless of
who queries it — and because every base table is granted to
`powerbi_reader`, a column rename or a table drop in a future migration can
silently break a Power BI report with no signal anywhere in this repository's
own tests or CI. A `reporting` schema of views, stable by design rather than
by accident, is the preferred long-term surface for anything meant to be
maintained rather than queried ad hoc against the raw schema.
