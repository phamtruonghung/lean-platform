/*
 * The People Module's entry point (ADR-0006). Everything another Module or
 * `src/index.js` needs from People comes through here — never through
 * `./service`, `./plant`, `./middleware`, `./directory`, `./authorization`,
 * `./job-roles`, `./errors` or `./skills` directly.
 *
 * `router` combines five route files under the one `/api/people` mount:
 * routes.js (Accounts, issue #6), plant-routes.js (Sites and the Org Unit
 * tree, issue #7), directory-routes.js (the Employee directory, issue #9,
 * plus Org Unit assignments, issue #10), job-role-routes.js (the job role
 * catalogue, issue #10), and skill-routes.js (the skills matrix — the skill
 * catalogue, an Employee holding a skill, and skill coverage, issue #11).
 *
 * `floorRouter` is a second router rather than a sixth file inside `router`,
 * and that is issue #201's one deliberate oddity: floor-routes.js owns the
 * shared floor device's HTTP surface (ADR-0016), which this Module took over
 * from Maintenance, but its ADDRESS stayed under `/api/maintenance` because
 * that is what deployed devices are pointed at and the frontend is not part
 * of the move. `src/index.js` mounts it there — see that file's own comment
 * and floor-routes.js's header. Folding it into `router` instead would have
 * moved every floor device's URL to `/api/people/...`, which is exactly the
 * change this prefactor exists to avoid.
 *
 * All five belong to this Module per CONTEXT.md — see plant.js's own header
 * for why Sites/Org Units live here rather than in a Module of their own,
 * ADR-0009 for why the Employee directory is readable platform-wide rather
 * than Org-Unit-scoped the way Sites and Org Units are, and ADR-0010 for why
 * Org Unit assignments (kept in directory-routes.js, not a separate file —
 * see that file's own header) are scoped differently again from the rest of
 * the directory's write surface, and why ADR-0010's own Consequences section
 * pre-decides that an Employee holding a skill (skill-routes.js's PUT
 * /employees/:id/skills/:skillId) is administrator-only rather than
 * Org-Unit-scoped the same way.
 *
 * Issue #59 widens this beyond `router` and the two auth middlewares, since
 * Maintenance is about to become the second Module with routes of its own to
 * guard — see ADR-0006's own "What a Module's entry point may expose"
 * section for the rule this export list follows: questions, not commands
 * (no export here writes a People record on a caller's behalf); values, not
 * control flow (a lookup returns null for "no such row", never a throw
 * carrying an HTTP status into a caller that does not own People's error
 * funnel); domain, not utility (no `parseId`/`httpError`/`notFound`/
 * `handleError` from errors.js, and no `escapeLikePattern` from sql.js,
 * crosses this boundary — People is not a library).
 *
 * `authenticate`/`requireActive` are the documented exception to the first
 * two clauses, and the ADR says so rather than pretending otherwise: they are
 * control flow, and `authenticate` writes — an identity signing in for the
 * first time gets its Account row created here (issue #6), so a first-ever
 * sign-in landing on a Maintenance route writes People's `app_users` through
 * another Module's request path. That is allowed because there is one
 * identity provider and one Account per person Platform-wide (ADR-0002): a
 * second Module cannot answer "is this caller signed in and admitted"
 * without re-implementing Accounts, which is the data seam this whole ADR
 * refuses. The rule stays narrow — a Module may export middleware that
 * establishes the caller's identity, and only that.
 *
 * Exactly fifteen exports, each justified below against the sibling ticket
 * that needs it:
 *
 *   - router — mounted by src/index.js, which lives outside `modules/` and so
 *     is not a cross-Module caller the boundary checker even looks at; this
 *     is not really a clause-1/2/3 export at all, just the one every Module
 *     needs to be reachable over HTTP.
 *   - floorRouter — the same special case as `router`, for the surface this
 *     Module took over in #201: a router is mounted, never called, so none of
 *     the three clauses evaluate it. It is kept apart from `router` only so
 *     that src/index.js can mount it at the frozen `/api/maintenance`
 *     prefix; see the header above.
 *   - authenticate, requireActive — every Maintenance route in #56, #57,
 *     #61, #62, #63 sits behind these two, the same as every People route
 *     does today; a second Module guarding its own routes needs the exact
 *     same "is there a session" / "is that Account approved and active"
 *     checks, not a reimplementation of them.
 *   - canAct — every write in that chain calls this with `{ write: true }`
 *     against the Org Unit the Asset in question sits at, the same
 *     read/write grant check plant-routes.js and directory-routes.js already
 *     gate their own writes with (issue #8). Re-exporting the function
 *     rather than a `requireOrgUnitScope`-shaped middleware is deliberate —
 *     no Maintenance route is path-param-keyed on an Org Unit id the way
 *     People's own `/org-units/:id` routes are (an Asset's Org Unit is read
 *     off the Asset row, not the URL), so there is no `:id` for a ready-made
 *     middleware to parse in the first place; `canAct` is the reusable part.
 *     Two sharp edges a caller outside People must know about, since People's
 *     own call sites have always known them by convention: `write` defaults
 *     to FALSE, so a write handler that forgets `{ write: true }` is
 *     authorised by any read grant and fails open with no error anywhere;
 *     and the `admin` short-circuit returns true before the null-Org-Unit
 *     guard, so `canAct({ account: anAdmin, orgUnitId: null, write: true })`
 *     is true — resolve the Org Unit with findOrgUnit and handle null BEFORE
 *     asking about scope, which is the existence-before-scope ordering
 *     issue #8 already settled inside People. Issue #204 adds a third option
 *     beside `write` — `quality: true`, ADR-0035 — which asks the same
 *     grant-reaching-downward question restricted to grants carrying Quality
 *     authority (the flag migration 1799800000000 puts on a Grant). It is
 *     for a different kind of decision, not a stricter write: the Quality
 *     Module's later slices ask it before releasing nonconforming product or
 *     opening an investigation (a Concession, reopening a Non-conformance,
 *     opening or verifying a CAPA), and it is deliberately independent of
 *     `write` in both directions because ADR-0035 rejects both "any write
 *     grant" and "Quality authority implies write". It carries the same two
 *     sharp edges as `write` — it defaults to FALSE, and an administrator
 *     answers true with no Org Unit at all — so a caller outside People
 *     resolves the Org Unit first, exactly as it already does for a write.
 *   - canSeeSite — #198: a Concern is a report rather than a decision, and
 *     CONTEXT.md's Concern entry says anyone on the floor may raise one where
 *     they found it "whether or not they hold a Grant reaching that Org Unit".
 *     `modules/actions` therefore has to be able to ask the weaker of People's
 *     two questions about a place — not `canAct` at one Org Unit, but "can
 *     this Account see this Site at all", which is exactly the predicate
 *     GET /sites already filters by (any Grant, read or write, on any Org Unit
 *     within the Site, at any depth — authorization.js's canSeeSite). It
 *     crosses this boundary for the same reason `canAct` above does: which
 *     Org Units a Grant reaches is People's own judgment about People's own
 *     rows, and a second Module re-spelling that query is the data seam
 *     ADR-0006 refuses. Every other kind of Action — and everything that
 *     changes one after it is raised — still goes through `canAct` at its own
 *     Org Unit, unchanged by #198.
 *   - safetyAuthorityOrgUnitIds — #224, ADR-0037: which Org Units in one Site
 *     a Grant carrying Safety authority reaches. It crosses this boundary for
 *     the same reason canAct and canSeeSite do — which Org Units a Grant
 *     reaches is People's own judgment about People's own rows — and it is a
 *     question returning a value, so it is clauses 1 and 2 exactly. It is here
 *     rather than folded into `canAct` because it answers a **different**
 *     question from either of canAct's existing options, in two ways that both
 *     matter. It is asked of a whole Site at once, because the Safety
 *     Module's register serialises up to 200 incidents spanning many Org Units
 *     and a per-row canAct would be a query per row; and it carries **no
 *     administrator short-circuit**, because ADR-0037 restricts reading an
 *     injured person's diagnosis to a holder of the Grant and issue #224
 *     names an administrator without one as a caller the fields are withheld
 *     from. canAct({ safety: true }) stays exactly what it is and is still
 *     what Safety's own *writes* ask — see authorization.js's own comment
 *     above the function for why the two are not in tension.
 *   - findOrgUnit — #56 only: the client picks `orgUnitId` in the request
 *     body when placing an Asset, so Maintenance must resolve it before it
 *     can even ask canAct about scope (existence before scope — the same
 *     ordering ADR-0008/issue #8 already settled inside People) and 404 a
 *     bad one itself, in its own wording. #57 needs no resolution at all —
 *     it reads the Org Unit id off the Asset row by trigger, already proven
 *     to exist.
 *   - findSite — #56: GET /sites/:siteId/assets names a Site in its own path
 *     and must 404 an unknown one in Maintenance's own wording, exactly the
 *     "existence before scope" shape findOrgUnit serves above, one level up
 *     the tree. plant.js splits getSite (throws) into findSite (null) and
 *     getSite (still throws, still People's internal 404) the same way it
 *     already split getOrgUnit/findOrgUnit — see that file's own header.
 *   - findEmployee — #62: validate the assignee named on a work order
 *     actually exists, and read `isActive` off the result so a departed
 *     Employee is never offered as an assignee, without reaching past this
 *     Module's boundary to query `employees` directly.
 *   - findDeviceByCredential, findValidIdentification, deviceReachesOrgUnit,
 *     findDeviceContext — #201: the shared floor device and the
 *     identification presented on it moved into this Module, and Maintenance
 *     keeps the two doors that consult them. `findDeviceByCredential` is
 *     asked by a floor write and by Maintenance's own floor read ("is this a
 *     device, and is it switched on", 401 when not);
 *     `findValidIdentification` by a floor write only ("who does this device
 *     say is standing at it" — null when the token is missing, expired or
 *     from another device); `deviceReachesOrgUnit` by a floor write's scope
 *     check, since the tree the device's reach is measured in is `org_units`,
 *     this Module's own record; and `findDeviceContext` by Maintenance's
 *     floor read, which needs the Site and Org Unit path the device is
 *     registered at to bound its own list of Work orders. All four are
 *     questions returning a value — null for "no such row" — over records
 *     this Module owns, which is clauses 1 and 2 exactly. Deliberately not
 *     exported with them: createFloorDevice, setEmployeePin, verifyPin,
 *     findCredentialForEmployeeNo and createIdentification, this Module's own
 *     writes and the secrets they handle (clause 1) — floor-routes.js reaches
 *     them directly, as a People route reaches any People service.
 *   - OUTSIDE_GRANTED_ORG_UNITS — the exact 403 body every scope refusal
 *     already shares inside People (authorization.js, plant-routes.js); the
 *     one deliberate exception to "domain, not utility" (ADR-0006): it reads
 *     like a utility string but it is the canonical wording of the refusal
 *     People's own grant model produces, and a caller getting different
 *     sentences for the same refusal depending on which Module answered
 *     would itself be the real inconsistency.
 *
 * Deliberately NOT exported, and why: isAdmin, requireAdmin,
 * requireOrgUnitScope, requireSiteScope, grantedEntryPointIds,
 * orgUnitScopeFor, ROLES (all authorization.js) — `canSeeSite` used to be on
 * this list and comes off it as of #198 (see its own bullet above: raising a
 * Concern is a Site-level question, so it now has a caller outside People).
 * Maintenance's reads are Site-wide regardless of Grants (#55's rule,
 * ADR-0009's own reasoning extended to the second Module), so nothing in the
 * maintenance chain needs requireSiteScope/grantedEntryPointIds/
 * orgUnitScopeFor at all;
 * no Maintenance route is path-param-keyed on an Org Unit (see the canAct
 * bullet above), so requireOrgUnitScope has no caller; canAct already
 * short-circuits role `admin` internally, so requireAdmin/isAdmin have none
 * either, and ROLES is an input-validation concern local to People's own
 * Approval flow. Also not exported: every write in plant.js, directory.js,
 * service.js, skills.js, job-roles.js and floor-devices.js (clause 1 — a
 * second Module never writes People's own tables), and errors.js's
 * parseId/httpError/notFound/handleError/escapeLikePattern (clause 3 —
 * Maintenance gets its own small modules/maintenance/errors.js rather than
 * importing People's).
 */

