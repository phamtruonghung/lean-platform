# 0059. A picture of a Quality issue is a stored image, in a second bounded column

## Status

Accepted (issue #419).

## Context

A shop-floor slide show is only worth a screen if it shows the *thing*: the burr
on the flange, the seal that did not seat, the wrong label on the pallet. The
Quality Module already records the words — a Non-conformance's description and
containment, a customer complaint's own account of what was said — and words on
a wall are read once and forgotten.

So an issue needs at least one picture, and the Platform needs somewhere to put
it. It has no object store, and adding one (S3, MinIO, a filesystem mount with
retention and backup rules of its own) is a much larger decision than this
feature: it would arrive with its own credentials, its own backup gap beside the
database's, and its own story about what happens to a picture when the record it
belongs to is deleted.

ADR-0052 already answered the same question once, for a Signature, and recorded
its answer as a deliberate exception: `employee_signatures.image` is the schema's
one `bytea` column, "one table wide", and `schema.test.js` fails if a second one
appears. That guard is what this decision has to earn its way past.

## Decision

A picture of a Quality issue is stored in the database, in
`quality_issue_images.image`, and that is the schema's **second** and named
`bytea` column. The schema test becomes an exact list of two rather than a count
of one, so a third exception still has to be argued here before it can pass.

The bounds are what make it safe, and every one of them is in the database as
well as at the door:

| bound | value | why |
|---|---|---|
| weight | 5 MiB | what a slide can load over a shop-floor LAN without a stall |
| long edge | 1600 px | a 1080p projector downsamples 1600 to 1080 once, at the projector, and a phone photo's 4000 px buys nothing on a wall |
| formats | JPEG, PNG, WebP | the three a browser draws without a plugin and a phone camera produces |
| caption | 280 characters | one sentence under the picture, not a document |
| one parent | exactly one of a Non-conformance or a complaint | `num_nonnulls(...) = 1` |

**The client downscales; the server refuses.** The backend carries no image
library — ADR-0052 established that the client does the pixel work
(`signature_png.dart` says so in its own header) — and a native image dependency
(sharp, or an ImageMagick shell-out) for one door is a worse trade than a browser
that already has a decoder. So the browser scales the picture to a 1600 px long
edge before it uploads, and the server **reads the file's own header** and refuses
anything over the bound with a sentence naming the size it actually received
(`image-file.js`). The claim the card cares about — *nothing larger than 1600 px
is stored, and nothing larger than 5 MiB is stored* — is therefore true of the
table, whatever produced the request. What the server does not do is re-encode,
so a caller that skips downscaling is told to, rather than silently served a
lower-quality copy.

**This is not a file store.** Three formats, one picture per slide, a bounded
size, no folders, no sharing links, no retention policy of its own: a picture
belongs to the record it was taken for and has no life of its own, and there is
deliberately no address that serves an image without the session that asked for
the record. If a future feature wants documents attached to anything, it needs
its own ADR and probably its own storage; this one does not start that road.

## Consequences

- `quality_issue_images` joins `employee_signatures` as a named exception, and
  the schema test that guarded the first now guards both.
- **A picture is not yet deleted with the record's own delete**, and an earlier
  draft of this ADR said it was. Both parent keys are plain `REFERENCES` with no
  `ON DELETE CASCADE`, and neither a Non-conformance nor a Customer complaint has
  a delete route, so nothing removes a picture with the record it was taken for.
  When a record delete arrives it must remove that record's pictures first, in
  the same transaction; a removal through the pictures' own `DELETE` is audited
  like any other row's (`attach_audit`).
- A backup of the database is a backup of the pictures. There is no second
  backup path to forget, and no second restore to prove.
- A row is at most 5 MiB, and the register reads only metadata, so a Site's
  register stays a small read; a picture is fetched from its own address, one at
  a time, with an `ETag` and a private cache directive.
- The two records that carry a picture are the two the slide show shows. A third
  kind of Quality record with a picture would add a third foreign key here, not a
  third table.
