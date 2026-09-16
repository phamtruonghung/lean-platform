/*
 * The Quality Module's entry point (ADR-0006) — the fourth Module in this
 * backend, after People, Maintenance and Actions, and the one issue #203
 * creates.
 *
 * One export, and it is here because something outside this Module mounts it.
 * `router` is this Module's own routes — the Product catalogue and the Defect
 * code tree as they stand today — mounted by src/index.js under
 * `/api/quality`, a prefix of this Module's own beside `/api/people`,
 * `/api/maintenance` and `/api/actions`. src/index.js lives outside
 * `modules/` and is not a cross-Module caller the boundary checker looks at,
 * so like every Module's `router` it is a special case of none of ADR-0006's
 * three clauses: it is how the Module becomes reachable over HTTP at all.
 *
 * Nothing else is exported, and each absence is a decision rather than an
 * omission:
 *
 *   - No lookup about a Product or a Defect code is offered to another Module.
 *     Nothing outside Quality asks one today: the catalogue is read by this
 *     Module's own routes and by the client. A sibling Module that needs to
 *     resolve a Product — a Non-conformance slice naming one — adds the
 *     question here at that point, which is what ADR-0006's "What a Module's
 *     entry point may expose" section anticipates and what
 *     people-entry-point.test.js's own header describes as cheap on the way in
 *     and expensive on the way out.
 *   - No KPI registry contribution yet. The tier board's registry (issue #202)
 *     is composed in src/index.js from whatever each Module offers, and this
 *     Module records no measurement anyone could put on that board: it holds
 *     two catalogues, and a catalogue is not a number. The Quality pillar's
 *     own KPIs are computed from `quality_issues`, `nonconformances` and the
 *     CAPA tables, which the baseline seeds and no slice has started writing —
 *     so they answer `no_data` on the board exactly as they do today, and
 *     contributing a registry entry here would be inventing a number rather
 *     than publishing one. The contribution arrives with the slice that starts
 *     recording that work.
 *   - No error plumbing and no SQL helpers. errors.js is this Module's own
 *     copy (ADR-0006's third clause, "domain, not utility" — see its header),
 *     and products.js/defect-codes.js each keep their own private helpers
 *     rather than sharing them through this file.
 *
 * What this Module requires from outside itself is People's entry point and
 * nothing else (issue #203's own acceptance criterion, and what
 * `npm run lint`'s boundary checker enforces): product-routes.js and
 * defect-code-routes.js ask `people.authenticate` and `people.requireActive`
 * and carry their own copy of the administrator check, since People
 * deliberately does not export `requireAdmin`. `modules/people/authorization.js`
 * already answers the Quality question this Module's later slices need
 * (`canAct({ quality: true })`, issue #204, ADR-0035) — that is People's
 * export, reached through People's entry point, not something re-exported
 * here.
 */

const express = require('express');
const productRoutes = require('./product-routes');
const defectCodeRoutes = require('./defect-code-routes');

const router = express.Router();
router.use(productRoutes);
router.use(defectCodeRoutes);

module.exports = {
  router
};
