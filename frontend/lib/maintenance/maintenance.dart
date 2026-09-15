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
/// `lib/platform/` is not a cross-Module consumer and does not go through
/// here: it is the mounting layer, the same special case `src/index.js` is for
/// a Module's `router` on the server.
library;

export 'org_unit_chooser.dart' show OrgUnitChooser;
