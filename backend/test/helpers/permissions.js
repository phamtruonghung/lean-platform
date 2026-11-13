/*
 * A permission code put on a role for the length of one test, and taken off
 * again before the next one.
 *
 * ADR-0061's retrofit asks a code *before* the scope or Grant helper a route
 * already had, so a test whose claim is about the Grant half of the model — "a
 * write Grant on this Org Unit admits this write", "a read Grant does not" —
 * cannot reach that helper as a non-administrator once the code is seeded on
 * ROLE_ADMIN alone. Rather than weaken those tests to a role comparison they
 * were never about, they lend themselves the code:
 *
 *   test('...', async (t) => {
 *     t.after(await temporaryCode(pool, 'ROLE_OPERATOR', 'PPL_ORG_UNITS_CHANGE'));
 *     ... the test's own body, unchanged ...
 *   });
 *
 * `requirePermission` reads the join table on every request (its own header:
 * a role edit takes effect on the caller's next request), so the row is live
 * for the request the test makes and gone again by the clean-up — which runs
 * even when an assertion throws, because it is registered on `t.after`.
 *
 * The seed is restored exactly: a role that already held the code is left
 * alone, and the returned release only deletes the row this helper wrote.
 */
async function temporaryCode(pool, roleCode, code) {
  const { rows: [role] } = await pool.query('SELECT id FROM app_roles WHERE code = $1', [roleCode]);
  if (!role) throw new Error(`no role ${JSON.stringify(roleCode)} to lend ${code} to`);

  const { rows: held } = await pool.query(
    'SELECT 1 FROM app_role_permissions WHERE app_role_id = $1 AND permission_code = $2',
    [role.id, code]
  );

  await pool.query(
    `INSERT INTO app_role_permissions (app_role_id, permission_code)
     VALUES ($1, $2)
     ON CONFLICT (app_role_id, permission_code) DO NOTHING`,
    [role.id, code]
  );

  return async function release() {
    if (held.length > 0) return;
    await pool.query(
      'DELETE FROM app_role_permissions WHERE app_role_id = $1 AND permission_code = $2',
      [role.id, code]
    );
  };
}

module.exports = { temporaryCode };
