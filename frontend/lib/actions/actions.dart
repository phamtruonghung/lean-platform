/// The Actions Module's client entry point (ADR-0012's client mirror of
/// ADR-0006), the counterpart of `backend/src/modules/actions/index.js` and of
/// `lib/people/people.dart` and `lib/maintenance/maintenance.dart`.
///
/// It exists because a second Module needs three things Actions owns, and it
/// names them the way every other client entry point does — one export per
/// consumer, added the day the consumer existed rather than in anticipation of
/// it. The Quality Module's Non-conformance detail Screen (issue #208) offers
/// raising a Concern from the record and linking the record to an existing
/// one, so it needs:
///
///   - `ActionsApi`, because raising a Concern from a Non-conformance is a
///     write to the action log and the action log's own routes are where it
///     lives. That is the same decision the backend makes and for the same
///     reason: `quality` may not write the Action log, and an entry point that
///     exposed a write would be the second implementation of the Action log's
///     rules that ADR-0006 forbids. The Screen reaches the record through
///     `ActionsApi` the way Maintenance's forms reach the Org Unit tree
///     through `people.dart`;
///   - `LinkedConcern`'s *vocabulary* — `actionStatusLabel`,
///     `actionStatusTone`, `actionTypeLabel` — because a Concern is an Action
///     and its status is the action log's five words, with the tones this
///     client's shared status vocabulary gives them. A second copy of that map
///     in `lib/quality/` is exactly the drift the seam exists to prevent;
///   - `Action`, the model the raise answers with, so the Screen can name the
///     Concern it just raised.
///
/// `LinkedNonconformance` is exported too, and it is the one export here that
/// is not a consumer's request: it is the row Actions' own Concern read
/// carries from Quality's table, and the Concern Screen (in this Module)
/// renders it. It deliberately has no status vocabulary of its own — see its
/// own doc comment — which is what keeps the dependency between the two client
/// Modules running one way only: `quality` imports `actions`, and `actions`
/// imports nothing of `quality`.
///
/// The Safety Module's incident detail Screen (issue #229) is the second
/// consumer, for the same reasons as Quality's: raising a Concern from a
/// Safety incident is a write to the action log, so it needs `ActionsApi` and
/// the vocabulary `Action`'s status carries. `LinkedSafetyIncident` is
/// exported for the same reason `LinkedNonconformance` is — it is the row
/// Actions' own Concern read carries from Safety's table, and `safety`'s own
/// Screens render it, keeping the dependency running one way: `quality` and
/// `safety` each import `actions`, and `actions` imports neither.
///
/// `lib/platform/` is not a cross-Module consumer and does not go through
/// here: it is the mounting layer, the same special case `src/index.js` is for
/// a Module's `router` on the server.
library;

export 'action.dart'
    show
        Action,
        ActionParent,
        ActionPhase,
        ActionType,
        LinkedNonconformance,
        LinkedSafetyIncident,
        actionPriorityLabels,
        actionStatusLabel,
        actionStatusTone,
        actionTypeLabel;
export 'actions_api.dart' show ActionsApi, ActionsApiException;
