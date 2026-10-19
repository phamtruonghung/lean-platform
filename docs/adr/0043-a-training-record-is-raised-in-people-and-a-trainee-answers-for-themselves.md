---
status: accepted
---

# A training record is raised in People, and a Trainee answers for themselves

Date: 2026-10-18

The plant trains people constantly and records almost none of it in the
Platform. A training is delivered on the floor, and the evidence is a
bilingual form — `training record template.PNG` at this repo's root — filled
in by hand afterwards, signed by everyone who attended, signed by the
trainer, countersigned by HR and filed on paper. Nothing here records a
training: the baseline carries no training table at all, and its only trace
of a training is the `training` value of
`attendance_records.attendance_status`, which says a person was *away from
their line*, not what they were trained on. Issue #286 specifies the feature
and #287–#293 are its slices; this ADR records the two decisions those
slices turn on and would otherwise be re-litigated.

## The decision

**A training record lives in the People Module, and it is one occasion of
training delivered** — its title, the day it was given, how long it lasted,
its trainer, its objective, and the Employees who attended, listed one by
one. This is ADR-0040's decision for attendance applied to the nearest case
it did not cover: a capability about Employees that other Modules may read
from is People's, and two tables with their Screens do not earn a Module of
their own (ADR-0028's counter-precedent, where inventory stayed inside
Maintenance for the same reason).

**Anyone holding an edit Grant reaching the record's Org Unit may raise,
send and correct it; an administrator may anywhere.** No new authority is
added to a Grant. Recording a training is an operational fact about a place
— the same answer #223 gave for recording a Safety incident and #249 for
recording an Attendance sheet — not the judgment call Quality authority
(ADR-0035) or Safety authority (ADR-0039) gate. ADR-0039 already names the
arrival of a *third* authority as the trigger to revisit how authorities are
modelled; a training record is not that trigger, and adding one sideways
would pre-empt the question.

**A Trainee answers for themselves — `confirmed`, or `declined` because the
record is wrong — and nobody answers on their behalf.** Not a supervisor,
not HR, not an administrator with an edit Grant. The form's Signature column
is what this is: a signature given by somebody else is not a signature, and
a Platform that accepted one would be recording a person's word that the
person never gave. A Trainee may change their own answer, audited; an
administrator may give anybody the edit Grant that lets them *fix the
record*, and still cannot answer for them.

**A Trainee who holds no Account answers at the shared floor device.**
`CONTEXT.md`'s Employee entry is explicit that most of a plant cannot sign
in, and the Platform's existing door for that population is the device where
an Employee identifies by number and PIN (ADR-0016, #201) — the same door
Safety reports are made through. The device writes the same columns the
Account door writes, filling the identified Employee rather than an Account,
so the two doors are one fact with two ways of saying who is standing there.

**A confirmation asserts that the person was there, never that they can do
the thing.** No answer writes `employee_skills`, and the trainer's
`evaluation` field (`paper` / `job_training`) records *how* each Trainee was
evaluated — the form's own assessment-shaped data — rather than a pass or a
fail.

`Paper` / `Job-training` is recorded as a reading of the template's own
Evaluation header: **the method the Trainee was evaluated by, as the trainer
records it.** It is the trainer's own field and not a correction, so it is
settable after the record is sent, when the trainer often fills it in. If a
plant means something else by that header, such as the Trainee's own answer or
both methods applying, the change is one column and one enum, not the model.

**A record is a draft until somebody sends it, and a draft is visible to
whoever could send it.** Sending asks every Trainee at once, and requires
the record's own facts and at least one Trainee. The form is filled in
*after* the training is delivered, so publishing on creation would put
requests on the floor while the list was still being typed and would leave a
mistyped Trainee un-askable. A draft is hidden from ordinary readers for the
reason the register's read is open to them at all (ADR-0009): a register
everybody may read must not contain a record nobody has committed to — and
the predicate that hides it is the one that already decides who may send it,
rather than a second, "who authored this" rule.

## Why not a supervisor confirming on the trainee's behalf

Rejected. It is the one alternative that would make the feature easier —
the supervisor already holds an edit Grant, is already standing there, and
already knows who turned up — and it is exactly what the paper form does not
do. The plant's own habit is a signature per person, collected by passing
the sheet down the line; a record where somebody else's word stands in for
mine would be a quieter version of the same problem the paper has, with the
Platform's authority behind it. It also destroys the only thing an answer is
good for: when a training is later questioned, "I confirmed it myself" is
the evidence, and "somebody confirmed it for me" is not.

## Why nothing writes `employee_skills`

Rejected as a consequence of a confirmation, and deliberately left as a
separate decision somebody may make later. Three reasons, in order of
weight. First, `employee_skills` writes are administrator-only by decision
(ADR-0010's own recorded consequence), and a Trainee answering their own
record would be the only non-administrator write path to the skills matrix
in the Platform — a data seam opened for convenience. Second, a proficiency
level is not something a tap establishes, and the row's expiry derives from
an assessment date that no tap produced: a skill minted this way would carry
a revalidation date computed as though somebody had assessed it. Third,
ADR-0018 refuses to let a qualification gate anything today, which is only
coherent while qualifications mean something — the moment `employee_skills`
is filled by attendance taps, the matrix stops being a record of assessment
and starts being a record of presence.

If a plant wants a training to grant a skill, the honest shape is the
trainer's assessment writing the skill, with the training named as its
source — a decision with its own ticket, and one this ADR does not make.

## Consequences

`employee_skills` and its Screens are untouched, and the skills matrix keeps
meaning "assessed, as of a date". The attendance sheet's `training` absence
reason is untouched too: a person at a training is still recorded as away
from their line for the day, and the training record is what says what they
were away for. An Attendance sheet and a Training record are therefore two
records of one morning that do not reference each other — deliberate, and
the first place a later ticket should look if the plant asks for the link.

A sent record is never deleted; a draft may be discarded. Corrections after
sending go through the same Grant and are audited, which is ADR-0040's rule
for a confirmed Attendance sheet and the Platform's one mechanism for a past
fact that was recorded wrong. A Trainee who answered and is then taken off
the record takes their answer with them, audited — HR listing the wrong
person is the case that has to stay fixable.

The record's numbers, addresses and the printed document it produces are
issue #286's; the document's own decision — that it is printed from the
browser rather than exported as a file — is ADR-0044.
