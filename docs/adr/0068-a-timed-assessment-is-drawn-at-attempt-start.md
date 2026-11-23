---
status: accepted
---

# 0068 — A timed Assessment is drawn at Attempt start and frozen onto it

Date: 2026-11-23

Issue #588 asks for "Kiểm tra": a timed Assessment of 10 or 15 Questions drawn
at random from a process's Question bank, assigned to Employees, sat on a
screen and marked. Today a Team Leader types questions into Word, prints, marks
with a red pen and files the sheet; nothing answers "how did Winding score last
quarter" or "which Questions do people keep missing". The bank is long and the
owner will keep editing it, so the first thing to settle is when a paper comes
into being, because everything after it — the score, the deadline, the Marking
— is a claim about one particular paper.

## The decision

**The paper is drawn at Attempt start and frozen onto the Attempt.** When an
Employee starts, the Platform draws the Assessment's Questions at random from
the process's bank and writes one row per drawn Question onto the Attempt,
carrying the Question's text, its three Options, the correct letter and any
explanation as they were at that moment. A later edit to the bank cannot change
a paper already in someone's hands. What a Marker marks, and what a score is
computed against, is the frozen paper and nothing else.

**The Other answer is typed text, never a fourth Option.** A Question always
has three Options and exactly one is correct. "Khác: ghi câu trả lời của bạn"
is a sentence the candidate writes on their own Answer row when none of the
three fits; it is read by a Marker and kept even when no point is awarded.

**A pass writes nothing to `employee_skills`.** A pass is a record that an
Employee answered a paper, not a qualification, and nothing is gated on it.
That is ADR-0018's line, which this ADR applies to a new surface: "A
qualification is information a supervisor reads on the way to a decision,
never a gate the Platform closes on their behalf."

## Why not draw the paper on every read

The alternative is to store only the Assessment and the Employee, and pick the
Questions each time the paper is served. Rejected: two reads of one Attempt
could show two different papers, a score could not be recomputed afterwards,
and the Question an Employee saw at minute three could differ from the one
marked at minute thirty. A frozen paper is what makes a score defensible, and
it is also what makes the deadline checkable, because the server set the
deadline against one fixed set of Questions the moment the Attempt started.

## Why not a fourth "Khác" Option row

The alternative is to store "Khác" as a fourth Option on every Question.
Rejected: an Option is a lettered answer the Platform can score, and "none of
these fits" is the opposite of that. A fourth row would lose the sentence the
candidate wrote, and it would make a non-answer indistinguishable from an
answer, which is how a bad Question survives for years. Keeping the typed text
on the Answer is what lets a Marker see that no Option fitted and why.

## Why not write a pass to `employee_skills`, or gate anything on it

The alternative is to treat a pass as a qualification: record it against the
Employee's skills and let assignment, rosters or Permissions read it.
Rejected, on ADR-0018's reasoning. A paper measures what one Employee knew on
one day, and the Platform cannot say what a particular job requires of them,
so a gate built on it would enforce a requirement it does not know and strand
work when the best-qualified person is off sick. The score is information for
a Team Leader to read, and the list of those below the pass mark is a filter,
not a flag that blocks anyone.

## Consequences

- A Question corrected in the bank no longer matches papers already drawn
  around it. That is the cost and it is intended: the corrected wording applies
  to papers drawn from now on, and a paper in someone's hands, or already
  marked, keeps the words it was sat with. Anyone comparing a Question's
  current text with an old Attempt will see them differ.
- The frozen paper is what a Marker marks, so the Marker's screen reads the
  Attempt's own rows and never joins back to the bank for wording.
- Drawing at Attempt start, not at creation, means the Assessment fixes only the
  paper's size; the number of Questions in the bank must be checked when an
  Attempt starts, not only when the Assessment is created.
- An Employee who retakes is drawn a new paper, and the earlier one stays as it
  was.
- No row is written to `employee_skills` and nothing reads a pass to decide
  anything, so removing or changing an Assessment later touches no
  qualification record.
