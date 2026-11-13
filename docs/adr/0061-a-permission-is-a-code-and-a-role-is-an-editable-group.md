# 0061 — A permission is a code, a role is a group of them, and the default group is not assigned

- **Status:** Accepted
- **Date:** 2026-11-13
- **Issue:** #492

## Context

Who may do what was decided in two places and neither was data. On the server,
`app_users.role` — five values, `operator`/`supervisor`/`engineer`/`manager`/
`admin` — plus a Grant on an Org Unit that says whether a write is allowed
where. On the client, `ModuleRoles` in `frontend/lib/platform/destinations.dart`
repeated the same five values to decide which of forty-two sidebar entries to
draw. Adding a Module meant editing both, and the only way to give one person
one extra function was to give them a whole role.

The owner asked for SAP's shape instead, in these words: every permission is
identified by a role code, an administrator puts a person into the group and
presses assign, a group is a set of permissions the administrator can change,
and there is a default group of functions everybody has.

## What SAP actually does

Checked against SAP's own documentation rather than memory, because three of
the four mechanisms are easy to conflate:

1. **Authorization object + activity.** A function is an authorization object
   (`M_MSEG_WMB`) with up to ten fields, each with permitted values, one of
   which is usually `ACTVT` — `01` create, `02` change, `03` display. A single
   authorization is "object + permitted field values". Objects are supplied in
   code; an administrator never invents one.
2. **Role (PFCG).** A role is a bundle of authorizations plus a menu, with a
   technical name of up to 30 characters (`Z_MM_DISPLAY`) — the "role code".
   Editing its authorizations regenerates the role's **profile** (`T-…`), which
   is what the user master actually holds. A **composite role** is a group of
   roles.
3. **User master record + user comparison.** `SU01` assigns roles to a person,
   with validity dates. The assignment alone grants nothing until a **user
   comparison** runs — `SU01` does it on save; `PFCG`'s User tab offers a full
   comparison to push a changed role out to everyone holding it. The change
   lands at that person's next logon, and `PFCG_TIME_DEPENDENCY` moves roles
   whose validity window has opened.
4. **A default.** The `SAP_NEW` profile: SAP generates it with the authority
   checks a release introduces, so an upgrade does not lock everybody out
   before roles are adjusted. It is a bridging default, not a curated set of
   common functions.

So the recollection was right about the mechanics with two corrections that
matter for the design: **a role is not the atomic permission** (the object plus
activity is), and **assignment is two steps in SAP** (assign, then compare)
even though `SU01` hides the second behind the same button.

## Decision

Four tables, and every claim below is a thing a test can check.

### 1. The catalogue is code, not data — `permissions`

`permissions(code, module, label, description, sort_order)`, seeded by migration
`1803400000000_permissions-and-roles.js` and offered read-only over HTTP. A
code is born in `backend/src/modules/people/permissions.js`; the migration
carries a frozen copy (a migration is a one-way door, ADR-0007) and
`test/integration/roles.test.js` asserts the two agree, which is what keeps the
copy honest.

Codes read `<MODULE>_<THING>_<ACTIVITY>`:
`PPL`/`MTN`/`ACT`/`QLT`/`SAF`/`PRD`/`INS`/`ADM` for the Module, and `DISPLAY`
(`ACTVT` 03), `CHANGE` (`ACTVT` 02), or a verb naming the one decision the
Screen exists for where "change" is too coarse to be safe
(`QLT_NONCONFORMANCES_DISPOSE`, `SAF_CLASSIFY`, `ACT_CAPA_VERIFY`,
`PPL_LEAVE_REQUESTS_DECIDE`).

This is SAP's authorization object, not its role: the supplier writes it, the
administrator grants it.

### 2. A role is an editable group — `app_roles` + `app_role_permissions`

