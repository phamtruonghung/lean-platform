/*
 * The People Module's entry point (ADR-0006). Everything another Module or
 * `src/index.js` needs from People comes through here — `router` to mount,
 * `authenticate`/`requireActive` for a future Module's own protected routes —
 * never through `./service` or `./middleware` directly.
 */

const router = require('./routes');
const { authenticate, requireActive } = require('./middleware');

module.exports = { router, authenticate, requireActive };
