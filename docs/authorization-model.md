# The authorisation model

**Status:** implemented by ADR-0061, migration
`1803400000000_permissions-and-roles.js`, and `backend/src/modules/people/`
(`permissions.js`, `roles.js`, `role-routes.js`).

This is the reference for two questions a person actually asks: *what is the
code for this function* and *which group does this function belong to*. The
authority is `backend/src/modules/people/permissions.js`; this page is
generated from it, and `backend/test/integration/roles.test.js` fails if the
database's seeded copy drifts from it.

## The four words

- **Permission** — one function, named by a **code** (`MTN_WORK_ORDERS_CHANGE`).
  Written by the Platform, never by an administrator; offered read-only over
  HTTP. SAP's *authorization object + activity*.
- **Role** — a named group of permissions with a code of its own
  (`ROLE_STORE_ROOM`). An administrator creates it and edits what it carries.
  SAP's *role*.
- **Assignment** — one Account holding one role because an administrator put it
  there, made by the **Assign** button on the Accounts Screen. SAP's *user master
  record + user comparison*, collapsed into one act.
- **Default group** — the one role every Account holds without being assigned
  anything (`ROLE_STANDARD`). SAP's `SAP_NEW` profile in spirit: the card's
  "nhóm chức năng mặc định".

A fifth word the Platform already had stays as it was: a **Grant** (`app_user_org_units`)
says *where* an Account may act. A permission says *what*. Both are asked; neither
implies the other.

## Effective permissions

`GET /api/people/me` answers the union of:

1. every permission carried by a role with `is_default = true`;
2. every permission carried by the role whose `legacy_role` equals this
   Account's own `app_users.role`;
3. every permission carried by a role an administrator assigned.

An Account whose `app_users.role` is `admin` is answered with the whole
catalogue before any of that is read (ADR-0061 §5: a mis-edited role must not
be able to lock the last administrator out).

## The catalogue — 83 permissions

Grouped by the sidebar's own headings, in its own order. Every Destination is
guarded by the `…_DISPLAY` code below; the other codes name a decision or a
write behind that Screen.

### People

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `PPL_DIRECTORY_DISPLAY` | Directory | Read the Employee directory and an Employee record. |
| `PPL_DIRECTORY_CHANGE` | Maintain Employees | Add an Employee, correct one, record an assignment, or mark one departed. |
| `PPL_JOB_ROLES_DISPLAY` | Job roles | Read the Job role catalogue. |
| `PPL_JOB_ROLES_CHANGE` | Maintain Job roles | Add a Job role or retire one. |
| `PPL_SKILLS_DISPLAY` | Skills | Read the Skills catalogue and who holds each one. |
| `PPL_SKILLS_CHANGE` | Maintain Skills | Add a Skill, retire one, or record that an Employee holds it. |
| `PPL_ORG_UNITS_DISPLAY` | Org Units | Read the Org Unit tree and the Sites it hangs beneath. |
| `PPL_ORG_UNITS_CHANGE` | Maintain Org Units | Add or change a Site or an Org Unit, or import a tree. |
| `PPL_ATTENDANCE_DISPLAY` | Attendance | Read a shift instance's Attendance sheet. |
| `PPL_ATTENDANCE_CHANGE` | Confirm Attendance | Confirm an Attendance sheet for a shift instance. |
| `PPL_TRAINING_DISPLAY` | Training | Read Training records and follow one that names the caller. |
| `PPL_TRAINING_CHANGE` | Raise Training | Raise a Training record, add a trainee, or sign one off. |
| `PPL_TRAINING_ANSWER_OWN` | Answer my Training | Answer the caller's own training question as its Trainee. |
| `PPL_SIGNATURE_OWN` | My signature | Store and change the caller's own signature. |
| `PPL_LEAVE_REQUESTS_DISPLAY` | Leave requests | Read the caller's own leave requests and those they decide. |
| `PPL_LEAVE_REQUESTS_DECIDE` | Decide Leave | Approve or decline a leave request for an Employee in the caller's scope. |
| `PPL_LEAVE_REQUESTS_RAISE` | Raise my Leave | Raise the caller's own leave request, and cancel it before a decision. |
| `PPL_COST_RATES_MAINTAIN` | Cost rates | Maintain the cost rates an Employee's hours are priced at. |
| `PPL_PRODUCT_COSTS_MAINTAIN` | Product standard costs | Maintain a product's standard cost. |

