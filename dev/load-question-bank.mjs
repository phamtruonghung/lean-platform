#!/usr/bin/env node
/*
 * Loads the Cutting Machines question bank (500 multiple-choice questions) into
 * the assessment Question bank (`assessment_questions`) of ONE Org Unit, through
 * the app's own module (backend/src/modules/people/assessment-questions.js):
 * the same `parsePaste` the paste screen uses and the same
 * `bulkCreateQuestions` the bulk route calls — one transaction, all or nothing,
 * audit actor set with `withActor`. Nothing here writes SQL against the bank.
 *
 *   # preview (default): reads the database, writes nothing
 *   DATABASE_URL=postgresql://... node dev/load-question-bank.mjs --account-id 2
 *   # load
 *   DATABASE_URL=postgresql://... node dev/load-question-bank.mjs --account-id 2 --write
 *   # no database needed: only write out the paste text the CSV converts to
 *   node dev/load-question-bank.mjs --emit-paste /tmp/bank-paste.txt
 *
 * Options
 *   --account-id <n>        required (except with --emit-paste alone): the
 *                           Account the audit trail names. Must exist, be
 *                           active and approved.
 *   --org-unit-code <code>  default SC-CUTTING-MTU. Must name exactly one
 *                           active Org Unit.
 *   --csv <file>            default: docs/Question bank Cutting Machines - 500
 *                           MCQ (import).csv in the repo, or, in the container,
 *                           the same file name beside this script.
 *   --backend-dir <dir>     where src/ lives. Default: auto-detected, either
 *                           ../backend (repo) or .. (the image, where src/ sits
 *                           directly under /app).
 *   --emit-paste <file>     write the generated paste text and, when no
 *                           --account-id is given, stop there.
 *   --dry-run (default) | --write
 *
 * ## Mapping (the source CSV is `;`-delimited, UTF-8 BOM, 16 columns)
 *
 *   Question  -> `Câu hỏi:` line
 *   A..D      -> three options: the key plus two distractors
 *   Answer    -> the key, re-lettered to its new position, marked `*`
 *   Feedback  -> `Giải thích:` line
 *
 * The bank holds exactly three options A/B/C, so one distractor per question is
 * dropped: of the three wrong options the two whose md5(stem + letter) sorts
 * first are kept (a deterministic choice, so a re-run converts identically),
 * and the options stay in their original order.
 *
 * ## What is dropped
 *
 *   - the 4th option (the one distractor above);
 *   - 7 metadata columns: Domain, Subdomain, Bloom, Difficulty, Type,
 *     Criticality, Reference — the bank has no field for them;
 *   - Exam (Đề 1..5): the bank has no paper entity, a paper is a random draw at
 *     attempt start, so the five papers become one pool of 500.
 *   (CorrectAnswer repeats options[Answer] and is only cross-checked.)
 *
 * ## Re-running
 *
 * Each block is fingerprinted by Postgres (the column's own expression, never
 * JavaScript) and looked up among the Org Unit's existing rows:
 *   create     no row has that stem            -> inserted
 *   unchanged  same stem, options, key, explanation
 *   drift      same stem, something else differs -> reported with the paste
 *              line and row id, never overwritten, never blocks the creates
 * Only the `create` set is sent, in one `bulkCreateQuestions` call. A second
 * --write therefore reports created 0 / unchanged 500 / drift 0.
 *
 * ## On production, inside the backend container
 *
 *   docker cp dev/load-question-bank.mjs <backend>:/app/dev/
 *   docker cp "docs/Question bank Cutting Machines - 500 MCQ (import).csv" <backend>:/app/dev/
 *   docker exec <backend> node /app/dev/load-question-bank.mjs --account-id 2
 *   docker exec <backend> node /app/dev/load-question-bank.mjs --account-id 2 --write
 *
 * (create /app/dev first if the image has none: `docker exec <backend> mkdir -p
 * /app/dev`.) The container already has DATABASE_URL. Adds no migration.
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const CSV_NAME = 'Question bank Cutting Machines - 500 MCQ (import).csv';
const COLUMNS = ['Exam', 'Domain', 'Subdomain', 'Bloom', 'Difficulty', 'Type', 'Criticality', 'Question', 'A', 'B', 'C', 'D', 'Answer', 'CorrectAnswer', 'Feedback', 'Reference'];

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const args = { orgUnitCode: 'SC-CUTTING-MTU', write: false };
  const valueOf = (i, name) => {
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) fail(`${name} needs a value`);
    return argv[i + 1];
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--write') args.write = true;
    else if (a === '--dry-run') args.write = false;
    else if (a === '--account-id') args.accountId = valueOf(i++, a);
    else if (a === '--org-unit-code') args.orgUnitCode = valueOf(i++, a);
    else if (a === '--csv') args.csv = valueOf(i++, a);
    else if (a === '--backend-dir') args.backendDir = valueOf(i++, a);
    else if (a === '--emit-paste') args.emitPaste = valueOf(i++, a);
    else fail(`unknown argument ${a}`);
  }
  if (args.accountId !== undefined && !/^[1-9]\d*$/.test(args.accountId)) fail('--account-id must be a positive integer');
  return args;
}

// ---------------------------------------------------------------------------
// The file
// ---------------------------------------------------------------------------

// `;`-delimited with optional double-quoted fields (RFC-4180 style quoting).
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i += 1; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"' && field === '') quoted = true;
    else if (c === ';') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i += 1;
      row.push(field); field = '';
      if (row.some((f) => f !== '')) rows.push(row);
      row = [];
    } else field += c;
  }
  row.push(field);
  if (row.some((f) => f !== '')) rows.push(row);
  return rows;
}

function resolveCsv(explicit) {
  if (explicit) return path.resolve(explicit);
  const candidates = [path.join(here, '..', 'docs', CSV_NAME), path.join(here, CSV_NAME)];
  return candidates.find((p) => existsSync(p)) ?? fail(`No question bank CSV found. Looked at:\n  ${candidates.join('\n  ')}\nPass --csv <file>, or docker cp the CSV next to this script.`);
}

function readSourceRows(csvPath) {
  let text;
  try {
    text = readFileSync(csvPath, 'utf8').replace(/^﻿/, '');
  } catch (error) {
    if (error.code === 'ENOENT') fail(`No CSV at ${csvPath}`);
    throw error;
  }
  const [header, ...lines] = parseCsv(text);
  if (!header || header.join(';') !== COLUMNS.join(';')) fail(`Unexpected CSV header: ${header ? header.join(';') : '(empty)'}`);
  return lines.map((fields, index) => {
    if (fields.length !== COLUMNS.length) fail(`CSV record ${index + 2}: expected ${COLUMNS.length} fields, got ${fields.length}`);
    return Object.fromEntries(COLUMNS.map((name, i) => [name, fields[i].trim()]));
  });
}

// One row -> one three-option paste block (see "Mapping" above).
function toBlock(row, index) {
  const where = `CSV record ${index + 2}`;
  const key = row.Answer;
  if (!['A', 'B', 'C', 'D'].includes(key)) fail(`${where}: Answer "${key}" is not A-D`);
  if (row[key] !== row.CorrectAnswer) fail(`${where}: CorrectAnswer does not match option ${key}`);
  const distractors = ['A', 'B', 'C', 'D']
    .filter((letter) => letter !== key)
    .map((letter) => ({ letter, rank: createHash('md5').update(row.Question + letter, 'utf8').digest('hex') }))
    .sort((a, b) => (a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0))
    .slice(0, 2)
    .map((d) => d.letter);
  const kept = ['A', 'B', 'C', 'D'].filter((letter) => letter === key || distractors.includes(letter));
  const lines = [`Câu hỏi: ${row.Question}`];
  kept.forEach((letter, position) => {
    lines.push(`${letter === key ? '*' : ''}${'ABC'[position]}. ${row[letter]}`);
  });
  lines.push(`Giải thích: ${row.Feedback}`);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// The backend module, from the repo or from the image
// ---------------------------------------------------------------------------

function loadBackend(explicit) {
  const candidates = explicit ? [path.resolve(explicit)] : [path.join(here, '..', 'backend'), path.join(here, '..')];
  const dir = candidates.find((d) => existsSync(path.join(d, 'src', 'modules', 'people', 'assessment-questions.js')));
  if (!dir) fail(`Cannot find the backend (src/modules/people/assessment-questions.js) under:\n  ${candidates.join('\n  ')}\nPass --backend-dir.`);
  const req = createRequire(path.join(dir, 'package.json'));
  return {
    dir,
    bank: req('./src/modules/people/assessment-questions'),
    db: req('./src/platform/db')
  };
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const csvPath = resolveCsv(args.csv);
  const rows = readSourceRows(csvPath);
  const pasteText = `${rows.map(toBlock).join('\n\n')}\n`;
  const { bank, db, dir } = loadBackend(args.backendDir);

  console.log(`${args.write ? 'WRITE' : 'DRY RUN'}. ${rows.length} rows read from ${csvPath}`);
  if (args.emitPaste) {
    writeFileSync(args.emitPaste, pasteText);
    console.log(`paste text (${Buffer.byteLength(pasteText)} bytes) written to ${args.emitPaste}`);
    if (args.accountId === undefined) return;
  }

  const parsed = bank.parsePaste(pasteText);
  if (parsed.error) fail(`The converted paste does not parse: ${parsed.error.message}`);
  const blocks = parsed.questions;
  if (blocks.length !== rows.length) fail(`Parsed ${blocks.length} blocks from ${rows.length} rows`);

  if (args.accountId === undefined) fail('--account-id is required');
  if (!process.env.DATABASE_URL) fail('DATABASE_URL is required.');
  const pool = db.getPool();

  try {
    const { rows: units } = await pool.query(
      `SELECT o.id::text AS id, o.code, o.name, o.is_active, s.code AS site
         FROM org_units o JOIN sites s ON s.id = o.site_id WHERE o.code = $1`,
      [args.orgUnitCode]
    );
    if (units.length === 0) fail(`Org Unit ${args.orgUnitCode} does not exist.`);
    if (units.length > 1) fail(`Org Unit code ${args.orgUnitCode} is ambiguous (${units.map((u) => `${u.site}:${u.id}`).join(', ')}).`);
    const unit = units[0];
    if (!unit.is_active) fail(`Org Unit ${unit.code} (id ${unit.id}) is not active.`);

    const { rows: accounts } = await pool.query(
      'SELECT id::text AS id, email, is_active, approval_status FROM app_users WHERE id = $1',
      [args.accountId]
    );
    if (accounts.length === 0) fail(`Account ${args.accountId} does not exist.`);
    const account = accounts[0];
    if (!account.is_active) fail(`Account ${account.id} (${account.email}) is not active.`);
    if (account.approval_status !== 'approved') fail(`Account ${account.id} (${account.email}) is ${account.approval_status}, not approved.`);

    const count = async () => (await pool.query('SELECT count(*)::int AS n FROM assessment_questions WHERE org_unit_id = $1', [unit.id])).rows[0].n;
    const before = await count();

    // Existing rows with the same stem, matched on the column's own expression.
    const { rows: found } = await pool.query(
      `SELECT u.n::int AS n, q.id::text AS id, q.option_a, q.option_b, q.option_c, q.correct_option, q.explanation
         FROM unnest($2::text[]) WITH ORDINALITY AS u(t, n)
         JOIN assessment_questions q
           ON q.org_unit_id = $1
          AND q.question_text_fingerprint = md5(lower(regexp_replace(btrim(u.t), '\\s+', ' ', 'g')))`,
      [unit.id, blocks.map((b) => b.questionText)]
    );
    const existingByBlock = new Map(found.map((r) => [r.n - 1, r]));

    const toCreate = [];
    const drift = [];
    let unchanged = 0;
    blocks.forEach((block, i) => {
      const row = existingByBlock.get(i);
      if (!row) { toCreate.push(block); return; }
      const same = row.option_a === block.optionA && row.option_b === block.optionB && row.option_c === block.optionC
        && row.correct_option === block.correctOption && (row.explanation ?? null) === (block.explanation ?? null);
      if (same) unchanged += 1;
      else drift.push({ block, row });
    });

    console.log(`Org Unit      ${unit.id} ${unit.code} "${unit.name}" (site ${unit.site})`);
    console.log(`Actor         ${account.id} ${account.email}`);
    console.log(`Backend       ${dir}`);
    console.log(`Blocks parsed ${blocks.length}`);
    console.log(`Bank rows before ${before}`);
    console.log(`create ${toCreate.length} / unchanged ${unchanged} / drift ${drift.length}`);
    for (const { block, row } of drift) {
      console.log(`  drift: paste line ${block.line} matches Question ${row.id} by stem but its options, key or explanation differ; left as is.`);
    }

    if (!args.write) {
      console.log('Dry run: nothing written. Add --write to create the rows.');
      return;
    }
    let created = 0;
    if (toCreate.length > 0) created = (await bank.bulkCreateQuestions(args.accountId, unit.id, toCreate)).length;
    console.log(`created ${created} / unchanged ${unchanged} / drift ${drift.length}`);
    console.log(`Bank rows after ${await count()}`);
  } finally {
    await db.closePool();
  }
}

main().catch((error) => {
  console.error(`\nFAILED: ${error.message}`);
  process.exit(1);
});
