/// One register row with a block of prose one press beneath it.
///
/// **Why it exists.** A Job plan carries its steps and a PM schedule its rules
/// (`Rolls from…`, `Raised N days early`, `Accumulated…`). Neither is a value a
/// reader compares down a column, and neither may be dropped. Spent as columns
/// they would turn a register of one comparable shape into a wall of sentences;
/// dropped they would lose what the record says. So the register keeps its one
/// shape (a name, the few things that compare, the act) and the record's prose is
/// one press away, under the row it belongs to. Nothing is lost, and nothing
/// competes with the columns until it is asked for.
///
/// **How it composes with `AppTableRow`.** The toggle has to sit in one of the
/// row's cells while the block sits *beneath the whole row*, and `AppTableRow`
/// owns its own hairline and tap target, so the block cannot be a cell. The
/// widget therefore builds the row itself: [rowBuilder] is handed the toggle and
/// returns the row (an `AppTableRow` whose cells include that toggle), and this
/// widget stacks the block under it. The block is indented by `Spacing.md`, the
/// row's own horizontal padding, so it starts at the first cell's edge.
///
/// **It owns its own state and nothing else.** Collapsed by default; whether it
/// is open is a view concern no Bloc needs to know. Key each instance by its
/// record's id so the state follows the record when the list rebuilds on a
/// filter keystroke or a Bloc update. It imports no Bloc and makes no request.
///
/// **An open row survives scrolling.** Rows sit in a `ListView`, which disposes
/// children scrolled past its cache; an open row asks to be kept alive, so it is
/// still open when the reader scrolls back.
///
/// **Access and motion.** The toggle is at least [AppTouchTarget.min] in both
/// directions, carries a tooltip and a `Semantics` label (and says whether it is
/// expanded), and the chevron turns over at most [RowDisclosure.motion] — or not at all when
/// the reader has asked the platform to reduce motion.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class RowDisclosure extends StatefulWidget {
  const RowDisclosure({
    super.key,
    required this.toggleKey,
    required this.label,
    required this.rowBuilder,
    required this.child,
  });

  /// The key of the toggle, which the caller names so a test can press it.
  final ValueKey<String> toggleKey;

  /// What is behind the toggle, in the caller's words: `3 steps`, `3 rules`.
  final String label;

  /// Builds the row, given the toggle to place in one of its cells.
  final Widget Function(BuildContext context, Widget toggle) rowBuilder;

  /// The block shown beneath the row while expanded.
  final Widget child;

  /// The longest the chevron and the block take to move.
  static const Duration motion = Duration(milliseconds: 160);

  @override
  State<RowDisclosure> createState() => _RowDisclosureState();
}

class _RowDisclosureState extends State<RowDisclosure> with AutomaticKeepAliveClientMixin {
  bool _expanded = false;

  /// An open row stays alive when a `ListView` scrolls it past its cache, so it
  /// is still open when the reader scrolls back; a closed one has nothing to keep.
  @override
  bool get wantKeepAlive => _expanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : RowDisclosure.motion;
    final palette = AppColors.of(context);
    final tooltip = _expanded ? 'Hide ${widget.label}' : 'Show ${widget.label}';

    final toggle = Semantics(
      button: true,
      expanded: _expanded,
      label: tooltip,
      excludeSemantics: true,
      // The same toggle the `InkWell` runs: `excludeSemantics` drops the
      // `InkWell`'s own tap action, so without this a screen reader would be
      // handed a button it cannot press.
      onTap: _toggle,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          key: widget.toggleKey,
          onTap: _toggle,
          hoverColor: palette.rowHoverFill,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppTouchTarget.min,
              minHeight: AppTouchTarget.min,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: duration,
                  child: Icon(Icons.expand_more, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.rowBuilder(context, toggle),
        AnimatedSize(
          duration: duration,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.sm,
                    Spacing.md,
                    Spacing.md,
                  ),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
