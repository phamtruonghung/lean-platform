---
status: accepted
---

# The training record is printed from the browser; the Excel form is a layout, not a file format

Date: 2026-10-18

The document HR files for a training is the bilingual form in the repo root
(`training record template.PNG`) — a screenshot of an Excel sheet, with its
column letters across the top, its row numbers down the side, a "Page 1"
watermark across the middle, and the form itself inside a black border: the
training's facts, an attendance table, and three signature lines. What the
plant keeps is the printed sheet, not the workbook. The Platform generates no
files anywhere; its one printable record is the CAPA report, a Screen at its
own address, declared outside the Shell so the sidebar does not print onto it
(ADR-0021, #212). Issue #286 specifies the training record and #292 is the
slice that produces this document.

## The decision

**The document is a Screen at its own address — `/training/:id/form` —
declared as a sibling of the `ShellRoute`, printed from the browser.** It
reads the record's existing read and adds no route of its own: a second
address answering the same question is the first thing to drift. Its labels
are bilingual English-over-Vietnamese, exactly the template's two languages,
hardcoded on that Screen alone — the client has no translation layer and this
feature does not add one, so the application's own Screens stay English.

**The record's number prints, in the header.** It is the one visible addition
to the template, and it is deliberate: every numbered record in this Platform
prints its number, and a filed sheet with no reference on it cannot be found
or matched back to the record that produced it. If the printed sheet must
match a controlled document byte for byte, this is the line to remove, and
the number stays on the Screen.

**Rows are the record's own Trainees, in the order they were added** — never
the template's five blank rows, which are a paper artefact. Each row carries
the Employee's number and name, the Trainee's answer date in the Signature
cell (empty where they have not answered, so a hand signature can still be
collected for the stragglers), and the trainer's evaluation. The trainer's
line prints the trainer's name; the HR line prints blank, because the
Platform has no HR actor to name.

## Why not a server-generated PDF

Rejected. It would mean a second layout to keep in step with the Screens and
the record's fields — the same document drawn twice, drifting at the first
change to either — a new server-side dependency in a backend that carries no
document tooling and no development dependencies at all, and a second answer
to a question the record's own read already answers. It also buys nothing the
browser does not already do: printing a page from the browser is how a person
gets a PDF here, at no cost to the Platform.

## Why not a `.xlsx` or `.docx` download

Rejected on the same grounds, with one more. The Excel chrome in the template
is the tool the form was drawn in, not the document: the plant files the
printed sheet, and nothing downstream opens the workbook. A downloaded file
also forks the record — a copy on somebody's desktop with no link back to the
record it came from, correct on the day it was saved and silently stale
afterwards — where a Screen printed at the moment it is needed is never
stale and carries the record's number.

## Consequences

HR still countersigns the printed sheet: there is no HR sign-off step in the
Platform (issue #286's Out of Scope), so the paper does not fully disappear
until that decision is made on its own. Printing is the browser's own job and
nothing in the app depends on it — the Screen renders whether or not anything
is printed, which is also what makes it testable in the widget suite (both
languages' labels present, and no Shell chrome, asserted by the sidebar key
finding nothing).

A later "download this as a PDF" requirement is additive rather than a
reversal: the browser already offers it, and a generated file would be a new
ticket arguing against this one rather than a change to it.
