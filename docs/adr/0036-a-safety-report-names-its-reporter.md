---
status: accepted
---

# A safety report names its reporter

Date: 2026-09-20

The baseline's own comment above `safety_incidents` argues the opposite of
what this ADR decides, and argues it well:

> `employee_id` on an incident is nullable, and `is_anonymous` exists,
> because near-miss reporting has to be possible without naming anyone. A
> plant that requires a name on a near-miss report stops receiving near-miss
> reports within about a month, and then loses the only warning it had.

That argument was heard in the design session behind #223, and not taken.
This ADR is the answer owed to whoever reads that comment next.

## The decision

Every Safety incident names its reporter. Someone who holds an Account
reports as that Account; someone who does not — most of a plant — reports at
the shared floor device by identifying themselves with their number and PIN
(ADR-0016), and the report carries the identified Employee as its reporter
and no Account. Neither path accepts an unattributed record.

`is_anonymous` and the nullable `employee_id` on `safety_incidents` stay in
the schema, unused. A CHECK constraint forces `is_anonymous` false (#226), so
the decision is enforced rather than merely advisory: reintroducing anonymous
reporting means deleting a named constraint and writing an ADR that answers
this one, not flipping a flag left waiting for the purpose.

## Considered options

- **Anonymous reporting, as the baseline comment argues for.** Rejected: an
  anonymous report cannot be followed up, its reporter cannot be asked what
  happened, and nobody can be told what was done about it. The plant would
  gain a count and lose everything that count exists to support.
- **Anonymous by default, named as an option.** Rejected: reporting
  something that makes you look bad, or makes a colleague look bad, is
  already the uncomfortable case — offering anonymity as a choice means it
  gets chosen whenever reporting feels awkward, which is most of the time,
  and the record ends up anonymous in practice while looking optional on
  paper.
- **Require an Account to report.** Rejected for a different failure of the
  same shape the baseline comment warns about: most of a plant holds no
  Account, so requiring one would mean the operator who nearly lost a hand
  has to find a supervisor before the near miss gets reported at all.
  ADR-0016 exists because this gap is real, not hypothetical.

## Consequences

The baseline comment's own prediction is not disputed: some plants, on some
near misses, will report less than they would have anonymously, because
naming a report is a real cost to the person naming it. That loss is taken
deliberately rather than argued away. What is bought in exchange is a record
that can be followed up rather than merely tallied — an incident that can be
investigated with the person who saw it, and a reporter who can be told, in
the end, that reporting it changed something. A near-miss count with no path
back to the person who saw it answers "how many," and a safety programme
needs to answer "what happened" and "did it get fixed" at least as often.