`PPL_TRAINING_ANSWER_OWN` and `PPL_LEAVE_REQUESTS_RAISE` were added after the
catalogue shipped (ADR-0061, slice 5b). Their `sort_order` values are 81 and 82 —
appended rather than a released list renumbered — and the Roles Screen, which
groups by module, shows them inside the People group.

### Maintenance

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `MTN_ASSETS_DISPLAY` | Assets | Read the Asset register. |
| `MTN_ASSETS_CHANGE` | Maintain Assets | Add or change an Asset, nest one, or retire one. |
| `MTN_WORK_ORDERS_DISPLAY` | Work orders | Read Work orders and one Work order's detail. |
| `MTN_WORK_ORDERS_CHANGE` | Maintain Work orders | Raise, assign, complete or cancel a Work order. |
| `MTN_PARTS_DISPLAY` | Parts | Read the Parts catalogue. |
| `MTN_PARTS_CHANGE` | Maintain Parts | Add or change a Part. |
| `MTN_STORES_DISPLAY` | Stores | Read Stores and their stock. |
| `MTN_STORES_CHANGE` | Maintain Stores | Add a Store or record stock movement. |
| `MTN_REQUESTS_RAISE` | Raise a Request | Raise a Maintenance Request and follow the ones the caller raised. |
| `MTN_REQUESTS_TRIAGE` | Triage Requests | Read the triage queue and accept or decline a Request. |
| `MTN_DOWNTIME_DISPLAY` | Downtime | Read recorded downtime. |
| `MTN_DOWNTIME_CHANGE` | Record Downtime | Record downtime against an Asset and its reason. |
| `MTN_PM_SCHEDULES_DISPLAY` | PM schedules | Read preventive-maintenance schedules. |
| `MTN_PM_SCHEDULES_CHANGE` | Maintain PM schedules | Add or change a preventive-maintenance schedule. |
| `MTN_METERS_DISPLAY` | Meters | Read Asset meters and their readings. |
| `MTN_METERS_CHANGE` | Record meter readings | Record a meter reading that drives a PM schedule. |
| `MTN_JOB_PLANS_MAINTAIN` | Job plans | Maintain the Job plans a PM schedule runs. |

### Actions

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `ACT_LOG_DISPLAY` | Action log | Read the action log: Concerns and CAPAs. |
| `ACT_RAISE` | Raise a Concern | Raise a Concern where the caller found it. |
| `ACT_MEASURE` | Record measures | Record an immediate measure against a Concern. |
| `ACT_VERIFY` | Verify an Action | Verify an Action that has been carried out. |
| `ACT_CAPA_DISPLAY` | CAPAs | Read an investigation. |
| `ACT_CAPA_OPEN` | Open a CAPA | Open an investigation on a Concern. |
| `ACT_CAPA_VERIFY` | Verify a CAPA | Sign off an investigation's root causes and whys. |
| `ACT_CAPA_EFFECTIVENESS` | Check effectiveness | Check whether an investigation's measures held. |
| `ACT_CHANGE` | Change an Action | Link or unlink a Non-conformance, hand an Action up, or call one off. |

