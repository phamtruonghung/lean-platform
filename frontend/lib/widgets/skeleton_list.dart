import 'package:flutter/material.dart';

import '../theme.dart';

/// A vertical list of card-shaped placeholders shown while a page's first
/// load is in flight.
///
/// Deliberately static — no shimmer or animation. Tests drive the app with
/// `pumpAndSettle`, which only ever settles when every scheduled frame is
/// done, so an endlessly animating skeleton would hang the suite.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 6,
    this.maxWidth = 900,
    this.padding =
        const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
  });

  final int rows;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The same "flat card with a hairline border" the real cards use, so the
    // placeholder reads as their ghost rather than a second layout language.
    final fill = scheme.surfaceContainerHighest;

    // A rounded bar, sized as a fraction of its (bounded) parent. `Align` is
    // what guarantees the fraction is always against a concrete width — a bare
    // FractionallySizedBox in a Row would get an unbounded constraint and
    // overflow.
    Widget bar(double fraction, double height) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppRadius.card / 2),
              ),
            ),
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
          itemBuilder: (_, _) => Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: fill,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(child: bar(0.4, 14)),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  bar(0.6, 11),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
