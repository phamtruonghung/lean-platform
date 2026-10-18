---
status: accepted
---

# A leave request is decided by an edit Grant on the Employee's Org Unit

Date: 2026-10-18

Issue #265 adds the first piece of human-resources work the Platform records
beyond who worked a shift: an Employee asks for time off, and someone who
supervises where they work says yes or no. Attendance (ADR-0040) already
records an absence after the fact with an absence reason; nothing records one
that is asked for in advance. The model is Frappe HRMS's Leave Application and
Leave Type doctypes, which this ADR follows where they fit and departs from
where the Platform's own vocabulary already answers the question.

## The decision

**The leave type is an absence reason, not a new table.** `absence_reasons`
already holds Annual leave, Sickness, Parental leave, Family or carer leave
and the rest, and it is what `attendance_records` names for an absence. A
`leave_types` table would be a second catalogue kept in step with the first by
hand, and an approved request would name a reason that an attendance row later
has to translate. Instead `absence_reasons` gains `is_requestable`
(`DEFAULT FALSE`, so a reason added later is not offered until someone decides
it should be): Late arrival, Unexcused absence, Training and Lay-off are
recorded about an Employee, not requested by one. Unpaid leave is the one
reason a request needs that the baseline lacked, so `UNPAID` is seeded.
Whether leave is paid (Frappe's `is_lwp`) is deliberately not modelled:
CONTEXT.md says paid hours is a payroll question this Platform does not
answer.

**A leave request needs an edit Grant on the Employee's Org Unit to decide.**
Anyone holding an edit Grant reaching the request's Org Unit may approve or
reject it, and nothing more is required. ADR-0039 names a third authority
flag as the point at which Grant authorities should be generalised; this is
not that point. Deciding leave is the supervisor's operational call over
people they already record attendance for — ADR-0040's "an operational fact
about a shift the supervisor already runs, not a judgment call the way Safety
authority or Quality authority gate one" — so it takes the same Grant that
ADR-0040 does, and no `leave_authority` column is added. An administrator
holds it everywhere, as with every other check.

**Nobody decides their own leave.** A request whose Employee is the caller's
own linked Employee (`app_users.employee_id`) is refused with a 403,
administrators included. This is the ADR-0013 rule applied to a second
decision, and Frappe's `validate_for_self_approval`. An administrator who
wants their own leave approved asks another administrator.

**The Org Unit is a snapshot taken at submission.** The request stores the
Employee's Org Unit as the directory resolves it — current Assignment, else
`default_org_unit_id` — at the moment it is submitted, the way Frappe copies
`department` onto the application and the way an Asset's work keeps its Org
Unit. The decision is scoped to where the person worked when they asked, so a
later reassignment does not move a pending request out of the supervisor's
reach or into a new one's. An Employee with neither has no Org Unit
(`org_unit_id` is NULL) and only an administrator can submit for them or
decide it.

**Anyone may submit for themselves; on behalf needs an edit Grant.** The
caller's own linked Employee is always allowed. Recording on behalf of an
Employee — most of a plant cannot sign in — needs `canAct({ write: true })`
at the Employee's Org Unit, the same rule as recording their attendance. The
request remembers the submitting Account (`requested_by_account_id`), who may
cancel it along with the Employee's own Account, while it is pending.

**Reads are restricted, a deliberate exception to ADR-0009.** ADR-0009 makes
the Employee directory readable platform-wide because a plant directory is not
a secret. A leave request is not a directory fact: its note may carry health
detail, the same reasoning ADR-0037 applies to an injured person's diagnosis.
It is visible to the Account that submitted it, the Employee's own Account,
anyone whose edit Grants reach its Org Unit, and an administrator; everyone
else gets a 404, not a 403, so existence is not leaked. The two lists apply
the same rule as filters. This restriction is specific to leave requests and
does not change the directory.

**Overlap is refused by the database.** An EXCLUDE constraint over the
Employee and the inclusive date range, applying only while a request is
`pending` or `approved`, is Frappe's `validate_leave_overlap`. A rejected or
cancelled request frees its days. A constraint rather than a read-then-write
check is the only form that survives two concurrent submissions.

**Days are calendar days.** `days` is `ends_on - starts_on + 1`. The Platform
has no holiday calendar and no working-week definition, so a weekend inside
the range counts.

**The lifecycle is `pending`, then `approved` or `rejected`, or `cancelled`**
by the requester or the Employee while still pending. Each decision is its own
route (ADR-0019). Decision and cancellation are each recorded as a
time-and-Account pair, and every write is audited with `attach_audit`.

## Why not a third authority column

Rejected: a `leave_authority` flag on `app_user_org_units`. ADR-0039 says the
third authority is the trigger to generalise the flags, and adding one here
would force that refactor for a decision that is not a different kind of
judgment from the attendance a supervisor already records. If leave is later
decided by someone who does not supervise the Employee — a central HR
function — that is the moment to revisit it.

## What was deliberately left out

Each of these is a follow-up, not an oversight. Leave **balances and
allocations** (Frappe's Leave Allocation and Leave Ledger Entry): nothing
here stops a request exceeding what an Employee is owed. **Half days** and
partial days. **Holiday calendars** and working-week rules, which would change
how `days` is counted. **Marking attendance on approval**: Frappe writes an
"On Leave" attendance row for each approved day; here an approved request
records the intent and a supervisor still marks the sheet, so the two can
disagree until a follow-up joins them.

## Consequences

`leave_requests` is a new table (migration 1801300000000) with the deny-all
RLS floor, `attach_updated_at`, `attach_actor_columns` and `attach_audit`.
`absence_reasons` gains one column with a default and one seeded row; the
previous image is unaffected (ADR-0007).