### Quality

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `QLT_PRODUCTS_DISPLAY` | Products | Read the product catalogue. |
| `QLT_PRODUCTS_CHANGE` | Maintain Products | Add or change a product. |
| `QLT_DEFECT_CODES_DISPLAY` | Defect codes | Read the defect-code catalogue. |
| `QLT_DEFECT_CODES_CHANGE` | Maintain defect codes | Add or change a defect code. |
| `QLT_NONCONFORMANCES_DISPLAY` | Non-conformances | Read the Non-conformance register. |
| `QLT_NONCONFORMANCES_RECORD` | Record a Non-conformance | Record a Non-conformance where it was found. |
| `QLT_NONCONFORMANCES_DISPOSE` | Dispose of nonconforming product | Concede, rework or scrap nonconforming product. Needs Quality authority at the Org Unit. |
| `QLT_CUSTOMERS_DISPLAY` | Customers | Read the customer catalogue. |
| `QLT_CUSTOMERS_CHANGE` | Maintain Customers | Add or change a customer. |
| `QLT_COMPLAINTS_DISPLAY` | Customer complaints | Read the customer-complaint register. |
| `QLT_COMPLAINTS_RECORD` | Record a complaint | Record a customer complaint. |
| `QLT_SLIDESHOW_DISPLAY` | Slide show | Open the shop-floor slide show. |
| `QLT_SLIDESHOW_CHOOSE` | Choose slide-show issues | Put a Quality issue in the slide show and order it. |
| `QLT_SUPPLIERS_DISPLAY` | Suppliers | Read the supplier catalogue. |
| `QLT_SUPPLIERS_CHANGE` | Maintain Suppliers | Add or change a supplier. |
| `QLT_SUPPLIER_NCRS_DISPLAY` | Supplier NCRs | Read the supplier non-conformance reports. |
| `QLT_SUPPLIER_NCRS_RECORD` | Record a supplier NCR | Record a supplier non-conformance report. |

### Safety

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `SAF_INCIDENTS_DISPLAY` | Incidents | Read the Safety incident register. |
| `SAF_INCIDENTS_RECORD` | Record an Incident | Record a Safety incident. |
| `SAF_CLASSIFY` | Classify an injury | Record or read an injured person's diagnosis. Needs Safety authority at the Org Unit (ADR-0037). |
| `SAF_OBSERVATIONS_DISPLAY` | Observations | Read the Safety observation register. |
| `SAF_OBSERVATIONS_RECORD` | Record an Observation | Record a Safety observation. |
| `SAF_INJURY_TYPES_MAINTAIN` | Injury types | Maintain the injury-type catalogue. |
| `SAF_BODY_PARTS_MAINTAIN` | Body parts | Maintain the body-part catalogue. |

### Production

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `PRD_HANDOVER_DISPLAY` | Shift handovers | Read a Section's Shift handover. |
| `PRD_HANDOVER_WRITE` | Write a Shift handover | Open, amend and submit a Section's Shift handover. |
| `PRD_HANDOVER_ACKNOWLEDGE` | Acknowledge a Shift handover | Acknowledge the Shift handover handed to the caller. |

### Insights

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `INS_TIER_BOARD_DISPLAY` | Tier board | Read the tier board. |
| `INS_SKILL_COVERAGE_DISPLAY` | Skill coverage | Read how coverage of each Skill stands across a Site. |
| `INS_KPI_CATALOGUE_DISPLAY` | KPI catalogue | Read the MTU KPI catalogue and its Targets. |
| `INS_KPI_CATALOGUE_CHANGE` | Maintain the KPI catalogue | Add a KPI or change its Targets. |
| `INS_KPI_REVIEW_DISPLAY` | KPI review | Read the daily KPI review. |
| `INS_KPI_REVIEW_RECORD` | Record a KPI review | Record the daily KPI review. |

### Administration

| Code | Screen or function | What it permits |
| --- | --- | --- |
| `ADM_APPROVALS_DISPLAY` | Approvals | Read the queue of Accounts awaiting Approval. |
| `ADM_APPROVALS_DECIDE` | Decide an Approval | Admit an Account with its role and Grants, or reject it. |
| `ADM_ACCOUNTS_DISPLAY` | Accounts | Read every Account and the Grants each holds. |
| `ADM_ACCOUNTS_CHANGE` | Administer Accounts | Correct an Account's role or Grants, or deactivate it. |
| `ADM_ROLES_DISPLAY` | Roles | Read the roles and the permissions each carries. |
| `ADM_ROLES_CHANGE` | Maintain roles | Create a role, change what it carries, retire it, or assign it to an Account. |


## The seeded roles

