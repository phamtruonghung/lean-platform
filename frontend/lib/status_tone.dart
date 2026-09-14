/// The five meanings a status can carry (issue #168), named for what the
/// meaning IS rather than for the colour that currently paints it.
///
/// This is the vocabulary the whole client shares: a Work order, a Request, a
/// Downtime event and a Work order's own step each map their own wire statuses
/// onto these five, so "On hold" means the same thing on every Screen that
/// shows it (issue #168's own user story 7).
///
/// **Why this is its own file rather than living in `theme.dart`.** `theme.dart`
/// imports `package:flutter/material.dart` — it builds a `ThemeData`. A domain
/// model (`work_order.dart`, `request.dart`, `downtime_event.dart`) needs to
/// name the tone its own status carries, and making that model import the
/// Material layer to do it would put a presentation dependency inside the
/// domain for the sake of one enum. A leaf file with no imports at all keeps
/// the direction of that dependency pointing the way it should: the theme and
/// the models both depend on the vocabulary, and the vocabulary depends on
/// nothing.
///
/// The colour each tone resolves to is a design token, and lives in
/// `theme.dart` (`AppComponentColors.statusFill` / `.statusForeground`) — the
/// only file allowed to name a colour, which `theme_skeleton_test.dart`
/// enforces.
library;

enum StatusTone {
  /// Nothing is being asked of anyone: a draft, a deliberate cancellation, a
  /// Request that was rejected or folded into a duplicate. Painted quietest,
  /// because a decision somebody made on purpose is not a fault.
  neutral,

  /// Live and actionable, or in hand: approved, scheduled, in progress, a
  /// Request being triaged.
  info,

  /// Finished. Completed, closed, a step done.
  success,

  /// The one state that wants a decision from whoever is reading: a Work order
  /// on hold, a Request nobody has triaged yet, an Asset that is down.
  warning,

  /// Something is wrong, or was done wrongly: a step that failed. Reserved for
  /// faults rather than for outcomes — nothing is painted with this because a
  /// person chose it.
  danger,
}
