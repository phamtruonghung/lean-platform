/*
 * Walking the source tree. Shared by the checks that `npm run lint` runs, which
 * both need every .js file under a directory and were briefly carrying their
 * own identical copy of this.
 */

const fs = require('node:fs');
const path = require('node:path');

function listJsFiles(dir) {
  if (!fs.existsSync(dir)) return [];

  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return listJsFiles(full);
    return entry.isFile() && full.endsWith('.js') ? [full] : [];
  });
}

module.exports = { listJsFiles };