| Role code | Name | Held automatically by | What it adds |
| --- | --- | --- | --- |
| `ROLE_STANDARD` | Standard | every Account | The default group: the directory, the registers every Account reads, raising a Concern or a Request, the tier board, the Section handover, the two self-service acts — answering the caller's own training question and raising (or cancelling) their own leave request — and, since the Actions write retrofit (issue #533), the Quality write retrofit (issue #535) and the Safety write retrofit (issue #537), every Actions, Quality and Safety write code those slices gate, because those writes were reachable by any Grant-holder before them and the retrofit takes no act away from the shop floor |
| `ROLE_OPERATOR` | Operator | `app_users.role = operator` | Nothing beyond the default group — today an operator is offered nothing more, and the group says so rather than showing an empty list |
| `ROLE_SUPERVISOR` | Supervisor | `app_users.role = supervisor` | The Maintenance Screens (Assets, Work orders, Parts, Stores, Triage, Downtime, PM schedules, Meters) **and the writes behind them** — add an Asset, raise/assign/start/complete/cancel a Work order, book labour and parts, record a task's meter reading, open a Store and record a stock movement, create or deactivate a PM schedule and run its sweep — plus the Insights registers, confirming Attendance, raising Training, deciding Leave, recording measures and incidents |
| `ROLE_ENGINEER` | Engineer | `app_users.role = engineer` | A supervisor's set plus the writes behind an Asset, Work order, Part, Store and PM schedule, and opening and verifying a CAPA |
| `ROLE_MANAGER` | Manager | `app_users.role = manager` | An engineer's set — the two are seamed apart so they can diverge without another release |
| `ROLE_ADMIN` | Administrator | `app_users.role = admin` | Every permission (see §5 of ADR-0061 for the short-circuit that makes this true regardless) |

Each `legacy_role` role reproduces **exactly** the doors its `app_users.role`
value opened before ADR-0061, which is what makes the change backward-compatible
with no data migration. Changing one is how an administrator changes what
everybody in that account role may do.

## Adding a function

1. Add the code to `backend/src/modules/people/permissions.js` — module, label,
   the sentence an administrator reads.
2. New migration inserting that code into `permissions` (the frozen copy; never
   edit the old migration).
3. `GET /api/people/me` carries it automatically; decide whether any seeded role
   should carry it and seed `app_role_permissions` for it.
4. A sidebar Destination for it gets one line in `destinationPermissions`
   (`frontend/lib/platform/destinations.dart`), or it stays ungated — a missing
   line is an open door, not a build error.
5. Guard the route it protects with `requirePermission('THE_CODE')` when the
   rollout reaches that Module.

## What is not enforced yet

