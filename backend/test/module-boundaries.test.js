/*
 * The rule that keeps Modules from becoming one tangle.
 *
 * ADR-0006 makes a Module a code seam rather than a data seam: People,
 * Maintenance and the Tier Board share one schema and one process, and the only
 * thing holding them apart is that a Module never reaches into another Module's
 * internals — it calls that Module's service. A convention nothing checks is a
 * convention that decays, so this is checked.
 *
 * The checker is exercised against fixtures rather than against the real source
 * tree. Pointing it at src would make these tests pass for the wrong reason on
 * the day src has no Modules in it yet, and prove nothing about the rule.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { findBoundaryViolations } = require('../scripts/check-module-boundaries');

// Builds a throwaway source tree. Keys are paths relative to the tree root,
// values are file contents.
function buildTree(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lp-boundaries-'));
  for (const [relative, contents] of Object.entries(files)) {
    const full = path.join(root, relative);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, contents);
  }
  return root;
}

test('a Module calling another Module through its entry point is allowed', () => {
  const root = buildTree({
    'modules/people/index.js': "module.exports = require('./service');",
    'modules/people/service.js': 'module.exports = {};',
    'modules/maintenance/service.js': "const people = require('../people');\n"
  });

  assert.deepStrictEqual(findBoundaryViolations(root), []);
});

test('a Module reaching into another Module\'s internals is a violation', () => {
  const root = buildTree({
    'modules/people/index.js': "module.exports = require('./service');",
    'modules/people/service.js': 'module.exports = {};',
    'modules/maintenance/service.js': "const svc = require('../people/service');\n"
  });

  const violations = findBoundaryViolations(root);
  assert.strictEqual(violations.length, 1);
  assert.match(violations[0].file, /maintenance[/\\]service\.js$/);
  assert.strictEqual(violations[0].specifier, '../people/service');
  assert.strictEqual(violations[0].reason, 'reaches past the people Module entry point');
});

test('a Module importing its own files freely is allowed', () => {
  const root = buildTree({
    'modules/people/index.js': "const s = require('./service');\nconst q = require('./queries/list');",
    'modules/people/service.js': 'module.exports = {};',
    'modules/people/queries/list.js': 'module.exports = {};'
  });

  assert.deepStrictEqual(findBoundaryViolations(root), []);
});

test('a Module importing shared platform code is allowed', () => {
  const root = buildTree({
    'platform/db.js': 'module.exports = {};',
    'modules/people/service.js': "const { getPool } = require('../../platform/db');\n"
  });

  assert.deepStrictEqual(findBoundaryViolations(root), []);
});

test('shared platform code importing a Module is a violation', () => {
  const root = buildTree({
    'platform/db.js': "const people = require('../modules/people');\n",
    'modules/people/index.js': 'module.exports = {};'
  });

  const violations = findBoundaryViolations(root);
  assert.strictEqual(violations.length, 1);
  assert.match(violations[0].file, /platform[/\\]db\.js$/);
  // The foundation cannot depend on what is built on it. Allowing this would
  // make the dependency circular and the Modules impossible to reason about
  // separately, which is the whole point of having them.
  assert.strictEqual(violations[0].reason, 'shared platform code must not depend on a Module');
});

test('a tree with no Modules yet has nothing to report', () => {
  const root = buildTree({ 'platform/db.js': 'module.exports = {};' });
  assert.deepStrictEqual(findBoundaryViolations(root), []);
});

test('the real source tree obeys the rule', () => {
  const violations = findBoundaryViolations(path.join(__dirname, '..', 'src'));
  assert.deepStrictEqual(violations, []);
});
