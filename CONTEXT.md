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
Employees — and produces the measurements KPIs are calculated from. A Module is
a slice of one application, never a separately deployed app.
_Avoid_: App, service, pillar, subsystem

### The plant

**Site**:
One plant. Sites are plural and independent: each keeps its own shift pattern
and its own local time, so a production day means something different at each.
Every part of the plant hierarchy belongs to exactly one Site.
_Avoid_: Factory, location, facility, plant (use Site in prose about the model)

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

**Job role**:
What an Employee is assigned to do — Fitter, Line Operator, Quality
Inspector — held through their current Assignment rather than as a property
of the Employee itself. Job roles are defined once and shared by every
Site: a Fitter is a Fitter wherever they work, not a value duplicated into
each Site's own catalogue.
_Avoid_: Position, job title, role (an Account's own role is a different
fact — what it may do in this Platform, not what an Employee does on the
floor)

**Assignment**:
Where an Employee works, and as what, over time: an Org Unit and, usually, a
job role, each dated from when it began. An Assignment is history, not a
snapshot — it is never edited in place to reflect a move, only closed with
an end date, so a staffing question asked about last month is answered with
last month's Assignment, not today's.
_Avoid_: Posting, placement, position

**Transfer**:
An Employee moving to a new Org Unit, a new job role, or both. A Transfer is
recorded as a new Assignment that closes the previous one, never as an edit
to it: the old Assignment keeps its own start date and gains an end date,
intact rather than overwritten, which is what keeps the answer to "where did
they work before" honest after they move again.
_Avoid_: Move, reassignment

**Directory**:
The searchable listing of Employees, and the detail view behind one of
them — job role, Org Unit assignments and skills. Readable by any approved
Account regardless of their own Org Unit grants: a plant directory is not a
secret, and Org Unit scope decides where an Account may act, not who it may
know about.
_Avoid_: Employee list, staff directory, org chart

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
_Avoid_: Activation, verification, registration, onboarding

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
