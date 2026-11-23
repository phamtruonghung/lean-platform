/*
 * The assessment Question bank (issue #588, ADR-0068, slice 2): one row per
 * Question, filed on one Org Unit, the process. This file owns the SQL, the
 * row shape, the validation of a Question's own fields and the paste parser;
 * assessment-question-routes.js owns Express, the permission codes and the
 * Org Unit scope question. Nothing here asks who is calling — it takes the ids
 * it is handed and assumes the route already checked what needed checking
 * (AGENTS.md section 6) — and it requires no other Module (ADR-0006).
 *
 * **Fingerprints are computed by Postgres, never by this file.**
 * `assessment_questions.question_text_fingerprint` is a generated column over
 * `md5(lower(regexp_replace(btrim(text), '\s+', ' ', 'g')))`. Reproducing that
 * in JavaScript would have to agree with Postgres on three things that differ
 * between the two: `btrim` strips only spaces, `\s` is Postgres's own class,
 * and `lower()` follows the database's locale for Vietnamese letters. A paste
 * that repeats itself is therefore detected by asking Postgres to fingerprint
 * each block with the column's own expression (FINGERPRINT_SQL below), so the
 * two copies of the rule cannot drift: a block the parser calls a repeat is
 * one the column would have refused.
 *
 * **A fingerprint clash is a 409 that names the Question already there**, its
 * id and its text, so the author can correct it with a PATCH instead of
 * filing a near-duplicate. A retired Question still holds its fingerprint.
 *
 * **The paste is all-or-nothing.** `bulkCreateQuestions` inserts every block in
 * one transaction and any refusal rolls the lot back: a half-imported bank is
 * worse than none, because the author cannot tell which half is in.
 */

const { getPool, withActor } = require('../../platform/db');
const { httpError, notFound } = require('./errors');
const { escapeLikePattern } = require('./sql');

const CORRECT_OPTIONS = ['A', 'B', 'C'];
const TEXT_MIN = 5;
const TEXT_MAX = 2000;
const OPTION_MAX = 2000;
const EXPLANATION_MAX = 2000;
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

const FINGERPRINT_KEY = 'assessment_questions_org_unit_fingerprint_key';

// The same expression the column is generated from (migration
// 1804600000000), applied to a bind parameter.
const FINGERPRINT_SQL = (param) => `md5(lower(regexp_replace(btrim(${param}), '\\s+', ' ', 'g')))`;

const QUESTION_COLUMNS = `id, org_unit_id, question_text, option_a, option_b, option_c,
  correct_option, explanation, is_active, created_at, updated_at`;

