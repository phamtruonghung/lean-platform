#!/usr/bin/env node
/*
 * Loads the Relats Vietnam plant from docs/Employee_Master_Consolidated.csv
 * (issue #272, part of #267): the Site, the Production department with its SC
 * and TX sections and the areas under them, the Job roles the file's Position
 * column names, one Employee per row, one Assignment each, and one approved
 * Account each with the default password, so a named operator can sign in the
 * same minute the script finishes.
 *
 *   DATABASE_URL=postgresql://... node dev/seed-relats-vietnam.mjs [--dry-run]
 *
 * Reads the CSV beside this repo, talks to Postgres directly, needs no
 * network and no running API. It is NOT wired into dev/seed-demo.sql, docker
 * compose or any deploy path: it runs when somebody runs it. It adds no
 * migration and changes no schema.
 *
 * ## What the file does not become
 *
 * "Relats" is the estate's name; this schema has no row for an estate, so it
 * is carried here and in the ticket, not invented as a table. The `Present in`
 * column (which modules a person is in scope for) is deliberately not stored:
 * nothing in the schema models that, and the omission is a decision.
 *
 * ## Mapping
 *
 *   Site        RLVN, Relats Vietnam, Asia/Ho_Chi_Minh, VN
 *   Org Units   Production (department, the Site's root) -> SC, TX (section)
 *               -> one `area` per distinct Area / Process value. `Leader` and
 *               `Shift sup` are not areas: those rows sit at their Section.
 *   Section     41 rows have none; they are filed by their area's own section
 *               (AREA_SECTION). An area missing from that table stops the
 *               run rather than being guessed.
 *   Employee    employee_no = ID; first_name = all words but the last,
 *               last_name = the last word, so the generated display_name is
 *               the file's Name exactly.
 *   Account     <employee_no>@relats.vn, subject local:<employee_no>, approved.
 *   Grant       Operator/Trainee read their own area; Team Leader and Shift
 *               Supervisor write their own section; the Quality Inspector
 *               holds quality authority on the Site's root Org Unit.
 *
 * ## Sixteen people have no Joining Date
 *
 * Their Employee gets `hired_on = NULL`. `employee_assignments.effective_from`
 * is NOT NULL, so their Assignment starts on the date of the run that first
 * creates it ("placed as of the load date, hire date unknown"). On later runs
 * an existing Assignment for such an Employee is never compared on
 * effective_from, so a re-run stays at zero changes on any day.
 *
 * ## The Self-Closing section's machines and shifts (issue #341, part of #332)
 *
 * After the tree, the same run loads what the Production Module's handover
 * form and board read: the Site's shift pattern, the Cutting MTU line's
 * machines as Assets, and the Section's shift calendar.
 *
 *   Shifts      A 06:00, B 14:00, C 22:00, 480 minutes, no break, day_offset 0 -
 *               written ONLY when the Site has no shift definition at all. An
 *               existing pattern is read, reported and never touched.
 *   Assets      the 17 machines of the plant `mtu` database's public.machines,
 *               one per row, code = name = the machine's name, at SC-CUTTING-MTU
 *               (looked up by code). Keyed by code: a re-run inserts nothing and
 *               repairs a drifted name; it never moves or re-activates a machine.
 *   Calendar    generate_shift_instances for the SC section only (not its
 *               areas), from seven days back to sixty ahead.
 *
 * Cutting SC, Raschel, Shaping, Warping and every TX area have NO machine
 * master anywhere: nothing is loaded for them and none is invented. The run
 * says so. `--skip-people` stops after this plant data (tree, shifts, assets,
 * calendar) without loading Job roles, Employees or Accounts.
 *
 * ## Re-running
 *
 * Every table is matched on its natural key (sites.code, (site_id, code) on
 * org_units, job_roles.code, employees.employee_no, app_users.email), so a
 * second run reports created 0 / updated 0. A credential row is inserted only
 * when the Account has none and is never updated, so a re-run cannot reset a
 * password somebody has since changed or move its `updated_at`. No hash is
 * ever printed.
 *
 * `--dry-run` reads the database to diff (or plans against an empty one when
 * DATABASE_URL is absent) and writes nothing: every INSERT and UPDATE is
 * intercepted before it reaches Postgres.
 */

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const backendRequire = createRequire(path.join(here, '..', 'backend', 'package.json'));
const { hashSecret } = backendRequire('./src/platform/secrets');
const pg = backendRequire('pg');

