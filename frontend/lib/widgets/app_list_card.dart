/// The one card a catalogue's rows sit in (issue #189).
///
/// **What it is for.** Six catalogues — job roles, skills, skill coverage, the
/// parts catalogue, stores and store stock — each rendered their whole list
/// inside one `Card` whose children were plain `Padding`s. With no rule between
/// them and no pointer feedback, six records of `name · code` and an action
/// arrived as six lines of undifferentiated white: the eye had no edge to
/// follow across the page and nothing tied a row's left-hand text to its
/// right-hand action. This widget draws that edge — a hairline of the app's own
/// border colour **between** rows, never above the first nor below the last, so
/// a one-row catalogue has no stray rule and an `n`-row one has `n-1` of them.
///
/// **It adds nothing else, on purpose.** No padding of its own, no header band,
/// no scrolling, no hover band, no row height. Each row keeps its own `Padding`
/// and — critically — its own `Key`, which is why this widget *inserts* dividers
/// between the children it is handed rather than wrapping each child in a row of
/// its own: a wrapping implementation would push every `rowKey` one level down
/// the tree and break every test that finds one, for no visual gain.
///
/// **A catalogue row is not tappable, so there is no hover fill.** The
/// `AppComponentColors.rowHoverFill` token exists for the Work orders table's
/// tappable rows (issue #168), where the pointer's position is what ties an ID
/// at the left edge to an action at the right. A catalogue row's affordances are
/// its own buttons; a hover band would advertise a click that does nothing. Do
/// not "complete" this widget by adding one.
///
/// **The divider is the palette's hairline, not a new colour.** `AppColors.edge`
/// is the same value `AppComponentColors.cardBorder` binds as the card's own
/// rim, so a row's rule and its card's edge are the same weight in the same
/// family — and no `Color` literal is written here, which
/// `theme_skeleton_test.dart` enforces across `lib/`.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppListCard extends StatelessWidget {
  const AppListCard({super.key, required this.rows});

  /// The rows, in the order they are read. Every one of them keeps its own
  /// padding and its own `Key` — this widget only puts a rule between them.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 1, thickness: 1, color: AppColors.edge),
            rows[index],
          ],
        ],
      ),
    );
  }
}
