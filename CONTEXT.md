# Platform

One application for running a manufacturing plant: it records the work that
happens on the floor and reports the numbers that work produces.

## Language

### The product

**Platform**:
This product. One application, one database, covering the plant. Named for lean
manufacturing, not for any hosting arrangement — the k3s repo that once carried
the name is unrelated to it.
_Avoid_: The k3s platform, webapp-k8s-promox, infrastructure, system

**Module**:
A functional area of the Platform that records real work — Maintenance,
Employees, Quality — and produces the measurements KPIs are calculated from. A Module is
a slice of one application, never a separately deployed app.
_Avoid_: App, service, pillar, subsystem

### The plant

**Site**:
One plant. Sites are plural and independent: each keeps its own shift pattern
and its own local time, so a production day means something different at each.
Every part of the plant hierarchy belongs to exactly one Site.
_Avoid_: Factory, location, facility, plant (use Site in prose about the model)

**Production day**:
The span the plant counts a day's work against, beginning when a Site's
first shift begins rather than at midnight. It differs between Sites for the
same reason the Site entry above already does: each keeps its own shift
pattern and its own local time. Every event this Platform records is filed
against the production day its own shift fell within, never the calendar
date a clock happened to show at the time.
_Avoid_: Calendar day, date, 24-hour period

**Org Unit**:
A node in a Site's hierarchy — area, department, line, cell or work centre.
Org Units form a tree, so "everything under Line 3" is a single question. What a
KPI is measured against, what a person is granted access to, and where an Asset
sits are all Org Units.
_Avoid_: Department (that is one kind of Org Unit), team, group, node

**Entry point**:
The topmost Org Unit an Account is granted in a Site — where its own scope
begins when browsing the tree down from the top, since a grant reaches
downward only and a deep grant's own ancestors are not themselves granted. An
Account may hold several entry points in one Site; one granted a Site's root
has exactly one, the root itself.
_Avoid_: Root Org Unit (a property of the tree, not of a particular Account's
grants)

**Import**:
Submitting a whole branch (or several) of a Site's Org Unit hierarchy in one
call, rows keyed by their own `code` rather than a database id since most of
them do not exist yet — the file a spreadsheeter prepares offline, not a row
typed one at a time through the ordinary create. Validated whole before
anything is applied, and applied in one transaction: a single invalid or
out-of-scope row means none of the import happened, never a partial
hierarchy left behind.
_Avoid_: Upload (nothing here is a stored file — the request is JSON, kept
only long enough to validate and apply), bulk create, migration (a schema
change, an unrelated word this codebase already uses for that)

### The people

**Employee**:
A person the plant employs, recorded once and referenced everywhere — the
technician a job is assigned to, the operator a shift is booked for, the holder
of a qualification. An Employee need not be able to sign in; most of a plant
cannot.
_Avoid_: Staff member, worker, person, resource, user

**Departed**:
An Employee who no longer works at the plant. Departed is a flag
(`is_active = false`, with the date recorded), never a deletion: the record
stays, since an Employee's history is what answers "who worked here last
March" — a question this Platform must still be able to answer after they
leave.
_Avoid_: Terminated, ex-employee, removed, deleted

**Directory**:
The searchable listing of Employees, and the detail view behind one of
them — job role, Org Unit assignments and skills. Readable by any approved
Account regardless of their own Org Unit grants: a plant directory is not a
secret, and Org Unit scope decides where an Account may act, not who it may
know about.
_Avoid_: Employee list, staff directory, org chart

**Accounts Screen**:
The listing of every Account on the plant — pending ones included — what each
holds, and whether it can sign in. Where the Directory answers "who works
here", the Accounts Screen answers "who can sign in and what may they reach":
the two lists can disagree, since most of a plant cannot sign in at all and an
administrator need not be an Employee. Reached only by an administrator.
_Avoid_: Directory (that lists Employees, not Accounts), user list, admin panel

**Account**:
What lets somebody sign in and act. An Account carries the role that says what
kind of work they may do, and the Org Units it may be done in — a supervisor on
one line is not a supervisor of the Site. At most one Account per Employee, and
an administrator need not be an Employee at all.
_Avoid_: User, login, profile, identity (an identity is what the sign-in
provider holds; the Account is what this Platform grants)