function toQuestion(row, { revealKey = true } = {}) {
  return {
    id: row.id,
    orgUnitId: row.org_unit_id,
    questionText: row.question_text,
    optionA: row.option_a,
    optionB: row.option_b,
    optionC: row.option_c,
    // Null, never absent, when the caller may not read the key: the client
    // renders a dash for a null and would have to guess at a missing field.
    correctOption: revealKey ? row.correct_option : null,
    explanation: revealKey ? row.explanation : null,
    isActive: row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function lengthOf(value) {
  return [...value].length;
}

function requireText(body, field, { min = 1, max }) {
  const value = body[field];
  if (typeof value !== 'string') throw httpError(400, `${field} is required`);
  const trimmed = value.trim();
  if (lengthOf(trimmed) < min) {
    throw httpError(400, min > 1 ? `${field} must be at least ${min} characters` : `${field} is required`);
  }
  if (lengthOf(trimmed) > max) throw httpError(400, `${field} must be at most ${max} characters`);
  return trimmed;
}

// A Question's own fields, trimmed and checked against the table's CHECKs so a
// refusal names the field instead of a constraint. Full replacement: PATCH
// restates every field, so there is one validator for create and correct.
function validateQuestion(body) {
  const source = body ?? {};
  const questionText = requireText(source, 'questionText', { min: TEXT_MIN, max: TEXT_MAX });
  const optionA = requireText(source, 'optionA', { max: OPTION_MAX });
  const optionB = requireText(source, 'optionB', { max: OPTION_MAX });
  const optionC = requireText(source, 'optionC', { max: OPTION_MAX });
  if (optionA === optionB || optionA === optionC || optionB === optionC) {
    throw httpError(400, 'the three options must be different from one another');
  }

  const { correctOption } = source;
  if (!CORRECT_OPTIONS.includes(correctOption)) {
    throw httpError(400, `correctOption must be one of ${CORRECT_OPTIONS.join(', ')}`);
  }

  let explanation = null;
  if (source.explanation !== undefined && source.explanation !== null) {
    if (typeof source.explanation !== 'string') throw httpError(400, 'explanation must be text');
    const trimmed = source.explanation.trim();
    if (trimmed !== '') {
      if (lengthOf(trimmed) > EXPLANATION_MAX) {
        throw httpError(400, `explanation must be at most ${EXPLANATION_MAX} characters`);
      }
      explanation = trimmed;
    }
  }

  return { questionText, optionA, optionB, optionC, correctOption, explanation };
}

async function findQuestion(id) {
  const { rows } = await getPool().query(
    `SELECT ${QUESTION_COLUMNS} FROM assessment_questions WHERE id = $1`,
    [id]
  );
  return rows[0] ? toQuestion(rows[0]) : null;
}

function parseWindow(value, fallback, { min, max }) {
  if (value === undefined || value === null) return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < min) return fallback;
  return Math.min(number, max);
}

// One process's bank. `total` counts the rows the filter matches (what paging
// walks); `activeCount` counts the process's active Questions whatever the
// filter, the number a paper's size is checked against.
async function listQuestions({ orgUnitId, q, includeInactive = false, limit, offset, revealKey = false }) {
  const pageSize = parseWindow(limit, DEFAULT_LIMIT, { min: 1, max: MAX_LIMIT });
  const skip = parseWindow(offset, 0, { min: 0, max: Number.MAX_SAFE_INTEGER });

  const params = [orgUnitId, includeInactive === true];
  let search = '';
  if (typeof q === 'string' && q.trim() !== '') {
    params.push(`%${escapeLikePattern(q.trim())}%`);
    search = `AND question_text ILIKE $${params.length} ESCAPE '\\'`;
  }
  const where = `org_unit_id = $1 AND ($2 OR is_active) ${search}`;

  const [page, total, active] = await Promise.all([
    getPool().query(
      `SELECT ${QUESTION_COLUMNS}
         FROM assessment_questions
        WHERE ${where}
        ORDER BY id
        LIMIT ${pageSize} OFFSET ${skip}`,
      params
    ),
    getPool().query(`SELECT count(*)::int AS n FROM assessment_questions WHERE ${where}`, params),
    getPool().query(
      'SELECT count(*)::int AS n FROM assessment_questions WHERE org_unit_id = $1 AND is_active',
      [orgUnitId]
    )
  ]);

  return {
    questions: page.rows.map((row) => toQuestion(row, { revealKey })),
    total: total.rows[0].n,
    activeCount: active.rows[0].n
  };
}

// The Question that already holds `questionText`'s fingerprint in a process,
// read after the failed write has rolled back.
async function findByFingerprint(orgUnitId, questionText) {
  const { rows } = await getPool().query(
    `SELECT id, question_text FROM assessment_questions
      WHERE org_unit_id = $1 AND question_text_fingerprint = ${FINGERPRINT_SQL('$2::text')}`,
    [orgUnitId, questionText]
  );
  return rows[0] ?? null;
}

function clashMessage(existing) {
  return `this Question is already in the bank as Question ${existing.id}: "${existing.question_text}"`;
}

// A constraint violation becomes a clean 4xx before it leaves this file; a
// database error string names tables and columns and is never echoed.
async function mapQuestionWriteError(error, orgUnitId, questionText, line) {
  if (error.code === '23505' && error.constraint === FINGERPRINT_KEY) {
    const existing = await findByFingerprint(orgUnitId, questionText);
    if (existing) {
      const prefix = line === undefined ? '' : `line ${line}: `;
      const refusal = httpError(409, `${prefix}${clashMessage(existing)}`);
      refusal.extra = { questionId: existing.id, questionText: existing.question_text };
      if (line !== undefined) refusal.extra.line = line;
      return refusal;
    }
    return httpError(409, 'this Question is already in the bank');
  }
  if (error.code === '23514') return httpError(400, 'that is not a valid Question');
  return error;
}

async function createQuestion(accountId, orgUnitId, facts) {
  try {
    const row = await withActor(accountId, async (client) => {
      const { rows } = await client.query(
        `INSERT INTO assessment_questions
           (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING ${QUESTION_COLUMNS}`,
        [orgUnitId, facts.questionText, facts.optionA, facts.optionB, facts.optionC,
          facts.correctOption, facts.explanation]
      );
      return rows[0];
    });
    return toQuestion(row);
  } catch (error) {
    throw await mapQuestionWriteError(error, orgUnitId, facts.questionText);
  }
}

// Full replacement of the Question's own fields. The route has already
// refused a retired Question.
async function correctQuestion(accountId, question, facts) {
  try {
    const row = await withActor(accountId, async (client) => {
      const { rows } = await client.query(
        `UPDATE assessment_questions
            SET question_text = $2, option_a = $3, option_b = $4, option_c = $5,
                correct_option = $6, explanation = $7
          WHERE id = $1
          RETURNING ${QUESTION_COLUMNS}`,
        [question.id, facts.questionText, facts.optionA, facts.optionB, facts.optionC,
          facts.correctOption, facts.explanation]
      );
      return rows[0];
    });
    if (!row) throw notFound('Question');
    return toQuestion(row);
  } catch (error) {
    throw await mapQuestionWriteError(error, question.orgUnitId, facts.questionText);
  }
}

// Retiring, never deleting: idempotent, a second retire is a no-op.
async function retireQuestion(accountId, id) {
  await withActor(accountId, async (client) => {
    await client.query(
      'UPDATE assessment_questions SET is_active = false WHERE id = $1 AND is_active',
      [id]
    );
  });
}

// ---------------------------------------------------------------------------
// The paste (issue #588 section 12)
// ---------------------------------------------------------------------------

const STEM_LABELS = ['câu hỏi', 'question'];
const EXPLANATION_LABELS = ['giải thích', 'explanation'];
const LETTERS = ['A', 'B', 'C'];

function pasteError(message, line, extra = {}) {
  return { message, line, ...extra };
}

// `Label: rest` where the label is one of `labels`, compared case-insensitively
// after Unicode normalisation (a pasted Vietnamese label may arrive decomposed).
function matchLabel(line, labels) {
  const match = /^\s*([^:]{1,40}?)\s*:\s*(.*)$/u.exec(line);
  if (!match) return null;
  if (!labels.includes(match[1].normalize('NFC').toLowerCase())) return null;
  return match[2].trim();
}

const OPTION_LINE = /^\s*(\*)?\s*([A-Za-z])\s*\.\s*(.*)$/u;

// Reads one block starting at lines[start] and ending at the next blank line
// (or the end). Returns { question } or { error }, plus the index to resume at.
function parseBlock(lines, start, ordinal) {
  let end = start;
  while (end < lines.length && lines[end].trim() !== '') end += 1;
  const stemLine = start + 1;

  const stem = matchLabel(lines[start], STEM_LABELS);
  if (stem === null) {
    return { end, error: pasteError(`line ${stemLine}: a block must start with 'Câu hỏi:' or 'Question:'`, stemLine) };
  }
  if (stem === '') {
    return { end, error: pasteError(`line ${stemLine}: the question text is empty`, stemLine) };
  }

  const options = [];
  let cursor = start + 1;
  while (cursor < end && options.length < 3) {
    const match = OPTION_LINE.exec(lines[cursor]);
    if (!match) break;
    const letter = match[2].toUpperCase();
    const expected = LETTERS[options.length];
    if (letter !== expected) {
      return {
        end,
        error: pasteError(`line ${cursor + 1}: expected option ${expected}, found ${letter}`, cursor + 1)
      };
    }
    options.push({ letter, marked: match[1] === '*', text: match[3].trim(), line: cursor + 1 });
    cursor += 1;
  }

  if (options.length < 3) {
    return {
      end,
      error: pasteError(
        `question ${ordinal}: expected three options A, B, C, found ${options.length}`,
        cursor < end ? cursor + 1 : stemLine
      )
    };
  }

  for (const option of options) {
    if (option.text === '') {
      return { end, error: pasteError(`line ${option.line}: option ${option.letter} is empty`, option.line) };
    }
  }

  const marked = options.filter((option) => option.marked);
  if (marked.length === 0) {
    return { end, error: pasteError(`line ${options[2].line}: no option is marked *`, options[2].line) };
  }
  if (marked.length > 1) {
    return { end, error: pasteError(`line ${marked[1].line}: two options are marked *`, marked[1].line) };
  }

  let explanation = null;
  if (cursor < end) {
    const text = matchLabel(lines[cursor], EXPLANATION_LABELS);
    if (text === null) {
      const message = matchLabel(lines[cursor], STEM_LABELS) !== null
        ? `line ${cursor + 1}: a blank line must separate one Question from the next`
        : OPTION_LINE.test(lines[cursor])
          ? `line ${cursor + 1}: a Question has exactly three options, A, B and C`
          : `line ${cursor + 1}: expected 'Giải thích:' or 'Explanation:' or a blank line`;
      return { end, error: pasteError(message, cursor + 1) };
    }
    if (text === '') {
      return { end, error: pasteError(`line ${cursor + 1}: the explanation is empty`, cursor + 1) };
    }
    explanation = text;
    cursor += 1;
    if (cursor < end) {
      return {
        end,
        error: pasteError(`line ${cursor + 1}: a blank line must separate one Question from the next`, cursor + 1)
      };
    }
  }

  let facts;
  try {
    facts = validateQuestion({
      questionText: stem,
      optionA: options[0].text,
      optionB: options[1].text,
      optionC: options[2].text,
      correctOption: marked[0].letter,
      explanation
    });
  } catch (error) {
    return { end, error: pasteError(`line ${stemLine}: ${error.message}`, stemLine) };
  }
  return { end, question: { ...facts, line: stemLine } };
}

// Format only: the blocks, or the first malformed one. It never touches the
// database; repeats are found by `findRepeatsInPaste` and `bulkCreateQuestions`.
function parsePaste(text) {
  const raw = typeof text === 'string' ? text : '';
  const lines = raw.split(/\r\n|\r|\n/);
  if (lines.every((line) => line.trim() === '')) {
    return { questions: [], error: pasteError('nothing to import', null) };
  }

  const questions = [];
  let index = 0;
  while (index < lines.length) {
    if (lines[index].trim() === '') {
      index += 1;
      continue;
    }
    const block = parseBlock(lines, index, questions.length + 1);
    if (block.error) return { questions: [], error: block.error };
    questions.push(block.question);
    index = block.end;
  }
  return { questions, error: null };
}

// Fingerprints computed by Postgres with the column's own expression, so a
// repeat here is exactly a block the unique key would have refused.
async function fingerprintsOf(texts) {
  const { rows } = await getPool().query(
    `SELECT ${FINGERPRINT_SQL('t')} AS fingerprint FROM unnest($1::text[]) WITH ORDINALITY AS u(t, n) ORDER BY n`,
    [texts]
  );
  return rows.map((row) => row.fingerprint);
}

// The first block that repeats an earlier one in the same paste, or null.
async function findRepeatInPaste(blocks) {
  if (blocks.length < 2) return null;
  const fingerprints = await fingerprintsOf(blocks.map((block) => block.questionText));
  const seen = new Map();
  for (let i = 0; i < blocks.length; i += 1) {
    if (seen.has(fingerprints[i])) {
      return pasteError(
        `line ${blocks[i].line}: this Question repeats the one on line ${seen.get(fingerprints[i])}`,
        blocks[i].line,
        { firstLine: seen.get(fingerprints[i]) }
      );
    }
    seen.set(fingerprints[i], blocks[i].line);
  }
  return null;
}

// Every block in one transaction. A repeat inside the paste is a 400 naming
// both lines; a clash with the bank is a 409 naming the line and the existing
// Question; either rolls everything back. `blocks` come from `parsePaste`.
async function bulkCreateQuestions(accountId, orgUnitId, blocks) {
  const repeat = await findRepeatInPaste(blocks);
  if (repeat) {
    const refusal = httpError(400, repeat.message);
    refusal.extra = { line: repeat.line, firstLine: repeat.firstLine };
    throw refusal;
  }

  let failedAt = null;
  try {
    const rows = await withActor(accountId, async (client) => {
      const inserted = [];
      for (let i = 0; i < blocks.length; i += 1) {
        const block = blocks[i];
        try {
          const { rows } = await client.query(
            `INSERT INTO assessment_questions
               (org_unit_id, question_text, option_a, option_b, option_c, correct_option, explanation)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             RETURNING ${QUESTION_COLUMNS}`,
            [orgUnitId, block.questionText, block.optionA, block.optionB, block.optionC,
              block.correctOption, block.explanation]
          );
          inserted.push(rows[0]);
        } catch (error) {
          failedAt = block;
          throw error;
        }
      }
      return inserted;
    });
    return rows.map((row) => toQuestion(row));
  } catch (error) {
    if (failedAt) {
      throw await mapQuestionWriteError(error, orgUnitId, failedAt.questionText, failedAt.line);
    }
    throw error;
  }
}

module.exports = {
  validateQuestion,
  findQuestion,
  listQuestions,
  createQuestion,
  correctQuestion,
  retireQuestion,
  parsePaste,
  bulkCreateQuestions
};
