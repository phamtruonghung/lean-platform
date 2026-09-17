/// The Maintenance Module's client entry point (ADR-0012's client mirror of
/// ADR-0006), the counterpart of `backend/src/modules/maintenance/index.js`
/// and of `lib/people/people.dart`.
///
/// It exists because a second Module needs one thing Maintenance owns: the
/// single-select Org Unit chooser Actions raises a Concern with, and filters
/// its register by. That widget drives `OrgUnitPickerBloc` — People's state
/// machine, reached through People's own entry point — and renders it as one
/// pick rather than as a Grant editor, which is exactly what Actions needs and
/// what People's own `OrgUnitPicker` is deliberately not.
///
/// The alternative was a third copy of the chooser inside `lib/actions/`.
/// This file is the smaller, documented seam: one export, named for the one
/// consumer, added the day that consumer existed rather than in anticipation
/// of it.
///
/// `UnitOfMeasure` joined it with issue #203, the same way and for the same
/// reason: the Quality Module's Product form chooses the unit a Product is
/// measured in from the baseline catalogue, off the address this Module
/// already publishes (`GET /api/maintenance/units-of-measure`, #79/#80), and
/// the model that parses it belongs to this Module. Reaching into
/// `meter.dart` for it would be exactly the reach ADR-0006 forbids on the
/// server, so the model is exported here instead — one reading of one
/// catalogue rather than a second `UnitOfMeasure` in `lib/quality/`.
///
/// `Asset` joined it with issue #205, the same way and for a third reason:
/// a Non-conformance may name the machine it was found on, so the record form
/// picks one off `GET /api/maintenance/sites/:siteId/assets` — Maintenance's
/// own register — and the model that parses it belongs to this Module. The
/// alternative was a second `Asset` in `lib/quality/`, which is the same
/// duplication ADR-0006 forbids on the server.
///
/// `lib/platform/` is not a cross-Module consumer and does not go through
/// here: it is the mounting layer, the same special case `src/index.js` is for
/// a Module's `router` on the server.
library;

export 'meter.dart' show UnitOfMeasure;
export 'asset.dart' show Asset;
export 'org_unit_chooser.dart' show OrgUnitChooser;