`app_roles(code, name, description, is_default, legacy_role, is_active)` with a
3–30 character code shape (SAP's own technical-name limit) and
`app_role_permissions(app_role_id, permission_code)`.

An administrator edits the set and the change applies to everyone holding the
role on their next request — the effect of SAP's profile regeneration plus user
comparison, arrived at from the other end. There is no delete: a role is
retired with `is_active = false`, the same rule job roles and Employees already
follow (ADR-0009).

### 3. Assignment is one table, and it replaces — `app_user_roles`

`PUT /api/people/accounts/:id/roles` takes the complete set of role ids an
administrator wants and replaces what the Account held, in one transaction. It
is the card's "Assign" button.

**Deviation from SAP, named:** there is no user-comparison step and no validity
window. A `PUT` takes effect on the Account's next request, and a role has no
`valid from`/`to`. Both were left out because neither has a caller on this
Platform yet: nothing here is hired against a dated authorization, and the
freshness the rest of the Module already gives (a Grant revoked takes effect on
the next request, `authorization.js`'s own header) is what "comparison" would
buy.

### 4. Two automatic sources, so nothing is backfilled

- `is_default = true` — the group **every** Account holds. This is the card's
  "nhóm chức năng mặc định". `app_roles_one_default` (a partial unique index)
  makes it at most one role: two "everyone" groups would make the effective set
  depend on which one a reader happened to query.
- `legacy_role` — the `app_users.role` value that earns a role automatically.
  Seeded as `operator`, `supervisor`, `engineer`, `manager`, `admin`, one role
  each, carrying **exactly the doors those roles open today**. That is what
  makes this change backward-compatible without a data migration: every
  existing Account is in the right group the moment the migration runs, and
  `app_users.role` is not touched — it is still the column the Accounts Screen
  and the route guards read.

The honest consequence: an operator's own role adds nothing beyond the default
group, because today an operator earns nothing beyond the ungated Screens. The
seeded `ROLE_OPERATOR` carries the same set as `ROLE_STANDARD` so an
administrator opening it sees the truth rather than an empty group.

### 5. An administrator holds every permission, before any role is read

`effectivePermissions` short-circuits for `role = 'admin'` and answers with the
whole catalogue — SAP's `SAP_ALL`, kept for one reason: a mis-edited role must
not be able to lock the last administrator out of the Platform. It is recorded
here rather than left as a surprise, and it is why `ROLE_ADMIN`'s seeded
permission list documents the fact rather than producing it.

### 6. The sidebar filters on codes, and the role sets survive as a fallback

`/me` answers `permissions` (codes) and `roles` (role codes). The Shell filters
each Destination through `destinationPermissions` — one table mapping a
Destination's path to its code — instead of the old `ModuleRoles` sets. The
sets are kept and are used when the response carries no `permissions`, so a
cached client outliving a deploy still draws a usable sidebar.

### 7. A read several Screens legitimately read carries no code

The retrofit asks every read one question: which code names this door? For a
read that belongs to one Module's own Screen the answer is that Screen's
`*_DISPLAY` code. For **reference data several Screens legitimately read** the
answer is none. `GET /api/maintenance/sites/:siteId/assets` is read by the
Maintenance Request form — an operator must name an Asset to raise one — by the
Safety incident form and by the Quality non-conformance form, all of them
offered to every approved Account. `MTN_ASSETS_DISPLAY` names one Screen among
those four. A code every caller must hold is ceremony that buys nothing until an
administrator removes it from a role, and then it breaks a Screen nobody
realised was connected to it.

So: **a read several Screens legitimately read stays authenticated-but-ungated;
a read that belongs to one Module's own Screen keeps that Screen's `*_DISPLAY`
code.** The question a shared lookup actually asks is *whose rows may this
caller see*, and the containment test already answers it — `requireSiteScope`
for a Site, `requireOrgUnitScope` for an Org Unit branch, `canAct` where a row's
Grant matters. **Writes are unaffected:** every write carries a code, because a
write is always one Screen's act. This section records a rule the code already
followed in four slices, each time as a finding rather than a decision
(`t_3271c590`).

The register below is the whole of it, and it is checked rather than trusted:
`backend/test/shared-reference-reads.test.js` walks every Module router, collects
the `GET` routes that ask neither `requirePermission` nor a `may…` derivation of
it, and fails unless the set is exactly this list. A new shared read cannot join
it silently; a route here that gains a code cannot leave it silently.

#### Reads that carry no code because several Screens read them

| Route | Why it is shared |
| --- | --- |
| `GET /api/people/timezones` | The valid values for a Site's `timezone`: a non-administrator opening the Site form must see the list, and the list carries no plant data of its own (ADR-0023). |
| `GET /api/people/sites` | Filtered to the Sites the caller can see, so there is nothing to 403 on; every Screen that names a Site reads it (ADR-0008). |
| `GET /api/people/sites/:siteId` | Behind `requireSiteScope`, which is exactly "may this caller see this Site"; read by the Site picker, the Org Unit register and the KPI context. |
| `GET /api/people/sites/:siteId/org-units` | The same gate, then a per-row `canAct`; the Directory, Attendance, Training, Leave and the KPI views all read it. |
| `GET /api/people/sites/:siteId/org-units/search` | The same list, searched — the one control every Org Unit picker uses. |
| `GET /api/people/org-units/:id` | Behind `requireOrgUnitScope`, which answers whose row it is; the Asset form, the Work order form and People's own register read it. |
| `GET /api/people/org-units/:id/subtree` | The same gate, as the branch picker under a caller's own area. |
| `GET /api/people/cost-rates`, `/cost-rates/scopes`, `/cost-rates/resolution` | A rate is shared reference data (ADR-0005), and the resolution read is how a reader learns what a cost view will use — a number the tier board already shows them. The catalogue's only code is its administrator-only *maintenance* code, which would refuse those readers. |
| `GET /api/people/product-costs`, `/product-costs/products` | The same shape for the standard-cost catalogue and its Product picker. |
| `GET /api/maintenance/sites/:siteId/assets` | Read by the Maintenance Request form, the Safety incident form and the Quality non-conformance form — not only by the Assets Screen (see this section's opening). |
| `GET /api/maintenance/units-of-measure` | The one catalogue every unit picker draws from, read by Quality as well as Maintenance; it is registered in both `meter-routes.js` and `inventory-routes.js`. |
| `GET /api/maintenance/parts` | The parts catalogue the Work order and Stock movement forms pick from; the Parts Screen is one reader of it. |
| `GET /api/maintenance/sites/:siteId/stores`, `/stores/:storeId`, `/stores/:storeId/stock`, `/stores/:storeId/movements` | "What is on the shelf" is what a supervisor plans around, and the Request and Stock movement forms pick from it: Org Unit scope decides where an Account may act, not what it may know (ADR-0009). |
| `GET /api/maintenance/job-plans`, `/job-plans/:id` | The plan feeds pickers every role may need; no `MTN_JOB_PLANS_DISPLAY` code exists to ask, and inventing one for a read would refuse the pickers. |
| `GET /api/safety/injury-types` | Whoever classifies an injury needs the list as a set of choices (ADR-0023), and it names nobody — ADR-0037's restriction is about three fields on an *incident*. |
| `GET /api/safety/body-parts` | The same set of choices, for the body part an injury names. |

One address the card behind this section expected here is not: the job-role
lookup asks `PPL_JOB_ROLES_DISPLAY`, and the seed gives that code
to `ROLE_STANDARD` — the default group every Account holds — so the read is open
to every Account in effect, reached by a code nobody can lose by accident. That
is the same answer this rule gives, arrived at from the other end, and it is
left as the code says rather than moved into this table.

The four Production reads that stood here as outstanding work have settled the
other way, and are named so the table above is not read as having absorbed them:
`GET /api/production/handovers/:id`, `/handovers/:id/versions`,
`/sections/:orgUnitId/assets` and `/sections/:orgUnitId/handovers` now ask
`PRD_HANDOVER_DISPLAY`. They are one Screen's own reads — the Section's Shift
handover and the Assets it lists — not reference data several Screens read, so
this section's rule gives them a code rather than a place in the table. The code
is seeded on every role, so nothing changes for a caller today; what changed is
that an administrator can now take the Production handover off a role. The same
slice put the Module's eleven writes behind `PRD_HANDOVER_WRITE` and its one
acknowledgement behind `PRD_HANDOVER_ACKNOWLEDGE`.

#### Reads that carry no code and are not settled by this section

Named here so the table above is never read as approval of them. Neither group
is shared reference data; both are retrofit work with a card of their own.

| Route | What is outstanding |
| --- | --- |
| `GET /api/people/accounts`, `/accounts/pending` | These ask the legacy `requireAdmin` rather than `ADM_ACCOUNTS_DISPLAY`. The answer is the same today — the code is seeded on administrators only — so this is a rename waiting for its slice, not a shared read. |

#### Reads no code could name

| Route | Why no code applies |
| --- | --- |
| `GET /api/people/me` | The caller's own identity and effective codes; `authenticate` alone is the whole question. |
| `GET /api/auth/mode` | Which sign-in doors this deployment offers, asked before a session exists. |
| `GET /api/maintenance/floor/training/to-confirm`, `/floor/signature`, `/floor/work-orders`, `GET /api/quality/floor/products`, `/floor/defect-codes` | The shared floor device's door is `requireFloorDevice` plus a technician identification (ADR-0016): a device holds no Account, so no code can name it. |

## Consequences

- **A new Screen needs one line in `destinationPermissions` and one code in the
  catalogue.** Its absence is visible as an ungated door rather than a build
  error, which is why the two are reviewed together.
- **A route that gains or loses a code is a documentation change too.** §7's
  register is compared exactly by `test/shared-reference-reads.test.js`, so a
  new ungated read fails the suite until someone writes down why it is shared,
  and a listed route that gains a code fails it until the entry is removed.
  That is the whole point of writing the rule down: the list is short enough to
  read and enforced often enough to stay true.
- **Enforcement today is the roles surface.** `GET`/`POST`/`PUT` on
  `/roles`, `/permissions` and `/accounts/:id/roles` are gated with
  `requirePermission` (`ADM_ROLES_DISPLAY`, `ADM_ROLES_CHANGE`), which answers
  exactly what `requireAdmin` answered because the seed gives both codes to
  administrators only. Retrofitting `requirePermission` onto the other
  forty-odd routes is a follow-on card: each one needs its write's own code
  chosen against the ADR that governs it, and doing that blind here would be
  inventing authorization policy.
- **Delegated role administration is deliberately not offered.** An Account
  holding `ADM_ROLES_CHANGE` can edit the set of a role it holds, which is
  privilege escalation. SAP's answer is the separate `S_USER_AUTH`/`S_USER_GRP`
  pair guarding user and role maintenance; that pair is not built here, so the
  seed keeps both codes on `ROLE_ADMIN` alone.
- **A role edit is not user-scoped.** Two administrators editing the same role
  is last-write-wins on the whole set, which is what "replace, not patch" means
  and is stated in `roles.js`'s header.

## Alternatives rejected

- **An array of codes on `app_users`.** No group to edit, so "everyone in the
  store room gets this" becomes N row updates and there is no single place to
  see what a role means.
- **Permissions keyed on the Screen and derived from the route.** A route is
  where a thing is served, not what it permits: several Screens read one
  endpoint and one Screen writes through four.
- **Renaming `app_users.role` to "role" and letting roles be rows.** The
  account role is what the Approval queue sets at admission and what the
  Accounts Screen shows; making it a foreign key would change a shipped
  workflow in the same release that introduces the model. `legacy_role` reads
  the two together instead, and a later ADR can retire the column when the
  Approval queue offers groups.
