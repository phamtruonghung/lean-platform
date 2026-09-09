import 'package:flutter/material.dart';

import '../theme.dart';

/// The shared loading state (issue #103): three placeholder shapes —
/// [SkeletonList] (a vertical list, the original and still the most-used),
/// [SkeletonDetail] (one detail record's header and field rows) and
/// [SkeletonGrid] (a card grid) — sharing one file since they share one
/// design language: a flat card with the same hairline the real cards use
/// (`scheme.surfaceContainerHighest` fill, [AppRadius.card] rounding on
/// every bar), so a placeholder always reads as its own content's ghost
/// rather than a second layout language arriving with it.
///
/// Deliberately static — no shimmer or animation, on all three. Tests drive
/// the app with `pumpAndSettle`, which only ever settles when every
/// scheduled frame is done, so an endlessly animating skeleton would hang
/// the suite. [SkeletonList]'s own geometry (the 40px circle, the 14px and
/// 11px bars at 40% and 60% width) is unchanged by #103 — only
/// [SkeletonDetail] and [SkeletonGrid] are new.
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

/// A rounded placeholder bar, sized as a fraction of its (bounded) parent —
/// the same shape [SkeletonList]'s own private `bar` builds, lifted out so
/// [SkeletonDetail] and [SkeletonGrid] below share it rather than each
/// re-deriving the same `Align`-inside-`FractionallySizedBox` shape (issue
/// #103). `Align` is what guarantees the fraction is always against a
/// concrete width — a bare `FractionallySizedBox` in a `Row` would get an
/// unbounded constraint and overflow.
Widget _skeletonBar(Color fill, double fraction, double height) => Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        child: Container(
          height: height,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.card / 2)),
        ),
      ),
    );

/// One detail Screen's own first load: an avatar-and-title header — the
/// shape `EmployeeDetailScreen`'s own header already draws — followed by
/// [fieldRows] label-then-value pairs (issue #103). Generalises
/// [SkeletonList] beyond a list, per this file's own header, rather than
/// leaving every future detail Screen (#77's floor-facing surface among
/// them) to invent its own placeholder shape the way `SkillCoverageScreen`
/// and `JobRolesScreen` used to fall back to a bare `CircularProgressIndicator`
/// before #103.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({super.key, this.fieldRows = 4, this.maxWidth = 900});

  final int fieldRows;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double fraction, double height) => _skeletonBar(fill, fraction, height);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(0.5, 18),
                            const SizedBox(height: Spacing.sm),
                            bar(0.3, 13),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xl),
                  for (var i = 0; i < fieldRows; i++) ...[
                    if (i > 0) const SizedBox(height: Spacing.md),
                    bar(0.25, 11),
                    const SizedBox(height: Spacing.xxs),
                    bar(0.7, 14),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card grid's own first load (issue #103) — [tiles] flat cards over
/// [crossAxisCount] columns, each carrying the same two-bar shape
/// [SkeletonList]'s own row uses for its text, without that row's avatar:
/// a grid tile is typically narrower than a list row and a 40px circle
/// competes with the two bars for the space rather than leaving room for
/// them.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.tiles = 6, this.crossAxisCount = 3, this.maxWidth = 900});

  final int tiles;
  final int crossAxisCount;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double fraction, double height) => _skeletonBar(fill, fraction, height);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: Spacing.sm,
            crossAxisSpacing: Spacing.sm,
            childAspectRatio: 1.4,
          ),
          itemCount: tiles,
          itemBuilder: (_, _) => Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  bar(0.6, 14),
                  const SizedBox(height: Spacing.sm),
                  bar(0.4, 11),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