The codes decide the **sidebar** and the **roles surface**
(`ADM_ROLES_DISPLAY` / `ADM_ROLES_CHANGE`). The Maintenance Module's sixteen
write routes were retrofitted in ADR-0061's slice 2b: each asks its `…_CHANGE`
code *and* keeps the Grant check behind it, because the code answers which door
and the Grant answers which Org Units. The People Module's writes followed in
slice 5b — the Training writes, the Attendance writes and the leave decisions
ask their managing codes, and the two self-service acts ask the pair added
above — so an operator who holds an edit Grant on a People Screen no longer
performs the managing writes unless an administrator adds the code to its role
(the seed migration and that release's PR body state this narrowing). ADR-0061's
slice 8 closed the last three doors §7 still listed as outstanding — every
remaining role comparison outside Production is a write, listed below — and
left this shape:

- **`POST /parts` asks `MTN_PARTS_CHANGE`** (ADR-0061 slice 8). That gate
  *widened* the write: the code is carried by engineer and manager as well as
  administrator, so an engineer can now define a Part where the `requireAdmin`
  comparison refused it. The widening is deliberate — the seed already declared
  that an engineer maintains Part master data — and an administrator reverses it
  by taking the code off `ROLE_ENGINEER` / `ROLE_MANAGER` in the Roles Screen.
- **The Accounts reads ask `ADM_ACCOUNTS_DISPLAY`**, a pure rename: the code is
  carried by `ROLE_ADMIN` alone, exactly the set `requireAdmin` admitted.
- **The Maintenance reads stay open** (`GET /sites/:siteId/assets`, the parts
  and store reads). Several Screens read the same endpoints, so a read gate
  would narrow Screens that never asked for it — the rule, its exception list
  and the test that holds it are ADR-0061 §7.
- **The People and KPI writes are gated too** (ADR-0061, phase 2d — the
  section at the end of this file): the five Account writes, the Site and Org
  Unit writes, the technician-credential write, the Employee-assignment write
  and the two MTU KPI catalogue writes. With that slice, **no route chain in
  `backend/src/modules/**/[a-z-]*routes.js` compares the role string any more**;
  the only role comparison left in a write path is the root-row check inside
  `org-unit-import.js`, which the route's own code now precedes.

The Actions Module's sixteen write routes were retrofitted next (ADR-0061,
issue #533). Every write asks the code that names its act — `ACT_CHANGE`,
`ACT_MEASURE`, `ACT_VERIFY`, `ACT_CAPA_OPEN`, `ACT_CAPA_VERIFY`,
`ACT_CAPA_EFFECTIVENESS` — *and* keeps the scope or authority helper behind it,
so the code answers which door and the helper still answers whose Action, which
Org Unit. `ACT_CHANGE` is the one code this slice added, for the four acts the
catalogue had no code for: linking or unlinking a Non-conformance, handing an
Action up, calling one off. `1803800000000_actions-write-codes.js` seeds all six
on every role, which is a widening in every case — `ACT_MEASURE` and `ACT_VERIFY`
were supervisor-and-above, the three CAPA codes engineer-and-above, and the
writes themselves were reachable by any Account holding the right Grant, or a
place on a CAPA team, whatever its role. So **no caller's answer changes**: what
these codes buy is that each door is now visible and removable in the Roles
Screen. An administrator who decides verifying an Action belongs to supervisors
takes `ACT_VERIFY` off `ROLE_OPERATOR` and every operator loses it at once,
which a Grant cannot express. This slice does not enforce the seed's narrower
declaration on its own — taking live capabilities off a plant is the owner's
decision, not a migration's.

Retrofitting `requirePermission` onto the other Modules' routes is a follow-on
card per Module, because each write needs its own code chosen against the ADR
that governs that Module's authority.

The Quality Module's thirteen write routes were retrofitted next (ADR-0061,
issue #535). Every one asks the code that names its act *and* keeps the scope or
authority helper behind it, so the code answers which door and the helper still
answers which Site, which record:

| Route | Code |
| --- | --- |
| `POST /complaints/:id/respond`, `POST /complaints/:id/link` | `QLT_COMPLAINTS_RECORD` |
| `POST /nonconformances/:id/dispositions` | `QLT_NONCONFORMANCES_RECORD` |
| `POST /nonconformances/:id/concession`, `/lower-severity`, `/reopen`, `/cancel` | `QLT_NONCONFORMANCES_DISPOSE` |
| `PUT /slide-show/:kind/:id`, `PUT /sites/:siteId/slide-show/order` | `QLT_SLIDESHOW_CHOOSE` |
| `POST /sites/:siteId/supplier-ncrs`, `POST /supplier-ncrs/:id/disposition`, `/close`, `/link` | `QLT_SUPPLIER_NCRS_RECORD` |

The Concession/Disposition split is deliberate and is kept: a Concession is a
**decision** about the product (`QLT_NONCONFORMANCES_DISPOSE`), a Disposition is
recorded **work** (`QLT_NONCONFORMANCES_RECORD`). Lowering a severity, reopening
and cancelling are the same Quality authority over the same record as a
Concession, so they ask the disposal code — the shape `ACT_CHANGE` gave the four
Actions acts the catalogue had no code for. `POST /floor/nonconformances` is the
one Quality write left ungated: it is the shared floor device's door
(`requireTechnicianIdentification`, ADR-0016), the class ADR-0061 §7 registers as
having no code that could name it.

`1803900000000_quality-write-codes.js` widens the seed wherever today's reach was
wider than the code's, which is every case where the seed did not already say
"every role":

- `QLT_NONCONFORMANCES_DISPOSE` — engineer, manager, administrator → the default
  group, operator, supervisor, engineer, manager, administrator.
- `QLT_SLIDESHOW_CHOOSE` — administrator → the same six.
- `QLT_SUPPLIER_NCRS_RECORD` — administrator → the same six.
- `QLT_NONCONFORMANCES_RECORD` and `QLT_COMPLAINTS_RECORD` already sat on the
  same six roles; no row was written for them.

Thirteen rows, every one a widening, and **no caller's answer changes**: a
disposition, a Concession, a slide-show choice and a supplier NCR were all
reachable by any Account holding the right Grant before this slice, whatever its
role, and are still reachable by it. What these codes buy is the same thing the
Actions slice bought — each door is visible and removable in the Roles Screen. An
administrator who decides that granting a Concession is an engineer's act takes
`QLT_NONCONFORMANCES_DISPOSE` off `ROLE_OPERATOR` and every operator loses it at
once, which a Grant cannot express.

The Safety Module's four Safety-authority writes were retrofitted next (ADR-0061,
issue #537). Each asks the code that names its act *and* keeps
`requireSafetyIncidentSafetyAuthority` behind it, so the code answers which door
and the helper still answers whose Site and whose Org Unit:

| Route | Code |
| --- | --- |
| `POST /incidents/:id/severity`, `POST /incidents/:id/classify` | `SAF_CLASSIFY` |
| `POST /incidents/:id/days`, `POST /incidents/:id/close` | `SAF_INCIDENTS_RECORD` |

The split follows the catalogue's own sentences: `SAF_CLASSIFY` is "record or
read an injured person's diagnosis", which is what deciding a severity and naming
the injury are, while `SAF_INCIDENTS_RECORD` is the incident's own record, which
the days it cost and the close are maintaining. `POST /floor/incidents` and
`POST /floor/observations` are the one pair of Safety writes left ungated: they
are the shared floor device's door (`requireTechnicianIdentification`,
ADR-0016), the class §7 of ADR-0061 registers as having no code that could name
it.