const CSV_PATH = path.join(here, '..', 'docs', 'Employee_Master_Consolidated.csv');
const DRY_RUN = process.argv.includes('--dry-run');
const SKIP_PEOPLE = process.argv.includes('--skip-people');
const DEFAULT_PASSWORD = '12345678';

const SITE = { code: 'RLVN', name: 'Relats Vietnam', timezone: 'Asia/Ho_Chi_Minh', country_code: 'VN' };
const DEPARTMENT = { code: 'PROD', name: 'Production' };
const SECTIONS = ['SC', 'TX'];

// Where each Area / Process belongs. The file leaves Section blank on 41 rows;
// this is the mapping that files them, and it is also checked against every row
// that does name a Section.
const AREA_SECTION = {
  'Cutting MTU': 'SC',
  'Raschel': 'SC',
  'Shaping': 'SC',
  'Warping': 'SC',
  'Cutting SC': 'SC',
  'Braiding': 'TX',
  'Winding': 'TX',
  'Coating': 'TX',
  'Vision': 'TX',
  'Singing': 'TX',
  'Fest': 'TX',
  'Reeling': 'TX',
  'Cutting VSC': 'TX'
};

// The plant `mtu` database's public.machines: 17 rows, all active. Cutting MTU only.
const MTU_MACHINES = ['MTU40', 'MTU47', 'MTU17', 'MTU16', 'MTU28', 'MTU29', 'MTU23', 'MTU21', 'MTU22', 'MTU24', 'MTU25', 'MTU26', 'MTU27', 'MTU44', 'MTU34', 'MTU37', 'MTU45'];
const MACHINE_UNIT = 'SC-CUTTING-MTU';
const MACHINE_SECTION = 'SC';
const SHIFT_PATTERN = [
  { code: 'A', name: 'Shift A', start_time: '06:00', sort_order: 1 },
  { code: 'B', name: 'Shift B', start_time: '14:00', sort_order: 2 },
  { code: 'C', name: 'Shift C', start_time: '22:00', sort_order: 3 }
];
const NO_MACHINE_MASTER = ['Cutting SC', 'Raschel', 'Shaping', 'Warping', 'every TX area'];

// These Area / Process values are not areas: the person sits at their Section.
const SECTION_LEVEL_AREAS = { 'Production Team Leader': 'Leader', 'Production Shift Supervisor': 'Shift sup' };

// Position -> Job role code, Account role, and what the Grant looks like.
const POSITIONS = {
  'Operator': { jobRole: 'operator', role: 'operator', grant: 'area' },
  'Trainee': { jobRole: 'trainee', role: 'operator', grant: 'area' },
  'Production Team Leader': { jobRole: 'production-team-leader', role: 'supervisor', grant: 'section' },
  'Production Shift Supervisor': { jobRole: 'production-shift-supervisor', role: 'supervisor', grant: 'section' },
  'Quality Inspector': { jobRole: 'quality-inspector', role: 'engineer', grant: 'site' }
};

// ---------------------------------------------------------------------------
// The file
// ---------------------------------------------------------------------------

function fail(message) {
  throw new Error(message);
}

function unitCode(section, area) {
  return `${section}-${area.toUpperCase().replace(/[^A-Z0-9]+/g, '-')}`;
}

