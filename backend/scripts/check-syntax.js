#!/usr/bin/env node
/*
 * Parses every source and test file, so a syntax error is caught by `npm run
 * lint` rather than at the moment a route is first exercised. The backend
 * carries no development dependencies, matching its predecessors, so this uses
 * Node's own parser rather than a linter.
 */

const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { listJsFiles } = require('./lib/files');

const root = path.join(__dirname, '..');
const files = ['src', 'test', 'scripts'].flatMap((dir) => listJsFiles(path.join(root, dir)));

for (const file of files) {
  execFileSync(process.execPath, ['--check', file]);
}

console.log(`syntax: checked ${files.length} files`);