The Safety module's other six routes were gated by issue #507 and are unchanged
here: `SAF_INCIDENTS_DISPLAY` on the register, the overdue listing and one
record's read, `SAF_INCIDENTS_RECORD` on recording, the due-date PATCH and the
ordinary status move.

`1804000000000_safety-write-codes.js` widens the one seed today's reach outgrew:

- `SAF_CLASSIFY` — supervisor, engineer, manager, administrator → the default
  group, operator, supervisor, engineer, manager, administrator.
- `SAF_INCIDENTS_RECORD` already sat on all six roles; no row was written, so
  the days and the close narrow nobody.

Two rows, both a widening, and **no caller's answer changes**: the four writes
were reachable by any Account holding Safety authority at the incident's Org
Unit, whatever its role — a flag on a Grant, not a role (ADR-0035, ADR-0039) —
and are still reachable by it. What these codes buy is the same thing the
Actions and Quality slices bought: each door is visible and removable in the
Roles Screen. An administrator who decides that classifying an injury is a
supervisor's act takes `SAF_CLASSIFY` off `ROLE_STANDARD` and `ROLE_OPERATOR` and
every operator loses it at once, which a Grant cannot express. This slice does
not enforce the seed's original supervisor-and-above declaration on its own —
that would take a live capability off the plant, which is the owner's decision.