// The file has no quoted fields, so a split on commas is enough; a row with the
// wrong number of fields means that stopped being true and the run stops.
function readRows() {
  const text = readFileSync(CSV_PATH, 'utf8').replace(/^﻿/, '');
  const [header, ...lines] = text.split(/\r?\n/).filter((line) => line.trim() !== '');
  const columns = header.split(',');
  const expected = ['No', 'ID', 'Name', 'Position', 'Section', 'Area / Process', 'Joining Date', 'Present in'];
  if (columns.join('|') !== expected.join('|')) fail(`Unexpected CSV header: ${header}`);

  const seenIds = new Set();
  return lines.map((line, index) => {
    const fields = line.split(',');
    if (fields.length !== columns.length) fail(`CSV line ${index + 2}: expected ${columns.length} fields, got ${fields.length}`);
    const [no, id, name, position, section, area, joined] = fields.map((field) => field.trim());
    const where = `CSV line ${index + 2} (ID ${id})`;

    if (!/^\d+$/.test(id)) fail(`${where}: ID is not a number`);
    if (seenIds.has(id)) fail(`${where}: ID appears twice`);
    seenIds.add(id);

    const words = name.split(/\s+/).filter(Boolean);
    if (words.length < 2) fail(`${where}: Name "${name}" has no family name and given name to split`);
    if (words.join(' ') !== name) fail(`${where}: Name "${name}" has irregular spacing`);

    const spec = POSITIONS[position];
    if (!spec) fail(`${where}: Position "${position}" is not in the mapping`);
    if (joined !== '' && !/^\d{4}-\d{2}-\d{2}$/.test(joined)) fail(`${where}: Joining Date "${joined}" is not YYYY-MM-DD`);

    let unit;
    let sectionCode;
    if (spec.grant === 'section') {
      if (area !== SECTION_LEVEL_AREAS[position]) fail(`${where}: ${position} expected Area / Process "${SECTION_LEVEL_AREAS[position]}", got "${area}"`);
      if (!SECTIONS.includes(section)) fail(`${where}: ${position} needs a Section of ${SECTIONS.join(' or ')}, got "${section}"`);
      sectionCode = section;
      unit = section;
    } else {
      sectionCode = AREA_SECTION[area];
      if (!sectionCode) fail(`${where}: Area / Process "${area}" is not in the mapping`);
      if (section !== '' && section !== sectionCode) fail(`${where}: Area / Process "${area}" belongs to ${sectionCode} but the row says "${section}"`);
      unit = unitCode(sectionCode, area);
    }

    return {
      no,
      employeeNo: id,
      name,
      firstName: words.slice(0, -1).join(' '),
      lastName: words[words.length - 1],
      position,
      spec,
      sectionCode,
      area: spec.grant === 'section' ? null : area,
      unit,
      hiredOn: joined === '' ? null : joined
    };
  });
}

// ---------------------------------------------------------------------------
// The database, or none
// ---------------------------------------------------------------------------

const counts = {};
const planned = [];

function tally(table, outcome) {
  counts[table] ??= { created: 0, updated: 0, unchanged: 0 };
  counts[table][outcome] += 1;
}

// A client whose reads go to the real database (read only) and whose writes go
// nowhere. A row that does not exist yet gets a negative stand-in id, and
// anything looked up by that id finds nothing, which is exactly right.
function dryRunClient(real) {
  let fakeId = 0;
  return {
    async query(text, params) {
      if (/^\s*(insert|update)\b/i.test(text)) {
        return { rows: /returning/i.test(text) ? [{ id: String(--fakeId) }] : [] };
      }
      return real ? real.query(text, params) : { rows: [] };
    }
  };
}