const express = require('express');
const accountRoutes = require('./routes');
const plantRoutes = require('./plant-routes');
const directoryRoutes = require('./directory-routes');
const jobRoleRoutes = require('./job-role-routes');
const skillRoutes = require('./skill-routes');
const floorRoutes = require('./floor-routes');
const { authenticate, requireActive } = require('./middleware');
const { canAct, canSeeSite, safetyAuthorityOrgUnitIds } = require('./authorization');
const { findOrgUnit, findSite } = require('./plant');
const { findEmployee } = require('./directory');
const {
  findDeviceByCredential,
  findDeviceContext,
  findValidIdentification,
  deviceReachesOrgUnit
} = require('./floor-devices');
const { OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();
router.use(accountRoutes);
router.use(plantRoutes);
router.use(directoryRoutes);
router.use(jobRoleRoutes);
router.use(skillRoutes);

module.exports = {
  router,
  // Mounted at `/api/maintenance` by src/index.js, not at `/api/people` — see
  // the header above. It is a router, not a route file added to `router`.
  floorRouter: floorRoutes,
  authenticate,
  requireActive,
  canAct,
  canSeeSite,
  safetyAuthorityOrgUnitIds,
  findOrgUnit,
  findSite,
  findEmployee,
  findDeviceByCredential,
  findDeviceContext,
  findValidIdentification,
  deviceReachesOrgUnit,
  OUTSIDE_GRANTED_ORG_UNITS
};
