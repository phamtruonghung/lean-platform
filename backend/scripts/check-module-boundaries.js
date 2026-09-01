#!/usr/bin/env node
/*
 * Enforces the Module boundary from ADR-0006.
 *
 * A Module is a code seam, not a data seam: People, Maintenance and the Tier
 * Board share one schema and one process. What holds them apart is a single
 * rule — a Module never reaches into another Module's internals, it calls that
 * Module's service through its entry point. Two consequences follow, and both
 * are checked here:
 *
 *   1. From inside a Module, a require that lands in a different Module must
 *      land on that Module's entry point and no deeper.
 *   2. Shared platform code must not require a Module at all. The foundation
 *      cannot depend on what is built on it.
 *
 * Deliberately a plain script rather than an ESLint plugin: the backend carries
 * no development dependencies, matching its predecessors, and this rule is
 * small enough that a dependency would cost more than it saves.
 */

const fs = require('node:fs');
const path = require('node:path');

const MODULES_DIR = 'modules';
const PLATFORM_DIR = 'platform';

// Matches CommonJS requires and static ESM imports of a *relative* specifier.
// Only relative specifiers can cross an internal boundary; a bare specifier is
// a package from node_modules and is never this rule's business.
const SPECIFIER_PATTERN =
  /(?:require\(\s*['"](\.[^'"]*)['"]\s*\)|from\s*['"](\.[^'"]*)['"]|import\(\s*['"](\.[^'"]*)['"]\s*\))/g;

function listJsFiles(dir) {
  if (!fs.existsSync(dir)) return [];

  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return listJsFiles(full);
    return entry.isFile() && full.endsWith('.js') ? [full] : [];
  });
}

// Which Module a file belongs to, or null if it is not inside one. Compared on
// path segments rather than string prefixes so that a directory named
// `modules-legacy` is never mistaken for `modules`.
function moduleOf(root, file) {
  const segments = path.relative(root, file).split(path.sep);
  return segments[0] === MODULES_DIR && segments.length > 1 ? segments[1] : null;
}

function isPlatformFile(root, file) {
  return path.relative(root, file).split(path.sep)[0] === PLATFORM_DIR;
}

// The entry point of a Module: `modules/<name>` itself, or its index.js.
// Anything deeper is an internal.
function isEntryPoint(root, resolved, moduleName) {
  const base = path.join(root, MODULES_DIR, moduleName);
  return resolved === base || resolved === path.join(base, 'index.js');
}

function findBoundaryViolations(root) {
  const violations = [];

  for (const file of listJsFiles(root)) {
    const owner = moduleOf(root, file);
    const fromPlatform = isPlatformFile(root, file);

    // Anything outside a Module and outside platform is unclassified — the
    // entry point, for instance — and has nothing to answer for here.
    if (!owner && !fromPlatform) continue;

    const source = fs.readFileSync(file, 'utf8');

    for (const match of source.matchAll(SPECIFIER_PATTERN)) {
      const specifier = match[1] ?? match[2] ?? match[3];
      const resolved = path.resolve(path.dirname(file), specifier);
      const target = moduleOf(root, resolved);

      if (!target) continue;

      if (fromPlatform) {
        violations.push({
          file,
          specifier,
          reason: 'shared platform code must not depend on a Module'
        });
        continue;
      }

      // Its own files are its own business.
      if (target === owner) continue;

      if (!isEntryPoint(root, resolved, target)) {
        violations.push({
          file,
          specifier,
          reason: `reaches past the ${target} Module entry point`
        });
      }
    }
  }

  return violations;
}

function main() {
  const root = path.join(__dirname, '..', 'src');
  const violations = findBoundaryViolations(root);

  if (violations.length === 0) {
    console.log('module boundaries: ok');
    return;
  }

  console.error(`module boundaries: ${violations.length} violation(s)\n`);
  for (const violation of violations) {
    console.error(`  ${path.relative(root, violation.file)}`);
    console.error(`    imports '${violation.specifier}' — ${violation.reason}\n`);
  }
  console.error("See docs/adr/0006-modules-are-code-seams-not-data-seams.md");
  process.exitCode = 1;
}

if (require.main === module) main();

module.exports = { findBoundaryViolations };
