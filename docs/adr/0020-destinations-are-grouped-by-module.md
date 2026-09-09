---
status: accepted
---

# Destinations are grouped by Module, reversing #39

Date: 2026-09-10

Issue #39 built the Shell and shipped with this acceptance criterion ticked:

> - [x] No destination names a Module; destinations name what a person does

Its body was emphatic about it:

> Two decisions are load-bearing and should not be quietly reversed while
> building this. **Module is not a navigation concept**: destinations are the
> things people do — the Directory, Accounts, Sites — never "People", because
> nobody navigates to a Module.

`CONTEXT.md` encoded the same rule twice: the **Destination** entry read
"named for what a person does … never for the Module behind it", and listed
**Module** under its `_Avoid_` list.

The Shell now renders four group headings — **People**, **Maintenance**,
**Insights** and **Administration** — three of which are Module names.

This ADR exists because #39 asked that the decision not be reversed
*quietly*. Reversing it loudly is the sanctioned path, and this is what
loudly looks like: the reversal, the reason, and what was given up, recorded
where the next reader of that closed criterion will find it.

## The decision

Destinations are grouped, and the grouping is by Module.

| Group | Destinations |
| --- | --- |
| _(ungrouped)_ | Home |
| People | Directory, Job roles, Skills, Org Units |
| Maintenance | Assets, Work orders |
| Insights | Skill coverage |
| Administration | Approvals, Accounts |

Two details are not simply "by Module". Home stays ungrouped above the
headings, because it is the landing surface rather than a member of anything.
Approvals and Accounts sit under **Administration** rather than under People:
they administer the Platform itself — who may sign in, and what they may
reach — rather than the plant's workforce, and filing them next to the
Directory would suggest a relationship that does not exist.

## Why

#39's rule was right for ten Destinations and stops being right at sixteen.

At the time #39 shipped, the sidebar carried a handful of entries and a flat
list was the honest presentation: there was nothing to group, and inventing
headings would have been ceremony. Issues #72–#80 add Requests, Breakdowns,
Downtime, PM schedules, Job plans, Parts, the tier board and the floor-facing
surface. A flat column of sixteen is not scanned; it is read from the top
every time.

The argument for grouping is not in dispute. The argument was over what to
group *by*, and there were two candidates.

**By what a person does** — the rule #39 set. Something like "running the
plant" versus "maintaining its catalogues". This keeps the glossary intact
and stays faithful to the original reasoning.

**By Module** — the one taken. It loses the "nobody navigates to a Module"
principle, and the headings do name parts of the software rather than parts
of the job.

Module won on predictability. A person looking for Assets can reason "that is
maintenance" and be right; a person looking for Assets under a doing-based
scheme has to first work out which of two abstract activity groupings the
Platform's authors filed it under. The Module boundary is already visible to
anyone who uses the plant — maintenance is a department, not only a code
seam — so the heading names something real to them, even though it also
happens to name a folder in `frontend/lib/`.

What #39 was actually protecting against is still protected. Its concern was
that somebody would navigate *to* a Module — a "People" Destination that
opens a Module landing page, with the real Screens one click further down. No
such Destination exists. The headings are not selectable, carry no address,
and open nothing. Every Destination is still named for what a person does
there, and every one of them is still one click away.

## What this costs

The rule is genuinely weaker than it was. "No Module names in the navigation"
is a bright line that a reviewer can check without judgement; "no Module
names except as non-interactive grouping headings" is a line that needs one.
A later change that gives a heading an address, or collapses a group behind a
click that lands somewhere, would cross back over #39's original objection
while appearing to respect this ADR. That is the failure mode to watch for.

Grouping is also lopsided today: People carries four Destinations, Insights
carries one, and Administration two. #72–#80 bring Maintenance to roughly
eight and #76 fills Insights, so this evens out — but until then the headings
carry less weight than they will.

A group whose Destinations are all filtered away by the Account's role
renders no heading at all, so an operator never sees an empty
**Administration** label. The Shell continues to gate nothing itself: it
offers what it is handed, and role filtering stays exactly where #39 put it.

## Consequences

`CONTEXT.md`'s **Destination** entry is rewritten to match, and **Module**
leaves its `_Avoid_` list — a glossary that contradicts the code is worse
than no glossary. Issue #39 carries a comment linking here, so a reader who
finds that ticked criterion can follow it to the reversal rather than
concluding the code drifted.

The 700px rail breakpoint and the 260px/64px widths are unchanged. Group
headings do not render into the 64px rail, where there is no room for text; a
hairline rule marks each boundary there instead, so the grouping survives as
rhythm rather than as a truncated label.
