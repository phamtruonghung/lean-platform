/// One titled card on a detail Screen: a title with an optional action at its
/// far end, a hairline, and the section's own rows beneath.
///
/// **What it is, and what it is not.** A detail Screen opens with a summary card
/// that is the caller's own (the record's identifying fields); this is one
/// *section* of the page below it. It is not a Destination group: `CONTEXT.md`'s
/// `_Avoid_: Section` is about the Shell's own heading in the sidebar, and the
/// name here comes from the primitive and means something else.
///
/// **The title is `titleMedium` (16), not `headlineSmall` (18).** A section is
/// not the page: the Screen's title already spends the 18, and a section title
/// that large would flatten the page into a stack of equal headings. It earns
/// its place with w600 in `textPrimary` (10.36:1 light, 13.35:1 dark on a card)
/// and is a header to a screen reader.
///
/// **The column stretches.** A `Card`'s `Column` defaults to centring, and a row
/// that sizes to its own content then floats to the middle of the card
/// (`AppListCard` records that bug, #193). The alignment is stated, and
/// `layout_rules_test.dart` fails a `Card` whose direct `Column` does not state
/// one.
///
/// **The hairline under the title is the palette's `edge`**, the same line a
/// register row carries, so a detail page and a register read at one weight. It
/// spans the card edge to edge; the title and the rows are inset by the same
/// `Spacing.lg`, so they share one left edge.
///
/// **It owns no width.** Two of them side by side, equal in height, are
/// `AppSectionGrid`'s job, not this widget's.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppDetailSection extends StatelessWidget {
  const AppDetailSection({
    super.key,
    required this.title,
    this.trailing,
    this.children = const <Widget>[],
  });

  final String title;

  /// One action at the far end of the title row.
  final Widget? trailing;

  /// The section's rows, `Spacing.sm` apart.
  final List<Widget> children;

  static ValueKey<String> titleKey(String title) => ValueKey<String>('app-detail-section-title-$title');

  static const ValueKey<String> dividerKey = ValueKey<String>('app-detail-section-divider');
  static const ValueKey<String> bodyKey = ValueKey<String>('app-detail-section-body');

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    container: true,
                    child: Text(
                      title,
                      key: titleKey(title),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(key: dividerKey, height: 1, thickness: 1, color: palette.edge),
          if (children.isNotEmpty)
            Padding(
              key: bodyKey,
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: Spacing.sm),
                    children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