// One transaction per phase: committed on success, rolled back on any error,
// and in a dry run read only and never committed.
async function phase(pool, name, work) {
  console.log(`\n== ${name}`);
  if (DRY_RUN) {
    const real = pool ? await pool.connect() : null;
    try {
      if (real) await real.query('BEGIN READ ONLY');
      return await work(dryRunClient(real));
    } finally {
      if (real) {
        await real.query('ROLLBACK');
        real.release();
      }
    }
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// Finds the row for `key`, inserts it when absent, otherwise updates whichever
// of `values` differ. `insertOnly` is written on insert and never compared or
// updated (it may be an async function, so a hash is only computed when a row
// is really being created). Table and column names are this script's own
// constants; every value goes in as a parameter. Returns the row's id (its
// primary key, `idColumn`).
async function sync(client, table, { key, values, insertOnly = {}, label, idColumn = 'id' }) {
  const keyColumns = Object.keys(key);
  const valueColumns = Object.keys(values);
  const whereParams = [];
  const where = keyColumns.map((column) => {
    if (key[column] === null) return `${column} IS NULL`;
    whereParams.push(key[column]);
    return `${column} = $${whereParams.length}`;
  });

  const { rows: [existing] } = await client.query(
    `SELECT ${idColumn}::text AS id${valueColumns.map((column) => `, ${column}::text AS ${column}`).join('')}
       FROM ${table}
      WHERE ${where.join(' AND ')}`,
    whereParams
  );

  if (!existing) {
    const extra = typeof insertOnly === 'function' ? await insertOnly() : insertOnly;
    const all = { ...key, ...values, ...extra };
    const columns = Object.keys(all);
    const { rows: [created] } = await client.query(
      `INSERT INTO ${table} (${columns.join(', ')})
       VALUES (${columns.map((_, i) => `$${i + 1}`).join(', ')})
       RETURNING ${idColumn}::text AS id`,
      columns.map((column) => all[column])
    );
    tally(table, 'created');
    planned.push(`create  ${table} ${label}`);
    return created.id;
  }

  const same = (column) => (values[column] === null ? existing[column] === null : existing[column] === String(values[column]));
  const changed = valueColumns.filter((column) => !same(column));
  if (changed.length === 0) {
    tally(table, 'unchanged');
    return existing.id;
  }
  await client.query(
    `UPDATE ${table} SET ${changed.map((column, i) => `${column} = $${i + 1}`).join(', ')} WHERE ${idColumn} = $${changed.length + 1}`,
    [...changed.map((column) => values[column]), existing.id]
  );
  tally(table, 'updated');
  planned.push(`update  ${table} ${label} (${changed.join(', ')})`);
  return existing.id;
}

// ---------------------------------------------------------------------------
// Phases
// ---------------------------------------------------------------------------

function loadDate() {
  // The run's date at the Site, not the machine's.
  return new Intl.DateTimeFormat('en-CA', { timeZone: SITE.timezone }).format(new Date());
}

async function loadTree(client, rows) {
  const siteId = await sync(client, 'sites', { key: { code: SITE.code }, values: { name: SITE.name, timezone: SITE.timezone, country_code: SITE.country_code, is_active: true }, label: SITE.code });
  const unit = (code, name, unitType, parentId) =>
    sync(client, 'org_units', { key: { site_id: siteId, code }, values: { name, unit_type: unitType, parent_id: parentId, is_active: true }, label: code });

  const departmentId = await unit(DEPARTMENT.code, DEPARTMENT.name, 'department', null);
  const sectionIds = {};
  for (const code of SECTIONS) sectionIds[code] = await unit(code, code, 'section', departmentId);

  const areaIds = {};
  const areas = new Map();
  for (const row of rows) if (row.area) areas.set(row.unit, { name: row.area, section: row.sectionCode });
  for (const [code, { name, section }] of [...areas].sort(([a], [b]) => a.localeCompare(b))) {
    areaIds[code] = await unit(code, name, 'area', sectionIds[section]);
  }
  return { siteId, departmentId, unitIds: { ...sectionIds, ...areaIds } };
}

async function lookupUnit(client, siteId, code) {
  const { rows: [unit] } = await client.query('SELECT id::text AS id FROM org_units WHERE site_id = $1 AND code = $2', [siteId, code]);
  if (!unit && DRY_RUN) return null;
  if (!unit) fail(`Org Unit ${code} is not loaded at this Site; the tree load has to run first.`);
  return unit.id;
}

// Writes the pattern only when the Site has no definition at all.
async function loadShiftPattern(client, siteId) {
  const { rows: existing } = await client.query(
    'SELECT code, to_char(start_time, \'HH24:MI\') AS start_time, duration_minutes, break_minutes, day_offset, is_active FROM shift_definitions WHERE site_id = $1 ORDER BY sort_order, code',
    [siteId]
  );
  if (existing.length > 0) {
    console.log(`  Site already has ${existing.length} shift definition(s); left untouched:`);
    for (const d of existing) console.log(`    ${d.code} ${d.start_time} ${d.duration_minutes}min break ${d.break_minutes} day_offset ${d.day_offset}${d.is_active ? '' : ' (inactive)'}`);
    for (let i = 0; i < existing.length; i += 1) tally('shift_definitions', 'unchanged');
    return;
  }
  for (const shift of SHIFT_PATTERN) {
    await client.query(
      `INSERT INTO shift_definitions (site_id, code, name, start_time, duration_minutes, break_minutes, day_offset, sort_order, is_active)
       VALUES ($1, $2, $3, $4, 480, 0, 0, $5, TRUE)
       ON CONFLICT ON CONSTRAINT shift_definitions_code_unique DO NOTHING`,
      [siteId, shift.code, shift.name, shift.start_time, shift.sort_order]
    );
    tally('shift_definitions', 'created');
    planned.push(`create  shift_definitions ${shift.code} ${shift.start_time}`);
  }
}

async function loadMachines(client, siteId) {
  const orgUnitId = await lookupUnit(client, siteId, MACHINE_UNIT);
  for (const name of MTU_MACHINES) {
    await sync(client, 'assets', {
      key: { code: name },
      values: { name },
      insertOnly: { org_unit_id: orgUnitId, asset_type: 'machine', is_active: true },
      label: `${name} at ${MACHINE_UNIT}`
    });
  }
}

// Generates the SC section's calendar. A dry run cannot call the function (it
// writes), so it only says what it would do.
async function loadCalendar(client, siteId) {
  const sectionId = await lookupUnit(client, siteId, MACHINE_SECTION);
  if (DRY_RUN || sectionId === null) {
    console.log(`  dry run: would generate ${MACHINE_SECTION} shift instances, 7 days back to 60 ahead`);
    return 0;
  }
  const { rows: [{ made }] } = await client.query(
    `SELECT generate_shift_instances($1::bigint, current_date - 7, current_date + 60) AS made`,
    [sectionId]
  );
  console.log(`  ${MACHINE_SECTION}: ${made} shift instance(s) created`);
  return made;
}

async function loadJobRoles(client, rows) {
  const ids = {};
  for (const position of Object.keys(POSITIONS)) {
    if (!rows.some((row) => row.position === position)) continue;
    const code = POSITIONS[position].jobRole;
    ids[position] = await sync(client, 'job_roles', { key: { code }, values: { name: position, is_active: true }, label: code });
  }
  return ids;
}

async function loadEmployees(client, rows) {
  const ids = {};
  for (const row of rows) {
    ids[row.employeeNo] = await sync(client, 'employees', {
      key: { employee_no: row.employeeNo },
      values: { first_name: row.firstName, last_name: row.lastName, hired_on: row.hiredOn, is_active: true },
      label: `${row.employeeNo} ${row.name}`
    });
  }
  return ids;
}

async function loadAssignments(client, rows, { unitIds, jobRoleIds, employeeIds }) {
  const today = loadDate();
  for (const row of rows) {
    // Without a hire date the start is the load date, and only on creation.
    const start = row.hiredOn === null ? {} : { effective_from: row.hiredOn };
    await sync(client, 'employee_assignments', {
      key: { employee_id: employeeIds[row.employeeNo], effective_to: null },
      values: { org_unit_id: unitIds[row.unit], job_role_id: jobRoleIds[row.position], ...start },
      insertOnly: row.hiredOn === null ? { effective_from: today } : {},
      label: `${row.employeeNo} at ${row.unit} as ${row.spec.jobRole}`
    });
  }
}

async function loadAccounts(client, rows, { departmentId, unitIds, employeeIds }) {
  for (const row of rows) {
    const accountId = await sync(client, 'app_users', {
      key: { email: `${row.employeeNo}@relats.vn` },
      values: {
        display_name: row.name,
        employee_id: employeeIds[row.employeeNo],
        role: row.spec.role,
        external_subject: `local:${row.employeeNo}`,
        is_active: true,
        approval_status: 'approved'
      },
      label: `${row.employeeNo}@relats.vn as ${row.spec.role}`
    });

    // Insert only: an existing credential is never touched.
    await sync(client, 'account_credentials', {
      key: { app_user_id: accountId },
      values: {},
      idColumn: 'app_user_id',
      insertOnly: async () => ({ password_hash: await hashSecret(DEFAULT_PASSWORD), is_enabled: true, must_change_password: true }),
      label: `${row.employeeNo}@relats.vn`
    });

    const scope = { area: [unitIds[row.unit], false, false], section: [unitIds[row.unit], true, false], site: [departmentId, false, true] }[row.spec.grant];
    await sync(client, 'app_user_org_units', {
      key: { app_user_id: accountId, org_unit_id: scope[0] },
      values: { can_write: scope[1], quality_authority: scope[2] },
      label: `${row.employeeNo}@relats.vn on ${row.spec.grant === 'site' ? DEPARTMENT.code : row.unit}`
    });
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

function printReport(rows, { people }) {
  if (DRY_RUN) {
    console.log('\n== What a real run would change');
    for (const line of planned) console.log(`  ${line}`);
    if (planned.length === 0) console.log('  nothing');
  }

  const tables = ['sites', 'org_units', 'shift_definitions', 'assets', ...(people ? ['job_roles', 'employees', 'employee_assignments', 'app_users', 'account_credentials', 'app_user_org_units'] : [])];
  console.log(`\n== ${DRY_RUN ? 'Dry run, nothing written: would be' : 'Counts'}`);
  console.log(`  ${'table'.padEnd(22)} ${'created'.padStart(8)} ${'updated'.padStart(8)} ${'unchanged'.padStart(10)}`);
  for (const table of tables) {
    const c = counts[table] ?? { created: 0, updated: 0, unchanged: 0 };
    console.log(`  ${table.padEnd(22)} ${String(c.created).padStart(8)} ${String(c.updated).padStart(8)} ${String(c.unchanged).padStart(10)}`);
  }

  if (!people) return;

  const undated = rows.filter((row) => row.hiredOn === null);
  console.log(`\n== Placed as of the load date, hire date unknown (${undated.length})`);
  console.log(`  ${undated.map((row) => row.employeeNo).join(', ')}`);

  const byName = new Map();
  for (const row of rows) byName.set(row.name, [...(byName.get(row.name) ?? []), row.employeeNo]);
  const repeated = [...byName].filter(([, ids]) => ids.length > 1);
  console.log('\n== Names that repeat');
  for (const [name, ids] of repeated) console.log(`  ${name}: ${ids.join(', ')}`);
  console.log('  These are distinct people with distinct employee numbers and are created as such.');
  console.log('  900555 and 900578 share a name and an area and joined five months apart; a human should confirm they are two people.');

  console.log('\n== Risk: one default password');
  console.log(`  ${rows.length} people share one default password. The forced-change flow is a named follow-up;`);
  console.log('  until it ships, anyone who knows an employee number can sign in as that person.');
}

async function main() {
  const rows = readRows();
  console.log(`${DRY_RUN ? 'DRY RUN. ' : ''}${rows.length} rows read from ${path.relative(process.cwd(), CSV_PATH) || CSV_PATH}`);

  if (!process.env.DATABASE_URL && !DRY_RUN) fail('DATABASE_URL is required (only --dry-run may go without it).');
  const pool = process.env.DATABASE_URL ? new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 1 }) : null;

  try {
    const tree = await phase(pool, 'Site and org tree', (client) => loadTree(client, rows));
    await phase(pool, 'Shift pattern', (client) => loadShiftPattern(client, tree.siteId));
    await phase(pool, 'Machines (Assets)', (client) => loadMachines(client, tree.siteId));
    await phase(pool, 'Shift calendar', (client) => loadCalendar(client, tree.siteId));
    console.log(`\n== No machine master exists for: ${NO_MACHINE_MASTER.join(', ')}. Nothing was loaded or invented for them.`);
    if (SKIP_PEOPLE) {
      console.log('\n== --skip-people: Job roles, Employees, Assignments and Accounts not loaded');
      printReport(rows, { people: false });
      return;
    }
    const jobRoleIds = await phase(pool, 'Job roles', (client) => loadJobRoles(client, rows));
    const employeeIds = await phase(pool, 'Employees', (client) => loadEmployees(client, rows));
    await phase(pool, 'Assignments', (client) => loadAssignments(client, rows, { ...tree, jobRoleIds, employeeIds }));
    await phase(pool, 'Accounts, credentials and grants', (client) => loadAccounts(client, rows, { ...tree, employeeIds }));
    printReport(rows, { people: true });
  } finally {
    if (pool) await pool.end();
  }
}

export { loadTree, loadShiftPattern, loadMachines, loadCalendar, readRows, counts, MTU_MACHINES };

// Importing this file (the integration test does) must not run the load.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`\nFAILED: ${error.message}`);
    process.exit(1);
  });
}
