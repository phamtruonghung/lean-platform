---
status: accepted
---

# An administrator cannot act on their own Account, unconditionally

Date: 2026-09-03

Issue #53 ("An administrator can lock themselves out from the Accounts
Screen") named two routes: `POST /accounts/:id/approval` (`approveAccount`),
which can change an administrator's own `role` away from `admin`, and `PATCH
/accounts/:id` (`setAccountActive`), which can set an administrator's own
`is_active` to `FALSE`. Either one, aimed at a sole administrator's own
Account, ends every administrator's access to the Platform at once, with
nobody left who can reverse it. Investigating the fix surfaced a third route
with the same consequence that the issue did not name: `POST
/accounts/:id/rejection` (`rejectAccount`) also sets `is_active = FALSE`
unconditionally, regardless of the Account's current `approval_status` — a
sole administrator self-rejecting is the same lockout through a third door.

## The decision

An administrator may never approve, reject, or deactivate their **own**
Account through `approveAccount`, `rejectAccount`, or `setAccountActive` —
full stop, regardless of how many other administrators exist at the moment of
the call. The refusal is unconditional, not "only when it would leave zero
live administrators": all three functions compare the target `id` against the
caller's own `actingAccountId` as their first statement, before any other
validation, and refuse with a 403 if they match.

No special case is made for "self-approval as `admin` is harmless" — a caller
re-approving their own Account with `role: 'admin'` is refused exactly the
same as one demoting themselves, because the rule is about identity, not
about which particular write would be harmful this time.

## Why unconditional, not "only when it would leave zero administrators"

The permissive alternative — counting remaining administrators and refusing
only when the count would reach zero — is genuinely race-prone with this
codebase's existing locking, not merely theoretically so. Every write this
guard touches locks only the *target* row (`SELECT ... FOR UPDATE WHERE id =
$1`), the same per-row locking `approveAccount`, `rejectAccount`, and
`setAccountActive` already use for their own preconditions. Two
administrators self-demoting concurrently would each open a transaction,
lock only their own row, count the *other* administrator as still live under
ordinary READ COMMITTED, and both would pass a naive "count > 1" check —
leaving zero administrators despite the check having run and passed on both
sides.

Making the permissive rule correct would require a new, population-wide
advisory lock — the same kind `createAccountForSubject` already takes
(`pg_advisory_xact_lock(hashtext('app_users_bootstrap'))`) to serialize the
first-Account bootstrap, so every concurrent caller contends for the same
lock rather than each seeing an empty table. That device exists nowhere else
in this schema; there is no "last of something" rule anywhere else in the
People Module to build on. A pure identity comparison, made before any
transaction opens, cannot race with anything else — it needs no lock at all,
and is correct regardless of how many administrators happen to exist.

## Consequences

Offboarding yourself as an administrator is not something an administrator
can do alone — a colleague has to do it for them. That is a reasonable
process to require, not a defect: it is the same cost every other
"a colleague must do this, not you" rule already imposes, and it is a small
price against a lockout that nobody left in the Platform could undo.

Guarding three routes instead of the two the issue named is deliberate: any
future write that can set an Account's own `is_active` to `FALSE`, or change
its own `role` away from `admin`, needs the same `refuseSelfAction` check as
its first statement, not just the two routes the originating issue happened
to name. `service.js`'s own comment on `refuseSelfAction` points back here.
