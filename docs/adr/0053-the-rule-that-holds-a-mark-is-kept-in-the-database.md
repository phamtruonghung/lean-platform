---
status: accepted
---

# The rule that holds a mark is kept in the database

Date: 2026-10-19

ADR-0052 lets an administrator set a Signature for an Employee who holds no
Account, and closes that door with a 409 the moment the Employee can set their
own. Slice #320 implemented the refusal as `signatures.requireNoAccount`, a
`SELECT` against `app_users` in its own statement ahead of the write. Issue #326
found the gap: nothing serialises that statement against the act that links an
Account to the Employee, so an Account linked between the check and the write
leaves an administrator-set mark on an Employee who can now set their own.

## The decision

**The rule lives in the schema.** A `BEFORE INSERT OR UPDATE` trigger on
`employee_signatures` refuses a kept, current row for an Employee who holds an
Account unless the Account that set it is that Employee's own. A row with no
setter is refused the same way, so the shared floor device — which may apply a
Signature and never create one — has a backstop in the database as well as in
its routes. A stroke drawn for one act (`kept = FALSE`) and a row being
superseded are never refused.

**The serialisation primitive is the Employee's row lock, which the Account
link already takes.** `requireLinkableEmployee` runs `SELECT ... FOR UPDATE` on
the `employees` row before either writer of `app_users.employee_id` (Approval
and `setAccountEmployee`) links it. The trigger takes the same lock first, so a
signature write and a link of the same Employee wait for each other: the write
sees the Account, or the link waits until the mark has committed. Nothing in
Approval changed and there is no new kind of lock.

**The application's check stays.** `requireNoAccount` gives the wording in the
ordinary case, and `keepSignature` maps the trigger's generic `23514` refusal to
the same 409 sentence. The trigger is the rule that holds; the check is how it
is usually told to a caller. Neither is a duplicate of the other.

**One case is deliberately unchanged.** A mark written before a link is
legitimate at that instant, and linking an Account later does not touch it. The
Employee's own `PUT /me/signature` supersedes it, as ADR-0052 says.

## Consequences

- An administrator's write that loses the race gets the same 409 as one that
  fails the ordinary check, and never a 500.
- A signature write now takes the Employee row lock for its length. It is held
  briefly and contends only with a link of that same Employee.
- A future writer of `employee_signatures` is held to the rule without having
  to remember it.

## Alternatives considered

- **Re-check inside the write's transaction.** Closes the window only if the
  check also holds a lock the link takes, which is this decision spelled in
  application code, and every future writer must repeat it.
- **Lock in Approval and `setAccountEmployee` against signatures.** Changes
  two writers to protect a third table, and is silent about any new writer.
- **An advisory lock keyed by Employee.** A second lock type beside one both
  link writers already take, with nothing to say they must agree.
