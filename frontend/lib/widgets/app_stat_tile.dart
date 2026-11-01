/// One stat tile: an optional icon tile, a label, a figure and a line of
/// context, and, when it is given somewhere to go, a link.
///
/// **It is `home_screen.dart`'s private tile, lifted** so that a second Module
/// can spend it. Home does not adopt it in this card: the private `_HomeCard`
/// survives until its own slice, which is why the two shapes are temporarily
/// byte-similar. Keeping both for one card is deliberate, because it makes the
/// Home change a single reviewable diff with its own golden rather than a side
/// effect of introducing a primitive.
///
/// **[onTap] rather than a route string.** The tile is a presentation widget and
/// its caller owns the navigation; that is what makes it testable without a
/// router. A null [onTap] means the tile is not a link at all: no `InkWell`, no
/// hover, no chevron, so nothing advertises a click that is not there.
///
/// **[figure] is a `String`, not an `int`.** Formatting a number is the caller's
/// business. A tile that took an `int` would have to decide about thousands
/// separators, which is a domain question (and a locale one), not a layout one.
///
/// **Its shape** is the Home tile's: an icon row (a 40px rounded square in the
/// navigation's selected pair, then a chevron at the far end), `Spacing.md`,
/// the label in `dense` / `textMuted`, `Spacing.xs`, the figure, `Spacing.xs`,
/// the caption. Text is stacked under the icon rather than beside it so the
/// text's left edge is the tile's own padding edge. The figure is `headlineLarge`
/// at w700 when there is something to read, and a quiet `titleMedium` at w400 in
/// `textMuted` when [quiet] (a zero): measured 7.58:1 light and 9.85:1 dark on a
/// card.
///
/// **Keyboard focus is a ring drawn by swapping the card's `shape`**, 2px of
/// `focusRing`, only under `FocusHighlightMode.traditional` so a click leaves no
/// ring behind. Swapping a shape moves no pixel of layout, which matters on a
/// row of equal-height tiles; a border added around the content would grow the
/// focused tile and not its neighbours. That is why this widget is stateful.
///
/// **Motion** is the one 200ms hover fade, `Duration.zero` under
/// `MediaQuery.disableAnimationsOf`. The ink ripple is off (`NoSplash`) because
/// it runs far longer than that and ignores the setting.
///
/// **The chevron is decorative** and wrapped in `ExcludeSemantics`: the tile is
/// already one link, so announcing an arrow as well is noise.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppStatTile extends StatefulWidget {
  const AppStatTile({
    super.key,
    required this.label,
    required this.figure,
    this.caption,
    this.icon,
    this.onTap,
    this.quiet = false,
  });

  /// The eyebrow, e.g. "Open work".
  final String label;

  /// The number, already formatted by the caller.
  final String figure;

  /// A line of context, e.g. "3 need assigning".
  final String? caption;

  /// The 40x40 icon tile. Omitted, the tile is text only.
  final IconData? icon;

  /// Where the tile goes. Null means it is not a link.
  final VoidCallback? onTap;

  /// A zero figure: quieter, at regular weight.
  final bool quiet;

  /// The icon tile's side, and its corner radius. No `AppRadius` token suits a
  /// 40px square (`card`'s 14 is proportioned for a whole card).
  static const double iconTileSize = 40;
  static const double iconTileRadius = 10;

  static const ValueKey<String> iconTileKey = ValueKey<String>('app-stat-tile-icon');
  static const ValueKey<String> chevronKey = ValueKey<String>('app-stat-tile-chevron');
  static const ValueKey<String> labelKey = ValueKey<String>('app-stat-tile-label');
  static const ValueKey<String> figureKey = ValueKey<String>('app-stat-tile-figure');
  static const ValueKey<String> captionKey = ValueKey<String>('app-stat-tile-caption');

  @override
  State<AppStatTile> createState() => _AppStatTileState();
}

class _AppStatTileState extends State<AppStatTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final muted = AppTypography.dense(context)?.copyWith(color: palette.textMuted);
    final figureStyle = widget.quiet
        ? textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400, color: palette.textMuted)
        : textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700);
    final linked = widget.onTap != null;
    final showRing =
        _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    final content = Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.icon != null || linked) ...[
            Row(
              children: [
                if (widget.icon != null)
                  Container(
                    key: AppStatTile.iconTileKey,
                    width: AppStatTile.iconTileSize,
                    height: AppStatTile.iconTileSize,
                    decoration: BoxDecoration(
                      color: palette.navSelectedBackground,
                      borderRadius: BorderRadius.circular(AppStatTile.iconTileRadius),
                    ),
                    child: Icon(widget.icon, color: palette.navSelectedForeground),
                  ),
                const Spacer(),
                if (linked)
                  ExcludeSemantics(
                    child: Icon(Icons.chevron_right, key: AppStatTile.chevronKey, color: palette.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
          ],
          Text(widget.label, key: AppStatTile.labelKey, style: muted),
          const SizedBox(height: Spacing.xs),
          Text(widget.figure, key: AppStatTile.figureKey, style: figureStyle),
          if (widget.caption != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(widget.caption!, key: AppStatTile.captionKey, style: muted),
          ],
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      // Null leaves the theme's hairline shape in force.
      shape: showRing
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: palette.focusRing, width: 2),
            )
          : null,
      child: linked
          ? InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(AppRadius.card),
              hoverColor: palette.rowHoverFill,
              splashFactory: NoSplash.splashFactory,
              hoverDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: content,
            )
          : content,
    );
  }
}
