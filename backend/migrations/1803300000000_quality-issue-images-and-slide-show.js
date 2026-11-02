/**
 * A picture of a Quality issue, and the two flags that put an issue in the
 * slide show (issue #419).
 *
 * **Why a second `bytea` column exists.** ADR-0052 made `employee_signatures`
 * the schema's one image, and `schema.test.js` fails if a second `bytea` column
 * appears — deliberately, because "the Platform records text only" is a
 * decision rather than an accident. A shop-floor slide show needs a picture of
 * the nonconforming product, and the Platform has no object store; adding one
 * is a much bigger decision than this feature. ADR-0059 records the second
 * exception and names both tables, so the schema test's guard becomes "these
 * two tables, named" rather than "one table, forever".
 *
 * **`quality_issue_images` holds either a Non-conformance's picture or a
 * customer complaint's** — exactly one of the two foreign keys is set, which
 * `num_nonnulls(...) = 1` states in the database rather than in a route. A
 * single table, because the two records are one shape here: a number, a state,
 * a product and (at least) one picture. The alternative — two byte-identical
 * tables — buys nothing the CHECK does not already buy, and a slide show that
 * reads both would then have to UNION them.
 *
 * **The bounds live in the database too.** A row cannot exist that is over
 * 5 MiB (`image_bytes <= 5242880`), whose `image_bytes` disagrees with
 * `octet_length(image)`, whose long edge is over 1600 px, or whose
 * `content_type` is not one of the three formats the client can read. The route
 * refuses those first with a sentence a caller can act on; these constraints
 * are what makes the sentence true of the table as well as of the door.
 *
 * **The slide-show choice is a flag and a position on the record itself.** The
 * card asked for `in_slide_show` on the issue rather than a separate membership
 * table: a supervisor already works in the registers, so choosing an issue
 * there is a column on the row they are looking at, and the order the show
 * plays is the `slide_show_position` the Slide show Screen writes. NULL
 * position means "chosen, not yet ordered", which sorts after the ordered ones
 * and then by when the issue was recorded — the same rule the read uses.
 *
 * Backward-compatible per ADR-0007: two nullable/defaulted columns and a new
 * table change nothing an older running image reads or writes.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`
    CREATE TABLE quality_issue_images (
      id                    BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      -- Exactly one of these is set; see the CHECK below.
      quality_issue_id      BIGINT       REFERENCES quality_issues (id),
      customer_complaint_id BIGINT       REFERENCES customer_complaints (id),
      content_type          TEXT         NOT NULL,
      image                 BYTEA        NOT NULL,
      image_bytes           INTEGER      NOT NULL,
      width                 INTEGER      NOT NULL,
      height                INTEGER      NOT NULL,
      -- In the plant's own words, and a sentence rather than a field: a
      -- caption is read on the slide under the picture.
      caption               TEXT,
      created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
      updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
      created_by            BIGINT,
      updated_by            BIGINT,

      CONSTRAINT quality_issue_images_one_issue
        CHECK (num_nonnulls(quality_issue_id, customer_complaint_id) = 1),
      CONSTRAINT quality_issue_images_content_type_check
        CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp')),
      CONSTRAINT quality_issue_images_bytes_matches
        CHECK (image_bytes = octet_length(image)),
      -- 5 MiB: the ceiling the upload route refuses at, restated so a write
      -- that skipped the route cannot store something a slide cannot load.
      CONSTRAINT quality_issue_images_bytes_ceiling
        CHECK (image_bytes <= 5242880),
      -- The long edge is what the client downscales to and what a projector's
      -- 1080p output can hold without resampling on the shop floor's mini PC.
      CONSTRAINT quality_issue_images_dimensions
        CHECK (width BETWEEN 1 AND 1600 AND height BETWEEN 1 AND 1600),
      CONSTRAINT quality_issue_images_caption_length
        CHECK (caption IS NULL OR char_length(caption) <= 280)
    )
  `);

  pgm.sql(`
    CREATE INDEX quality_issue_images_nonconformance_idx
      ON quality_issue_images (quality_issue_id, created_at)
      WHERE quality_issue_id IS NOT NULL
  `);
  pgm.sql(`
    CREATE INDEX quality_issue_images_complaint_idx
      ON quality_issue_images (customer_complaint_id, created_at)
      WHERE customer_complaint_id IS NOT NULL
  `);

  // The slide show's own two columns, on both records that can be shown. The
  // partial indexes are what the show's read uses: it asks for the chosen few,
  // never for the register.
  pgm.sql('ALTER TABLE quality_issues ADD COLUMN in_slide_show BOOLEAN NOT NULL DEFAULT FALSE');
  pgm.sql(`
    ALTER TABLE quality_issues
      ADD COLUMN slide_show_position INTEGER
      CONSTRAINT quality_issues_slide_show_position_check
      CHECK (slide_show_position IS NULL OR slide_show_position > 0)
  `);
  pgm.sql(`
    CREATE INDEX quality_issues_slide_show_idx
      ON quality_issues (slide_show_position, id)
      WHERE in_slide_show
  `);

  pgm.sql('ALTER TABLE customer_complaints ADD COLUMN in_slide_show BOOLEAN NOT NULL DEFAULT FALSE');
  pgm.sql(`
    ALTER TABLE customer_complaints
      ADD COLUMN slide_show_position INTEGER
      CONSTRAINT customer_complaints_slide_show_position_check
      CHECK (slide_show_position IS NULL OR slide_show_position > 0)
  `);
  pgm.sql(`
    CREATE INDEX customer_complaints_slide_show_idx
      ON customer_complaints (slide_show_position, id)
      WHERE in_slide_show
  `);

  pgm.sql('SELECT attach_updated_at(\'quality_issue_images\')');
  pgm.sql('SELECT attach_actor_columns(\'quality_issue_images\')');
  pgm.sql('SELECT attach_audit(\'quality_issue_images\')');

  pgm.sql('ALTER TABLE quality_issue_images ENABLE ROW LEVEL SECURITY');
};

exports.down = (pgm) => {
  // Forward-only in production per ADR-0007 — this exists for local
  // development and for node-pg-migrate's requirement that a migration
  // define both directions.
  pgm.sql('ALTER TABLE quality_issue_images DISABLE ROW LEVEL SECURITY');
  pgm.sql('DROP TRIGGER IF EXISTS quality_issue_images_audit ON quality_issue_images');
  pgm.sql('DROP TRIGGER IF EXISTS zz_quality_issue_images_set_actor ON quality_issue_images');
  pgm.sql('DROP TRIGGER IF EXISTS quality_issue_images_set_updated_at ON quality_issue_images');
  pgm.sql('DROP TABLE IF EXISTS quality_issue_images');
  pgm.sql('DROP INDEX IF EXISTS customer_complaints_slide_show_idx');
  pgm.sql('ALTER TABLE customer_complaints DROP COLUMN IF EXISTS slide_show_position');
  pgm.sql('ALTER TABLE customer_complaints DROP COLUMN IF EXISTS in_slide_show');
  pgm.sql('DROP INDEX IF EXISTS quality_issues_slide_show_idx');
  pgm.sql('ALTER TABLE quality_issues DROP COLUMN IF EXISTS slide_show_position');
  pgm.sql('ALTER TABLE quality_issues DROP COLUMN IF EXISTS in_slide_show');
};
