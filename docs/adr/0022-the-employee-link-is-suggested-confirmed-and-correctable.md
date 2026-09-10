---
status: accepted
---

# The Employee link is suggested by email, confirmed at Approval, and correctable afterwards

Date: 2026-09-10

Issue #114 named the gap: `app_users.employee_id` — the nullable, UNIQUE link
from an Account to the Employee it belongs to (CONTEXT.md's own Account
entry: "at most one Account per Employee") — is read in two places
(`directory-routes.js`'s `GET /employees/me`, `router.dart`'s routing off it)
and written in none. Issue #115 is the write path this ADR is the decision
record for.

## The decision

Email matching computes a **suggestion**, never a write of its own: when
exactly one Employee's `work_email` matches an Account's `email`,
case-insensitively, `GET /accounts/pending` carries it back as
`suggestedEmployee`. An administrator **confirms** it — or overrides it, or
leaves it unconfirmed — as part of Approval, which is already the deliberate
act where they decide a person's role and Org Units (CONTEXT.md's own
Approval entry: "a person's plant is decided, so it is a deliberate act
rather than a flag"). `POST /accounts/:id/approval` gained an optional
`employeeId` for exactly this, written in the same transaction as `role` and
the Grants. A separate route, `PUT /accounts/:id/employee`, corrects the link
afterwards — for a suggestion missed at Approval time, an Employee record
that arrives after the Account did, or a mistake.

A suggestion is suppressed back to `null`, not surfaced as one an
administrator cannot act on, when the matched Employee has Departed
(`is_active = FALSE`) or is already linked to a different Account. The
ticket's own framing is the reasoning: a suggestion nobody can confirm is
worse than no suggestion at all — it invites an administrator to try, and
fail, for a reason the queue itself could have told them.

## Why not silent auto-linking at first sign-in

The alternative issue #114 considered and rejected: when a newly-created
Account's email matches an Employee's `work_email`, link them automatically,
with no administrator involved at all. Three reasons this does not hold up.

First, it is an unauditable identity claim. `email` on `app_users` comes from
whatever the identity provider's token carried at the moment of sign-in
(`resolveAccountForIdentity`, service.js) — this Platform did not verify that
the human behind that email is the same human `employees.work_email` names,
only that Supabase's own provider issued a token claiming it. Attaching an
Employee's whole history — Assignments, qualifications, the record
`GET /employees/me` exists to show them back — to an Account on the strength
of an unverified claim, with no human ever deciding to make that link, is a
materially different kind of trust than the rest of Approval already
requires: an administrator deciding a person's role and Org Units is
precisely the check this Platform relies on to keep a claim like "I am this
Employee" from being self-asserted.

Second, and more concretely dangerous: a work email is not permanently
attached to one human. A recycled address — the same `role@site.example`
handed to whoever currently holds a position, or a departing Employee's
mailbox reissued to their replacement — would silently attach a new hire to
a departed namesake's Employee record, with nothing in the system to
distinguish that from a correct link. The new hire would inherit assignment
history, qualifications and whatever else the record carries, attributed to
a person they are not. An administrator confirming the suggestion at
Approval is exactly the check that catches this: they are looking at both
records side by side at the moment they decide, not trusting a background
match that ran with nobody watching.

Third, and independent of either risk above: silent auto-linking cannot
serve most of the plant regardless. `employees.work_email` is nullable, and
most of a plant's Employees have none (CONTEXT.md's own Employee entry: "an
Employee need not be able to sign in; most of a plant cannot") — a
technician with no email on file has no possible match for an automatic
process to find. A manual path — the correction route this ADR also
decides — is required no matter what the automatic path does, so automating
only the lucky-email-match case buys a narrower, riskier mechanism without
removing the need for the wider one.

## Why not a link route alone, with no suggestion and no Approval-time write

The other alternative: skip the suggestion and the `employeeId` on Approval
entirely, and let `PUT /accounts/:id/employee` be the only way to set the
link, used whenever an administrator gets around to it. Two problems.

A link nobody is required to make simply stays null. Approval already forces
an administrator to look at every new Account once, deliberately, before it
can act at all — that captive moment is what makes confirming a suggestion
nearly free for the administrator doing it. A correction route with no
suggestion and no prompt at the one moment an administrator is already
looking at this Account relies entirely on an administrator remembering to
visit it again afterwards, for every Account, indefinitely. Nothing about
this Platform's Approval flow gives them a reason to.

And routing every correction through Approval — instead of adding a
dedicated route — is worse than a separate route, not equivalent to one:
`approveAccount` **replaces** an Account's whole Grant set on every call
(service.js's own documented decision, "Approval sets the whole set at once
... never adding to it"), because that is the correct behaviour for the
Grants Approval actually exists to set. Reusing Approval to fix a stale
`employeeId` would force sending the caller's full existing Grant set back
just to change one unrelated field — the same trap `approveAccount`'s own
`expectedApprovalStatus` precondition exists to guard against for a stale
read, made worse here by no relationship at all between "I want to fix the
Employee link" and "I am prepared to re-declare every Grant this Account
holds." A link/unlink route with no side effect on Grants is what a
correction that is not also a re-Approval requires.

## Why an administrator may not link their own Account

`refuseSelfAction` (service.js) guards `PUT /accounts/:id/employee` as its
own first statement, unconditionally, the same shape ADR-0013 already
mandates for `approveAccount`, `rejectAccount` and `setAccountActive`.
ADR-0013's own words explain why this extends here without a new argument
needed: "the rule is about identity, not about which particular write would
be harmful this time." Linking an Account to an Employee is an administrator
asserting "this Account is this human" — on their own Account, that is
exactly the kind of self-asserted identity claim ADR-0013's rule already
exists to refuse, regardless of whether this particular write could lock
anyone out the way the three original ones could. A second administrator can
link the first's Account, unaffected — the same "a colleague has to do it
for them" shape ADR-0013's own Consequences section already accepts as a
reasonable cost, not a defect.

## Consequences

An Account may legitimately stay unlinked in both directions — an
administrator with no Employee record at all, or an Employee whose Account
nobody has confirmed a link for yet — and neither is an error state anywhere
in this Module. `GET /employees/me` answers 404 for the first case
(`directory-routes.js`'s own "This Account has no linked Employee record",
issue #9's original criterion 8) and simply finds nothing to suggest for the
second (`suggestedEmployee: null`). Nothing in this Module treats an
unlinked Account as a state to be corrected on any particular schedule; it is
corrected when an administrator chooses to, through Approval or through the
link route, and not before.

The three refusals `requireLinkableEmployee` (service.js) enforces — no such
Employee, that Employee has Departed, that Employee is already linked to a
different Account — are shared verbatim between `approveAccount`'s
`employeeId` and `setAccountEmployee`, so the two writers of this column can
never drift onto different wording for the same refusal, the same
`OUTSIDE_GRANTED_ORG_UNITS`-style sharing this Module already uses for scope
refusals (errors.js). `app_users.employee_id`'s own UNIQUE constraint is the
belt-and-braces backstop behind the "already linked" pre-check, mapped to the
same clean 409 rather than left to surface as a raw constraint-violation
500 — the same shape directory.js's `mapEmployeeWriteError` already gives
`employees_work_email_key`.
