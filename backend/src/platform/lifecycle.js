/*
 * Whether this process is on its way out.
 *
 * Kept apart from health because it is not health's business: health answers
 * questions about the database, and this answers one about the process. They
 * were briefly the same file, which meant the shutdown path reached into the
 * health module to set a flag it did not own.
 *
 * Readiness consults this before it consults the database, so the proxy can
 * stop routing here while in-flight requests finish.
 */

let shuttingDown = false;

function beginShutdown() {
  shuttingDown = true;
}

function isShuttingDown() {
  return shuttingDown;
}

module.exports = { beginShutdown, isShuttingDown };
