---
status: accepted
---

# An administrator may sign in without an Employee; every other role may not

Date: 2026-10-19

Extends ADR-0022, which left an Account unlinked "in both directions" as a
legitimate state (an administrator with no Employee record at all) but did
not say whether that Account could sign in with a local password. Issue #268
made the answer no, for everyone: `sign-in.js` refused any Account without an
active Employee. Issue #284 measured the consequence: the deployment's only
administrator had no Employee, so with `AUTH_PASSWORD_MODE=local` nobody could
administer the site, and a password (#280) did not help.

## The decision

An Account whose `role = 'admin'` may sign in through `POST /api/auth/login`
without an Employee link. The rule lives in one named function,
`mayHoldLocalSession` in `sign-in.js`, not a bare `|| role === 'admin'`:

- Linked to an Employee: the Employee must be active, for every role. An
  administrator linked to a Departed Employee is still refused.
- Not linked: only role `admin` is allowed. Every other role is refused with
  the same 401 as any other failure.
- For everyone, unchanged: an enabled credential and a matching password.
  `is_enabled = FALSE` or a wrong password is the same 401 for an admin.

Rejected: the preferred option in #284, inventing or collecting an Employee
record for the administrator. It remains available to a deployment whose
administrator is a plant person; nothing here prevents linking later.

## What a local administrator's external_subject is

`authenticate` resolves a session through `app_users.external_subject`, and
`findSessionIdentity` ignores an Account without one, so the subject must be
set. It is assigned on first sign-in with `COALESCE(external_subject, ...)`,
so an existing subject is never rewritten.

- With an Employee: `local:<employee_no>`, unchanged.
- Without: `local-account:<app_users.id>`.

Why the id: it is the primary key, so it is unique and never changes. Why not
the email: it is mutable and could be reused, which would make the subject
point at another person. Why a different prefix rather than `local:<id>`:
`employee_no` is free text, so `local:12` could collide with an Employee whose
number is `12`; `local-account:` can never equal any `local:` value. Because
`COALESCE` keeps the first subject, linking the administrator to an Employee
later does not change its identity or invalidate its sessions.

## Consequences

An unlinked administrator has `employeeId: null` in the session payload and
`GET /api/people/me`. Backend paths already treat that as normal: `GET
/employees/me` answers 404 (ADR-0022), leave requests and CAPA team checks
guard null, and `canAct` returns true for `admin` before reading anything
else. The frontend router guards null `employeeId` too. Left untouched: the
"my own record" Screen shows its not-found state for such an administrator.

The Supabase door is unchanged. `dev/set-a-password.mjs` no longer warns about
a missing Employee for an administrator. No schema change.
