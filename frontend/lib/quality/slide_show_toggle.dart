/// Choose this issue for the Site's slide show (issue #418).
///
/// **One widget, two sizes.** A register row gets the compact form — an icon
/// control beside "Open" — because a seven-column table has no room for a
/// labelled switch and the choice is a single bit; a detail Screen gets the
/// labelled form, because there the question ("is this on the wall?") is worth
/// the sentence. Both dispatch the same event to the same Bloc, so the two
/// answers can never disagree.
///
/// **It says which state it is in, and why it might be off-limits.** Chosen is a
/// filled icon and a `switched on` semantics state, not merely a colour, so it
/// reads at a glance and to a screen reader. A caller with no write Grant sees
/// the state and not the control — the same asymmetry the register's row
/// actions follow, and the reason [canWrite] exists rather than a disabled
/// button nobody can explain.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class SlideShowToggle extends StatelessWidget {
  const SlideShowToggle({
    super.key,
    required this.inSlideShow,
    required this.onChanged,
    this.busy = false,
    this.canWrite = true,
    this.expanded = false,
  });

  /// Whether the issue is on the Site's slide show right now.
  final bool inSlideShow;

  /// Called with the state the caller wants next.
  final ValueChanged<bool> onChanged;

  /// A request for this row is in flight: the control shows it and refuses
  /// another tap until it lands.
  final bool busy;

  /// False renders the state only (a reader's view).
  final bool canWrite;

  /// The labelled form, for a detail Screen.
  final bool expanded;

  static const String onTooltip = 'On the slide show — take it off';
  static const String offTooltip = 'Put this issue on the slide show';

  @override
  Widget build(BuildContext context) {
    if (!canWrite) {
      if (!expanded) return const SizedBox.shrink();
      return Text(
        inSlideShow ? 'On the slide show' : 'Not on the slide show',
        style: AppTypography.dense(context)?.copyWith(color: AppColors.of(context).textMuted),
      );
    }

    if (busy) {
      return SizedBox(
        width: expanded ? null : AppTouchTarget.min,
        height: AppTouchTarget.min,
        child: const Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (!expanded) {
      return IconButton(
        // The caller's own key sits on this widget (see the class doc); the
        // button takes none of its own, or `find.byKey` would match two
        // elements for one control.
        tooltip: inSlideShow ? onTooltip : offTooltip,
        onPressed: () => onChanged(!inSlideShow),
        icon: Icon(inSlideShow ? Icons.slideshow : Icons.slideshow_outlined),
        isSelected: inSlideShow,
        selectedIcon: const Icon(Icons.slideshow),
        style: IconButton.styleFrom(
          minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
        ),
      );
    }

    return SwitchListTile(
      // No key of its own: the caller's is on this widget already.
      value: inSlideShow,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(
        inSlideShow ? 'On the slide show' : 'Not on the slide show',
        style: AppTypography.body(context),
      ),
      subtitle: const Text(
        'Chosen issues play in the Quality slide show, one picture at a time.',
      ),
    );
  }
}
