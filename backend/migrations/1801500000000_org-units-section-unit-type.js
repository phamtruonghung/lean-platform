/**
 * `org_units.unit_type` gains `section` (issue #271, part of #267). The plant
 * describes its structure as Department (Production) -> Section (SC, TX) ->
 * Area/Process (Braiding, Cutting MTU, Winding...), and the CHECK permitted
 * only `area | department | line | cell | work_center`, so SC and TX had no
 * honest type and a user had to lie about what they created.
 *
 * **Drop and recreate, under the same name.** The baseline declared the CHECK
 * inline and unnamed, so Postgres auto-named it `org_units_unit_type_check`
 * (`<table>_<column>_check`). That name is kept: it is what the baseline's
 * constraint already is in every database, it is the name a constraint
 * violation reports, and it is greppable from here. Dropping uses
 * `IF EXISTS` so a database that somehow lacks it still converges.
 *
 * **Nothing else about the tree changes.** No hierarchy rule is added (a
 * section under an area stays allowed, like any parent today) and no existing
 * type is renamed or removed, so every existing row still satisfies the new
 * CHECK. `plant.js`'s `UNIT_TYPES` and the Dart `OrgUnitTypes` move in the
 * same commit and must keep listing exactly these values.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql('ALTER TABLE org_units DROP CONSTRAINT IF EXISTS org_units_unit_type_check');
  pgm.sql(`
    ALTER TABLE org_units
      ADD CONSTRAINT org_units_unit_type_check
      CHECK (unit_type IN ('area', 'department', 'section', 'line',
                           'cell', 'work_center'))
  `);
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's own requirement that a migration
  // define both directions. It fails if any row already uses 'section'.
  pgm.sql('ALTER TABLE org_units DROP CONSTRAINT IF EXISTS org_units_unit_type_check');
  pgm.sql(`
    ALTER TABLE org_units
      ADD CONSTRAINT org_units_unit_type_check
      CHECK (unit_type IN ('area', 'department', 'line', 'cell', 'work_center'))
  `);
};