**Approval**:
An administrator admitting a person to the Platform and deciding which Org Units
they may work in. Signing in successfully is not admission: until Approval the
Account exists and can do nothing. With several Sites, Approval is where a
person's plant is decided, so it is a deliberate act rather than a flag.
Admitting a person is also where an administrator decides which Employee they
are, when the two are the same person.
_Avoid_: Activation, verification, registration, onboarding

**Grant**:
The record that an Account may work in one Org Unit, at one of two levels: view,
or view and edit. A Grant reaches downward, so one on a department covers every
line beneath it, and an Account holds exactly the Grants its last Approval gave
it — Approval sets the whole set at once, replacing what was there before, never
adding to it. This is the record Account, Approval and Entry point each already
gesture at. A Grant may also carry Quality authority or Safety authority — each
separate from its level and from the other — and both are set and replaced
along with the rest of the set.
_Avoid_: Permission, scope (scope is the reach a Grant produces, not the record),
access

**Job role**:
What an Employee does — fitter, welder, line leader. Defined once and shared
by every Site (ADR-0005's shared catalogue), never scoped to one, so the same
role means the same thing wherever it is held.
_Avoid_: Position, title, job code, grade

**Assignment**:
The record of an Employee working at one Org Unit, as one job role, from one
date. A transfer never edits an Assignment in place: the open one is closed
with an end date and a new one is opened, so both remain and an Employee's
history stays answerable.
_Avoid_: Placement, posting, allocation, transfer (a transfer is the act; an
Assignment is what it produces)

### Attendance

**Attendance sheet**:
One record per shift instance, confirming who worked it and for how long.
Pre-filled from the crew roster — the Org Unit roster when the shift has no
crew — so a normal shift takes one tap to confirm; the supervisor's own work
is marking the exceptions. Confirmation (`confirmed_at`,
`confirmed_by_account_id`) is its own fact and is never inferred from the
rows a sheet holds, because "everyone on the roster was absent" and "nobody
has filled this in" must stay different states.
_Avoid_: Timesheet, clock-in (both name a device or a payroll record; this is
neither), roster (that is what a sheet starts from, not what it is)

**Worked hours**:
The minutes an Employee is confirmed to have actually worked a shift. A
sheet's pre-filled default is the shift's duration minus its breaks; the
supervisor corrects it for a late arrival, an early finish or overtime.
Every Employee's worked hours count toward it, whatever their
`employment_type` — the plant supervises their work day to day whether they
are permanent, temporary, agency, contractor or apprentice.
_Avoid_: Scheduled hours (the shift's own duration, before any correction),
clock time, paid hours (a payroll question this Platform does not answer)

**Exposure hours**:
Worked hours, summed over a window and an Org Unit subtree, read as the
denominator `SAF_TRIR` and `SAF_LTIFR` divide by rather than as a cost.
Because it is a sum of Worked hours across every confirmed shift in the
window, a past shift within that window with no confirmed Attendance sheet
leaves the sum incomplete, which is why an unconfirmed shift makes the rate
`no_data` rather than silently understating it.
_Avoid_: Man-hours, FTE hours

### The work

**Asset**:
The machine, cell, tool or utility that work is done on. An Asset sits at
exactly one Org Unit, and that placement is what decides who may work on it —
scope follows the Asset, never the job. That placement can be corrected, and the
work already recorded against the Asset keeps the Org Unit it was raised at.
Assets nest, so a gearbox belongs to the press it is fitted to, and
"everything on this line" reaches the components beneath it.
_Avoid_: Equipment, machine (one kind of Asset), item, resource, tag

**Request**:
What anyone on the floor asks maintenance for, before there is a work order —
a machine acting up, something that needs looking at, raised by whoever
noticed it. Maintenance may accept it or decline it; accepting produces a work
order that still points back to the request that asked for it, so the person
who raised it can follow it through to the job. A request commits maintenance
to nothing: until it is accepted, it is an ask and no more.
_Avoid_: Ticket, complaint, maintenance request, work order (a request is not
yet one)

**Work order**:
The job maintenance commits to doing on an Asset: raised, assigned to somebody,
worked, and completed. A work order is not a request — a request is what anyone
on the floor asks for and maintenance may decline; the work order is the
commitment that follows one, or that maintenance raises for itself. What it
records on completion, above all when the work started and ended, is how long
the repair itself took — one half of the reliability numbers, the other being
how long the machine was down.
_Avoid_: Ticket, job card, task (a task is one step inside a work order),
maintenance request (that is what precedes it)

**Breakdown**:
A machine stopping unplanned. It bypasses the request-and-decline path
entirely, because the machine is already stopped rather than something
somebody is asking maintenance to look at — it produces both a record of the
stoppage and the work order that fixes it, together, rather than the one
waiting on the other.
_Avoid_: Failure, fault, incident, unplanned stop (use Breakdown)

**Downtime**:
The period a machine was not running — what availability is measured from,
and the span between one stoppage and the next. It is not the same length as
the work order's own duration, which is how long the repair took: a
job can take longer than the stoppage, if nobody gets to it right away, or the
stoppage can outlast the job, if the machine is back running before the work
order raised against it is finished.
_Avoid_: Stopped time, outage, breakdown (a breakdown is one cause of
downtime, not the period itself)

**Job plan**:
The reusable description of how a recurring job is done — the steps it takes
and what it requires — kept once and used every time that job comes around
again. It is distinct from the work order that carries it out: the job plan is
the instructions, the work order is one particular occasion of following
them.
_Avoid_: SOP, checklist, work instruction, template

**PM schedule**:
What raises a work order before something breaks, rather than in response to
one. Elapsed time and accumulated use are two different mechanisms sharing
this one word — one raises on a calendar, the other on running hours or a
cycle count — and a PM schedule may run on either.
_Avoid_: Preventive maintenance (that is the kind of work it produces, not the
schedule itself), maintenance plan, recurring work order

**Part**:
A stocked item consumed doing a job, drawn from stock when it is booked
against a work order. A part is not an Asset: it is consumed and gone, where
an Asset is what work keeps being done on.
_Avoid_: Spare, material, stock item, component (that is a nested Asset, not
something consumed)

**CAPA**:
A corrective and preventive action: the investigation opened when something
went wrong badly enough to need a root cause and a fix that holds. A CAPA is
opened on a Concern, never beside one — the Concern stays the problem and its
Containments, Countermeasures and Preventive actions are the CAPA's actions,
while the CAPA adds the team, the root-cause analysis and the verification that
the fix held. A quality engineer decides to open one; nothing opens one by
itself. A CAPA is raised from a quality escape, a customer complaint, a
supplier non-conformance, a safety incident, or from nothing at all — so it
belongs to no one Module and is owned by none. Which Module the problem
surfaced in and which Module does the fixing are independent of each other, the
same way a KPI's Module and its Pillar are. One CAPA answers one Concern; a
cause shared across Org Units is answered by escalating the Concern, not by
linking several to one CAPA. A CAPA closes only when a root cause is confirmed
for both why it happened and why it was not detected, its Concern is closed, and
someone holding Quality authority other than its team lead has verified, some
time later, that the problem has not come back.
_Avoid_: Corrective action (that is one half of it), 8D (that is one method of
running one), ticket, issue

### Quality

**Non-conformance**:
Product found not to meet its requirement, recorded where it was found: what was
wrong, how much of it, and what was done with it. A Non-conformance records the
bad product, not the problem behind it — a Concern is raised from one only when
someone decides the cause needs solving, so a Non-conformance may have no
Concern and one Concern may answer several Non-conformances. It always names the
Product, and it is finished once its whole quantity has a Disposition, whether or
not the cause has been answered. The quantity found may grow as the product is
sorted but never shrinks, and may be recorded by an Employee on a floor device.
Its severity starts at its Defect code's own; whoever records it may raise that,
and only Quality authority may lower it.
_Avoid_: Quality issue, defect (that is what a Defect code names), reject, NC
report, NCR (that is a supplier non-conformance)

**Product**:
What the plant makes, kept in one catalogue shared by every Site and maintained
by an administrator. A lot is not a Product; it is a reference recorded against
one.
_Avoid_: Item, part (that is consumed doing maintenance), SKU, material

**Quality authority**:
The standing to decide about nonconforming product and its cause in an Org Unit:
grant a Concession, reopen a Non-conformance, open a CAPA, verify one held. It
is held on a Grant, so it reaches downward like the Grant does and belongs to a
place rather than a job title — an engineer with it on Line 2 has none on Line 5.
_Avoid_: Quality engineer (a job, not the authority), QA role, approver

**Defect code**:
The kind of thing found wrong on a Non-conformance, chosen from one list shared
by every Site and maintained by an administrator, so the same failure carries
the same code wherever it happens. Each code carries the severity a
Non-conformance recorded against it starts at.
Codes form a tree, so "every dimensional defect" is a single question.
_Avoid_: Defect type, failure mode, reason code, category (that is a grouping of
codes, not a code)

**Disposition**:
The decision about what happens to a Non-conformance's product — scrap, rework,
use as is, or return to the supplier — for some or all of its quantity. A
Non-conformance is dispositioned in parts as the product is sorted, and is not
finished while any of it is undecided.
_Avoid_: Decision, outcome, resolution, MRB result

**Concession**:
A Disposition to use nonconforming product as it is. Unlike scrap or rework it
accepts the product rather than dealing with it, so only a quality engineer may
grant one and their name stays on the record.
_Avoid_: Deviation (that is permission granted before the product is made),
waiver, use-as-is approval

### Safety

**Safety incident**:
Something that went wrong, recorded where it happened — the kind of event,
its place on the Severity level ladder, who was hurt if anyone, and what was
done about it right away. Every Safety incident names its reporter: an
Account, or an Employee identified at the shared floor device by their number
and PIN (ADR-0016). A record nobody can be traced back to cannot be followed
up, and the person who reported it cannot be told what was done about it.
_Avoid_: Near miss (that is one value each of Incident type and Severity
level, not a word for every incident), accident, safety report, incident
report

**Incident type**:
What kind of event a Safety incident was — an injury, a near miss, property
damage, an environmental release, a fire, an ergonomic event, or a security
event. It answers a different question from Severity level: the type says
what happened, the ladder says what it cost a person, so a fire that hurt
nobody is type `fire` sitting on the ladder's no-injury rung, exactly where a
near miss also sits. It is the field "near misses reported" counts, which is
why keeping the two apart matters.
_Avoid_: Using it interchangeably with Severity level (a `near_miss` incident
type and the ladder's `near_miss` rung answer different questions), severity,
category

**Severity level**:
The worst actual outcome an incident produced, **to a person**, placed on
the fixed ladder the injury rates are built on. Its bottom rung is spelled
`near_miss` in the schema and cannot be respelled, but it means **no
injury** — which is also where a damage-only fire honestly sits, since
nobody was hurt by either. What kind of event occurred — an injury, a near
miss, property damage, an environmental release, a fire — is a separate
field, Incident type, and Incident type is what "near misses reported"
counts, not this one.
_Avoid_: Reading the bottom rung as "this was a near miss" (it says nobody
was hurt, not what kind of event this was), using the ladder to mean how
serious the event felt (that question belongs to Severity potential, asked
of an observation, not to this field), severity

**Recordable**:
Whether an incident counts toward the plant's injury rate. Derived from the
Severity level — medical treatment and worse — and never ticked by hand,
because recordability follows a fixed rule and a hand-maintained flag is how
injury rates end up understated without anyone intending it.
_Avoid_: Reportable, a recordable incident (Recordable is a derived flag on
an incident, not a kind of incident)

**Safety observation**:
What was seen before anything went wrong — a safe act, an unsafe act, or an
unsafe condition, under one category — recorded at the Org Unit it was seen
at. The leading indicator, and the only number on the Safety Pillar a team
can move this week, where an incident count is mostly zero and occasionally
catastrophic.
_Avoid_: Safety walk (that is the activity that produces observations, not
an observation itself), audit, inspection finding

**Severity potential**:
The worst credible outcome of what was observed, not what actually
happened. Ranking an observation by potential rather than by outcome is what
stops a safety walk turning into a tally of trip hazards: an unsafe act with
fatal potential outranks fifty pieces of loose housekeeping in the queue for
attention.
_Avoid_: Severity level (that ladder ranks an incident's actual outcome to a
person; this ranks a credible one), risk rating, likelihood

**Stop-work**:
Somebody stopping a job on their own authority. Rare, and the single
strongest signal that a plant's safety culture is real — which is why it is
flagged on an observation and counted on its own rather than filed as just
another unsafe condition.
_Avoid_: Work stoppage, shutdown, refusal

**Safety authority**:
The standing to classify an injury, set an incident's severity, record what
it cost and close it, in an Org Unit. Held on a Grant, so it reaches
downward and belongs to a place rather than a job title — the same shape
Quality authority takes, and independent of it.
_Avoid_: Safety officer (a job, not the authority), safety role, approver

### The action log

**Action**:
One thing somebody must do about something, recorded at the Org Unit it is about
and owned by whoever will do it. The kinds are what an Action is to a problem: a
**Concern** is the problem itself, a **Containment** stops its effect now, a
**Countermeasure** removes its cause, a Preventive action stops the same failure
appearing somewhere else, an Improvement raises the level, and a Routine action
answers nothing — order the gloves, chase the supplier. Every Action runs its own
PDCA cycle (see **Action phase**), a Concern's measures hang off it one level
deep, and an Action's number is its own Site's.
_Avoid_: Task (that is a step inside a Work order), item, to-do, ticket, issue,
countermeasure (that is one kind of Action, not the whole of one)

**Concern**:
The Action recording something found wrong, and the thing its measures answer.
Anyone on the floor may raise one where they found it, whether or not they hold a
Grant reaching that Org Unit: a concern is a report, not a decision. An open
Concern may be escalated to an Org Unit above the one it was raised at, and it
stays open where it goes — the Org Unit on the record is where the problem is,
never where it went.
_Avoid_: Problem (an internal word — say Concern), issue, defect (a defect is a
recorded non-conformance, a different thing), abnormality

**Containment**:
The Action that stops a Concern's effect now, and nothing more: clamp it, tag it,
rework the batch. A Containment is raised before the cause is known, which is the
point of it, and it is never the fix — an Action that removes the cause is a
Countermeasure, and a Concern recorded with only a Containment behind it was
contained rather than answered.
_Avoid_: Quick fix, temporary action, band-aid, immediate corrective action

**Countermeasure**:
The Action that removes a Concern's cause, chosen once the cause is known. The
word is deliberate: a fix that blames a person corrects nothing, and what a plant
changes is the process a person works in. A Concern with no Countermeasure behind
it cannot be closed, which is what makes the difference between a claim and a
record.
_Avoid_: Corrective action (the CAPA entry already avoids it, and the schema's
own `action_type` value is `countermeasure` for the same reason), solution, fix,
remedy

**Action phase**:
One step of an Action's current PDCA cycle — **Plan** names what will be
different and who owns it, **Do** is the work, **Check** measures the result and
records whether it held, **Act** names the standard that now holds it. Each phase
carries its own owner and due date, and a Check that found the countermeasure did
not hold opens the next cycle's Plan rather than ending the Action, so an Action
may be several cycles long with every one of them kept.
_Avoid_: Step (a step is what a Job plan and a Work order are made of), stage,
status (the Action's own status is the schema's five words, and it is not one of
these), PDCA stage

### The numbers

**Pillar**:
One of the five KPI categories on the tier board: Safety, Quality, Cost,
Delivery and People. A Pillar is a heading the numbers report under, not a part
of the software. One Module feeds several Pillars.
_Avoid_: Module, area, category, SQDCP letter

**KPI**:
A number reported under a Pillar, calculated from the measurements Modules
record. Maintenance work yields MTBF under Delivery and parts cost under Cost —
which Module produced a KPI and which Pillar it reports under are independent.
_Avoid_: Metric, measure, indicator, stat

### The interface

**Screen**:
A full destination with its own address — sign-in, the Directory, the Approval
queue. A Screen is what a person navigates to and can bookmark or link to; a
dialog, a card or a panel inside one is not a Screen.
_Avoid_: Page, view

**Destination**:
An entry in the Shell's sidebar — a Screen an Account can reach directly, named
for what a person does there (the Directory, the Approval queue). Every
Destination is a Screen; not every Screen is one, since sign-in and
awaiting-Approval are reached without ever being offered. Which Destinations an
Account is offered follows from its role.
_Avoid_: Menu item, tab, nav link

**Destination group**:
A heading the Shell files Destinations under — People, Maintenance, Insights,
Administration. A group is a label and nothing more: it has no address, cannot
be selected, and opens nothing, so a person still navigates only to
Destinations. Groups are named for the Module behind their Destinations rather
than for what a person does, which ADR-0020 records as a deliberate reversal of
issue #39's original rule; a flat list stopped being scannable at sixteen
entries. A group whose Destinations an Account's role all filter away renders
no heading.
_Avoid_: Section, category, nav header, Module (a group is named after one, but
a Module is the code seam, not the label)

**Shell**:
The persistent chrome around every Screen: the sidebar carrying the
destinations, the brand header, and the account footer with sign-out. The Shell
stays put while Screens change beneath it, which is why the current destination
is marked there and nowhere else.
_Avoid_: Layout, frame, chrome
