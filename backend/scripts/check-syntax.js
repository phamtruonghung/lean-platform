#!/usr/bin/env node
/*
 * Parses every source and test file, so a syntax error is caught by `npm run
 * lint` rather than at the moment a route is first exercised. The backend
 * carries no development dependencies, matching its predecessors, so this uses
 * Node's own parser rather than a linter.
 *
 * It also parses the repository-root dev/ directory, whose run-once operator
 * scripts (the plant seed, the password script) no other CI step touches. They
 * are checked here, beside the backend's own files, so there is one list of
 * what gets parsed rather than two that can drift. dev/ must exist: a wrong
 * path would otherwise list nothing and pass.
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { listJsFiles } = require('./lib/files');

const root = path.join(__dirname, '..');
const devDir = path.join(root, '..', 'dev');
if (!fs.existsSync(devDir)) throw new Error(`syntax: ${devDir} not found`);

const files = [
  ...['src', 'test', 'scripts'].flatMap((dir) => listJsFiles(path.join(root, dir))),
  ...listJsFiles(devDir, ['.js', '.mjs']),
];

for (const file of files) {
  execFileSync(process.execPath, ['--check', file]);
}

console.log(`syntax: checked ${files.length} files`);
