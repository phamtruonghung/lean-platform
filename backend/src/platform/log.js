/*
 * One JSON object per line, so output is greppable and machine-readable without
 * pulling in a logging framework. The Platform runs as a container behind a
 * reverse proxy; whatever collects its stdout wants structure, not prose.
 */

function log(level, msg, extra = {}) {
  console.log(JSON.stringify({ level, msg, ts: new Date().toISOString(), ...extra }));
}

module.exports = { log };
