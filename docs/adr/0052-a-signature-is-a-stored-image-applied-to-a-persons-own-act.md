---
status: accepted
---

# A Signature is a stored image, applied to a person's own act, and the Platform keeps one

Date: 2026-10-19

Every document this plant signs has a Signature line, and the Platform records
none of them. The one that exists today is the Training Record sheet
(`training record template.PNG`) — the `Signature / Ký tên` column beside each
Trainee, the trainer's line at the foot, HR's line beside it. ADR-0043 already
decides that a Trainee's answer *is* their signature on that form and that
nobody answers on their behalf; ADR-0044 decides the sheet is printed from the
browser and that the Signature cell prints the answer date, left empty for a
Trainee who has not answered so a hand signature can still be collected. What
neither decides is what a signature *is* in this Platform, where one is kept,
and what a record is left holding afterwards. Issue #316 specifies the
capability and #317–#320 are its slices.

## The decision

**A Signature is an Employee's own mark, kept once and applied wherever they
would otherwise sign a sheet by hand.** It is an image — uploaded as a photo or
scan, or drawn on screen — normalised to a small transparent PNG, and kept in
the Platform's own database. It is reused on every later act by that person, and
what a record keeps is **which** Signature was applied to it, **when**, and
whether it was the one the person had stored or one drawn at that moment. A
Signature replaced later never changes a sheet already signed.

**This is one narrow exception to "the Platform records text only", and it must
stay one table wide.** The baseline's third correction says there is no
`attachments` table and the Platform records text only, and
`test/integration/schema.test.js` asserts no `attachments` table exists
anywhere. `employee_signatures` is that exception: a person's own mark, small,
in the table that holds it. **It is not a file-storage capability** — no
documents, no scans, no certificates, no attachment on any record — and the
test that guards the rule is strengthened rather than deleted: a second table
with a `bytea` column fails the suite and has to argue for itself.

**The table is append-only: one row per image ever applied, and no row is ever
written twice.** The current Signature is the newest *kept* row with nothing
superseding it, held by a partial unique index; a stroke drawn for one signing
act is a row too, but one that is never current and never reused. So a record
can name the exact row it was signed with and that row can never change under
it, which is immutability without copying bytes per signing act.

**A Signature is applied only to an act the person performs themselves.**
Signing for somebody else is refused everywhere, exactly as ADR-0043 refuses
answering for somebody else: the Account door resolves the caller's own current
Signature and the inline door writes one for the caller's own Employee; no route
ever takes a Signature id from the request. An **administrator may set one for
an Employee who holds no Account** — most of a plant can never sign in, and the
alternative is that the feature reaches only the people who least need it — and
that door **closes with a 409 the moment the Employee can set their own**, with
the setting Account recorded on the row so a mark set for somebody is never
mistaken for a mark somebody uploaded. (ADR-0053 moves that rule into the
database so a concurrent link cannot slip past it.)

**The shared floor device may apply a stored Signature, and may never write
one.** A device answers on the frozen `/api/maintenance` prefix for an Employee
identified by number and PIN (ADR-0016, #201), and a stroke drawn there is
recorded as `drawn` — a one-off row that supersedes nothing. A PIN is enough to
sign this morning's sheet; it is not enough to own a mark for good, because a
stored Signature applied by whoever happens to be holding the device is a
rubber stamp, and the platform would be recording a person's mark that the
person did not give.

**The act is the evidence; the image is its rendering.** Nothing here hashes a
record's content, keeps a canonical copy of what was signed, or raises a
"this no longer matches what was signed" warning when a record is corrected.
The evidence is the authenticated act — an Account's session, or an Employee
identified by number and PIN — exactly as it is today, and what the image adds
is that the printed sheet looks like the plant's own sheet. Anyone wanting a
tamper-evident signature is asking for a different feature, and that is the
sentence that should stop the next agent from building it by halves.

**The moment signed is the moment answered.** `training_trainees.answered_at`
is the signed-at; nothing adds a second timestamp for one act. What prints is
the Site's local date, as the form prints it today (ADR-0048).

## Why not an object bucket

Rejected. A bucket means a storage client the backend does not have, a second
consistency story (a row referencing a mark that may or may not be there), a
URL-access question that must be answered the same way for every reader of a
record, and a second thing to back up beside the one database that already
holds everything. ADR-0051 leaves production data on Supabase Cloud and
identity local; a bucket would make the Platform's own database the *only*
place a signature might not be. A mark is two kilobytes; it belongs in the row.

## Why not a server-side resize, and why the client normalises

Rejected as a dependency. The backend carries five dependencies — `dotenv`,
`express`, `jose`, `node-pg-migrate`, `pg` — and no image library, and this
feature does not add one for a two-kilobyte mark. The client normalises (fixed
box, transparency kept, stepped down until the PNG fits) and the server
validates (PNG signature, `IHDR` shape, and a 48 KiB ceiling, in its own few
lines of code). The cap is 48 KiB because base64 is ~64 KiB of the existing
`express.json({ limit: '100kb' })`, which is therefore not raised for the whole
API. If a plant ever wants the server to be the only thing trusted with pixels,
that is a `pngjs`-shaped dependency and its own decision.

## Consequences

- **The printed form is signed.** The Signature cell renders the applied image
  with the Site's local date beneath it; a Trainee who has not answered still
  prints an empty cell, so the paper path ADR-0044 protects is untouched; and a
  decline prints as a decline, never as a mark.
- **Signing never gates an answer.** A Trainee with no device and no way to draw
  still answers, and the cell stays empty for their hand signature. Requiring a
  mark would convert "cannot upload" into "cannot confirm" for the population
  this form is about.
- **The type of the mark is never invisible.** `signature_applied_as` on the
  signing row says `stored` or `drawn`, so a record can always answer "was this
  signed in person", which is the question the floor-device rule exists to keep
  answerable.
- **Every other signature line is still paper.** The trainer's line and HR's
  line print blank for a hand signature; the Platform has no HR actor
  (ADR-0044). The Attendance sheet, a Leave decision, a CAPA verification and a
  Concession keep their own names as evidence until their own tickets give them
  Signatures on this model.
- **A surface that reads a record can read the Signature on it.** The image
  address follows the record's own read rule, so any approved Account that may
  read a Training record may fetch its Signatures — the register's read is
  open (ADR-0009) and the sheet is printable by anyone who may read the record.
  A Signature is not a secret, and its own address is the only door that
  returns one.
- **The glossary gains one word.** `CONTEXT.md` defines **Signature**, and
  refuses `e-signature`, `digital signature` and `sign-off` — the first two
  name legal standards this Platform does not claim, and the third is an
  Approval.
