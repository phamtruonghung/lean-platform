---
status: accepted
---

# Migrations run forward-only as a deploy step; a failed deploy rolls back the image, never the schema

Date: 2026-09-01

`deploy.sh` runs the new backend image's migrations against `DATABASE_URL`
after pulling but before anything running is touched, and a migration failure
fails the deploy with nothing changed. If the new version then fails its
health check, the script restores the previous image — but it never runs
`node-pg-migrate down`. Schema changes only ever move forward.

## Why a deploy step at all

The k3s platform this replaces got this from Helm: a pre-upgrade migration Job
that ran before the new release took traffic, and `--atomic` to undo the whole
release if anything failed. Compose has neither. Without something built to
replace it, a migration either runs inside the application on boot — racing
concurrent replicas and hiding failure behind the app's own health check — or
does not run automatically at all, and a schema change becomes a thing a
person does by hand before every deploy. Both are worse than a script step
that fails loudly and touches nothing when it fails.

## Why forward-only rather than an automatic `down`

The tempting symmetry is: if the image rolls back on a failed health check,
the schema should roll back with it. It is rejected because a schema rollback
is not the same kind of operation as swapping an image tag back. Undoing a
migration can drop a column or table that the *previous* version's own
queries still reference, or discard rows written under the new schema in the
interim — running that automatically, at the exact moment a deploy has just
gone wrong and the system is already in a degraded state, is more likely to
turn a bad deploy into data loss than to fix it. A human deciding to run a
specific `down` migration, having looked at what actually broke, is a
different and much safer act than a script doing it unattended.

Forward-only only works because of what it demands of every migration written
after this one: it must be safe for the version it is replacing to keep
running against it, for the window between the schema changing and the new
containers passing health. In practice that means expand now, contract later —
add and start filling a column in one deploy, drop what nothing reads any more
only in a later one once nothing depends on it. A migration that breaks the
outgoing version defeats the whole design, whether or not the deploy that
shipped it happens to succeed.

## Consequences

The previous image can always serve the migrated schema, which is what makes
image-only rollback safe rather than merely convenient. The cost is discipline
pushed onto every migration author from here on: a migration that is not
backward-compatible with the version it replaces is a bug in the migration,
not something the deploy step can catch or protect against. Recovering from a
bad migration that has already shipped means writing and deploying a further
migration that fixes it forward — there is no `down` path back.