The People and KPI writes were retrofitted last (ADR-0061, phase 2d, issue
#539), and that slice is what makes the rule above ("no route compares the role
string") true for the whole backend. Each route asks the code that names its act
*and* keeps its scope middleware behind it, so the code answers which door and
the middleware still answers which Site, which Org Unit, which part of the tree:

| Route | Code | Scope kept behind it |
| --- | --- | --- |
| `POST /sites` | `PPL_ORG_UNITS_CHANGE` | — (a Site is not owned by a Grant) |
| `PATCH /sites/:siteId` | `PPL_ORG_UNITS_CHANGE` | existence: 404 before the code (`requireSitePermission`) |
| `POST /sites/:siteId/org-units` | `PPL_ORG_UNITS_CHANGE` | write scope on the parent, when the body names one |
| `POST /sites/:siteId/org-units/import` | `PPL_ORG_UNITS_CHANGE` | Site scope |
| `PATCH /org-units/:id` | `PPL_ORG_UNITS_CHANGE` | write scope on the Org Unit |
| `PUT /floor-technician-credentials/:employeeId` | `PPL_DIRECTORY_CHANGE` | — (keyed to an Employee, not an Org Unit) |
| `POST /employees/:id/assignments` | `PPL_DIRECTORY_CHANGE` | write scope on the destination Org Unit |
| `POST /accounts/:id/approval`, `POST /accounts/:id/rejection` | `ADM_APPROVALS_DECIDE` | — |
| `PATCH /accounts/:id`, `PUT /accounts/:id/employee`, `POST /accounts/:id/password` | `ADM_ACCOUNTS_CHANGE` | — |
| `POST /catalogue`, `POST /targets` (Insights/KPI) | `INS_KPI_CATALOGUE_CHANGE` | `canAct({ write: true })` on the Site's root Org Unit |

The split is the catalogue's own sentences: `PPL_ORG_UNITS_CHANGE` is "add or
change a Site or an Org Unit, or import a tree"; `PPL_DIRECTORY_CHANGE` is "add
an Employee, correct one, record an assignment, or mark one departed", which is
why the Employee link inside Administration does **not** ask it — it is an
Account's own row, so it is `ADM_ACCOUNTS_CHANGE`; deciding an Approval is a
decision of its own, so it is `ADM_APPROVALS_DECIDE`.

Every code above except `INS_KPI_CATALOGUE_CHANGE` was already seeded on exactly
the callers the role comparison it replaced admitted, so **eight of these
fourteen routes change no caller's answer** — only the refusal body, from "This
action requires the administrator role." to a `PERMISSION_REQUIRED` naming the
code. The rest are declared narrowings and each is written down in its route
file:

- **`PATCH /org-units/:id`**, the child branch of **`POST /sites/:siteId/org-units`**
  and **`POST /sites/:siteId/org-units/import`** were scope-only: any Account
  holding a write Grant on the Org Unit could deactivate it, add a child to it
  or import beneath it, whatever its role. They now also ask
  `PPL_ORG_UNITS_CHANGE`, which is administrator-only, so a supervisor holding
  such a Grant loses the write until an administrator adds the code to a role it
  holds. Seeding the code up to today's reachers is not the fix here: the same
  code also names creating a Site, so widening it would hand every role in that
  seed the power to create Sites.
- **`POST /employees/:id/assignments`** was scope-only for the same reason and
  now asks `PPL_DIRECTORY_CHANGE`, also administrator-only. Widening that code
  instead would take four administrator-only payroll writes (create, correct,
  mark departed, reinstate) and hand them to every supervisor — a bigger and
  worse change than the one it would avoid.
- **`POST /catalogue` / `POST /targets`** were Grant-only. `1804100000000_kpi-catalogue-write-roles.js`
  seeds `INS_KPI_CATALOGUE_CHANGE` onto supervisor, engineer and manager — the
  three roles `ModuleRoles.kpi` offers the Screen to, so every role the UI
  enables "Add KPI" for keeps it. An operator-role Account with a root write
  Grant loses the two writes, which is the same declared narrowing
  `1803500000000_supervisor-holds-maintenance-writes.js` accepted for
  Maintenance.

**Left ungated, with reasons.** `POST /login` and `POST /logout` run before and
after a session; `POST /floor/identify` and `POST /floor-devices` are the device
enrolment door of ADR-0016; `POST /leave-requests/:id/cancel` is decided inside
by `requireCancelDoor` (requester versus supervisor), which slice 5b kept on
purpose; and `POST /floor/training/trainees/:traineeId/answer` is the shared
floor device's door, where there is no Account at all for a code to be read
from — `requireTechnicianIdentification` is that door's whole authority, the
same class ADR-0061 §7 registers for Safety's floor pair.
