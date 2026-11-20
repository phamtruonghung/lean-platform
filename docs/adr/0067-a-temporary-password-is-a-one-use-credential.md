# 0067. A temporary password is a one-use credential, and nothing seeds a shared one

## Status

Accepted (audit F1, `/root/.hermes/reports/security-audit/lean-platform/run-1/`).

## Context

Two facts combined into one defect. `dev/seed-relats-vietnam.mjs` wrote every
plant account with the same eight-digit password, as a literal in the
repository; and the API reported `account_credentials.must_change_password`
without ever enforcing it (`passwords.js` said so in its own header, and
`sign-in.js` minted a session without consulting the column). The client was
the only thing that honoured the flag, and a client is not an access control.

The consequence was stated by the loader itself: anyone who knew an employee
number could sign in as that person, and every Module supported by an Account —
the directory, the Quality screens, the KPI board — answered as that person.
Approval did not help: the loader writes `is_active = true` and
`approval_status = 'approved'`, so a seeded Account never waits in the queue.

A fix that only changed the loader would leave every already-seeded account
(and every administrator reset, which writes the same flag) as useful as a real
password. A fix that only enforced the flag would lock people out of an app
whose passwords all arrive by administrator reset or by the loader, with no way
to change one. Both halves are the decision.

## Decision

**The flag is enforced where the session is used, not where it is minted.**
`requireActive` (`backend/src/modules/people/middleware.js`) answers
`403 { status: 'password_change_required', code: 'MUST_CHANGE_PASSWORD' }` for
every authenticated route while `must_change_password` is TRUE, except two
doors:

- `GET /api/people/me` — it carries no `requireActive`, because an Account
  must always be able to learn who it is; it answers `account.mustChangePassword`
  so the shell can route to the change Screen.
- `PUT /api/people/me/password` — otherwise the Account could never leave the
  state. It opts out by naming `allowWhilePasswordChangeRequired` in front of
  `requireActive`, rather than the gate matching on a path string a rename would
  silently break.

The code is the client's contract: a bare 403 cannot be told apart from a
permission refusal, and every other refusal in this codebase already carries a
stable `code` (`PERMISSION_REQUIRED`, `APPROVAL_STATUS_CHANGED`). The approval
branch is checked first, so an inactive Account hears why it is inactive rather
than being told to change a password it may not use.

The check is one branch in the shared gate, not a guard per route: a route
added tomorrow cannot forget it. The cost is one primary-key read on
`account_credentials` per authenticated request, and the flag is read fresh
rather than cached on the session, so an administrator's reset takes effect on
the caller's very next request.

**The loader mints a password per person.** `temporaryPassword()` draws 16
characters from the OS CSPRNG over an alphabet without `0/O`/`1/l/I`, the
credential is written with `must_change_password = TRUE`, and the run prints
the email/password pairs once in its own report. Nothing writes them to a file
or to the repository, and because a credential row is insert-only, a second run
mints and prints nothing.

## Consequences

- A seeded or reset password can do exactly one thing: choose the real one. The
  loader's own printed risk line — "anyone who knows an employee number can sign
  in as that person" — is gone, and it is gone for accounts seeded before this
  change too, without touching their rows.
- **Distribution is now per person.** The loader's output is the only copy of a
  seeded password; an administrator hands each person their own line. There is
  no shared value to circulate, which is the point, and no recovery path other
  than a reset, which was already true.
- A client that ignores `account.mustChangePassword` can read `/me` and nothing
  else until it changes the password. The Flutter client already routes on it
  (`frontend/lib/platform/router.dart`, `accountRedirect`), and
  `SignOutOnUnauthorized` treats 403 as a role refusal rather than a dead
  session, so the refusal mid-session is shown, never a sign-out.
- The refusal names a state the Account can leave in one request. An Account
  that cannot reach the change Screen (no current password known to it) is a
  lockout in the ordinary sense: an administrator resets it, and the reset
  writes the same flag.
- Out of scope, and still open from the same audit: the sign-in throttle, the
  deploy runner, HSTS/CSP, and the employee CSV.
