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
 * Exactly seven exports, each justified below against the sibling ticket
 * that needs it:
 *
 *   - router — mounted by src/index.js, which lives outside `modules/` and so
 *     is not a cross-Module caller the boundary checker even looks at; this
 *     is not really a clause-1/2/3 export at all, just the one every Module
 *     needs to be reachable over HTTP.
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
 *     issue #8 already settled inside People.
 *   - findOrgUnit — #56 only: the client picks `orgUnitId` in the request
 *     body when placing an Asset, so Maintenance must resolve it before it
 *     can even ask canAct about scope (existence before scope — the same
 *     ordering ADR-0008/issue #8 already settled inside People) and 404 a
 *     bad one itself, in its own wording. #57 needs no resolution at all —
 *     it reads the Org Unit id off the Asset row by trigger, already proven
 *     to exist.
 *   - findEmployee — #62: validate the assignee named on a work order
 *     actually exists, and read `isActive` off the result so a departed
 *     Employee is never offered as an assignee, without reaching past this
 *     Module's boundary to query `employees` directly.
 *   - OUTSIDE_GRANTED_ORG_UNITS — the exact 403 body every scope refusal
 *     already shares inside People (authorization.js, plant-routes.js); the
 *     one deliberate exception to "domain, not utility" (ADR-0006): it reads
 *     like a utility string but it is the canonical wording of the refusal
 *     People's own grant model produces, and a caller getting different
 *     sentences for the same refusal depending on which Module answered
 *     would itself be the real inconsistency.
 *
 * Deliberately NOT exported, and why: isAdmin, canSeeSite, requireAdmin,
 * requireOrgUnitScope, requireSiteScope, grantedEntryPointIds,
 * orgUnitScopeFor, ROLES (all authorization.js) — Maintenance's reads are
 * Site-wide regardless of Grants (#55's rule, ADR-0009's own reasoning
 * extended to the second Module), so nothing in the chain needs
 * canSeeSite/requireSiteScope/grantedEntryPointIds/orgUnitScopeFor at all;
 * no Maintenance route is path-param-keyed on an Org Unit (see the canAct
 * bullet above), so requireOrgUnitScope has no caller; canAct already
 * short-circuits role `admin` internally, so requireAdmin/isAdmin have none
 * either, and ROLES is an input-validation concern local to People's own
 * Approval flow. Also not exported: every write in plant.js, directory.js,
 * service.js, skills.js and job-roles.js (clause 1 — a second Module never
 * writes People's own tables), and errors.js's parseId/httpError/notFound/
 * handleError/escapeLikePattern (clause 3 — Maintenance gets its own small
 * modules/maintenance/errors.js rather than importing People's).
 *
 * The most likely next addition is findSite, if #56 decides an unknown
 * siteId in the request body must 404 rather than silently return an empty
 * list — this rule already licenses that as a one-line addition mirroring
 * findOrgUnit/findEmployee, not a new design decision.
 */

const express = require('express');
const accountRoutes = require('./routes');
const plantRoutes = require('./plant-routes');
const directoryRoutes = require('./directory-routes');
const jobRoleRoutes = require('./job-role-routes');
const skillRoutes = require('./skill-routes');
const { authenticate, requireActive } = require('./middleware');
const { canAct } = require('./authorization');
const { findOrgUnit } = require('./plant');
const { findEmployee } = require('./directory');
const { OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();
router.use(accountRoutes);
router.use(plantRoutes);
router.use(directoryRoutes);
router.use(jobRoleRoutes);
router.use(skillRoutes);

module.exports = {
  router,
  authenticate,
  requireActive,
  canAct,
  findOrgUnit,
  findEmployee,
  OUTSIDE_GRANTED_ORG_UNITS
};
