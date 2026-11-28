/// The header every register Screen shares: a title, an optional description,
/// the Screen's actions at the row's far end, a hairline under the lot, and
/// whatever filters sit beneath it.
///
/// **Why it exists.** Twenty-odd Screens each hand-rolled a private `_Header`
/// that drew the same title, the same muted description and the same row of
/// buttons slightly differently, so the pages did not read as one product. Home
/// (issue #375) set the shape: a `headlineSmall` title at w700 that is a real
/// header to a screen reader, a muted description, and a `cardBorder` hairline
/// under it. This is that shape, once.
///
/// **What it does not own.** No padding, no `Center`, no [AppPageFrame]. The
/// call site keeps its frame and its `Spacing.lg` / `Spacing.xl` inset, because
/// `page_alignment_test.dart` pins that inset per page and no page's left edge
/// may move. The hairline therefore spans the call site's content box, from the
/// title's own left edge.
///
/// **Actions wrap by the box, not the window.** When the box this header is
/// given is narrower than [wrapBreakpoint], scaled by the reader's text size,
/// the actions drop under the title instead of squeezing it. The width is read
/// off a `LayoutBuilder`, never `MediaQuery`: a Screen renders inside the
/// Shell's content area, and the window is the wrong width to ask about (the
/// lesson of `WorkOrdersScreen.narrowBreakpoint`). `MediaQuery` supplies only
/// the text scale: the actions row grows with it and the box does not, so at a
/// larger text size the same box needs the wrap sooner (WCAG 1.4.4, Resize
/// Text). The actions also drop under the title when, above the breakpoint,
/// they are still too wide to share the title's row: the title keeps at least
/// [AppPageHeader.minTitleWidth], else they wrap.
///
/// **[below]** is the Screen's filter row (site dropdown, chips, toggles). It
/// sits under the hairline, [Spacing.md] beneath it, so every Screen spaces its
/// filters from the rule the same way.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/notices.dart';
import '../theme.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
    this.below,
  });

  final String title;
  final String? description;

  /// Buttons for the row's far end. Wrapped under the title when the box is
  /// narrower than [wrapBreakpoint] at the reader's text scale.
  final List<Widget> actions;

  /// A filter row beneath the hairline.
  final Widget? below;

  /// The widest a description may run, however wide the box.
  static const double descriptionMeasure = 640;

  /// Below this box width, at a text scale of 1, the actions wrap under the
  /// title. The breakpoint is multiplied by the reader's text-scale factor
  /// (never reduced below 1): the actions row grows with the scale and the box
  /// does not (WCAG 1.4.4).
  ///
  /// Wide enough is not enough on its own: a Screen with several actions can
  /// have a row wider than the box even above the breakpoint. The header also
  /// wraps when the actions, at their natural width, would leave the title
  /// less than [minTitleWidth] on its row, that is when
  /// `actionsWidth + Spacing.md > boxWidth - minTitleWidth`. The actions are
  /// measured by laying the one-row layout out, so no action widget is built
  /// twice. A header whose actions fit lays out exactly as it always did.
  static const double wrapBreakpoint = 560;

  /// The least width the title keeps on a one-row header. About sixteen
  /// characters of `headlineSmall`: enough for a register's title on one line
  /// ("Assessments" is roughly 150px), so the actions never squeeze it into a
  /// sliver before the header gives up and wraps them.
  static const double minTitleWidth = 200;

  static const ValueKey<String> titleKey = ValueKey<String>('app-page-header-title');
  static const ValueKey<String> descriptionKey = ValueKey<String>('app-page-header-description');
  static const ValueKey<String> actionsKey = ValueKey<String>('app-page-header-actions');
  static const ValueKey<String> ruleKey = ValueKey<String>('app-page-header-rule');
  static const ValueKey<String> belowKey = ValueKey<String>('app-page-header-below');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            key: titleKey,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: Spacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: descriptionMeasure),
            child: Text(
              // A page header's description is a render boundary too: a
              // Bloc-held code is resolved here, prose passes through
              // unchanged (ADR-0062).
              noticeTextFor(context, description!),
              key: descriptionKey,
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ],
    );

    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions.isEmpty)
          titleBlock
        else
          _AdaptiveHeaderRow(
            breakpoint: wrapBreakpoint * (textScale < 1 ? 1 : textScale),
            actionCount: actions.length,
            builder: (wrapped) {
              if (wrapped) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: Spacing.sm),
                    Wrap(
                      key: actionsKey,
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: actions,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: Spacing.md),
                  Row(
                    key: actionsKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: Spacing.sm),
                        actions[i],
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: Spacing.md),
        // A `Divider` spans the content box, so it starts at the title's own
        // left edge.
        Divider(key: ruleKey, height: 1, thickness: 1, color: palette.cardBorder),
        if (below != null) ...[
          const SizedBox(height: Spacing.md),
          KeyedSubtree(key: belowKey, child: below!),
        ],
      ],
    );
  }
}

/// Builds the header's title row, one-row or wrapped, choosing at layout time.
///
/// Like `LayoutBuilder` it builds its child during layout, but it also
/// measures: it builds the last-chosen layout and reads the max intrinsic
/// width of the actions (`AppPageHeader.actionsKey`). If the box is under [breakpoint],
/// or the actions leave the title less than `AppPageHeader.minTitleWidth`, it
/// rebuilds the wrapped layout. Nothing is built twice in the final tree; an
/// action that cannot report an intrinsic width leaves the one-row layout be.
class _AdaptiveHeaderRow extends RenderObjectWidget {
  const _AdaptiveHeaderRow({
    required this.breakpoint,
    required this.actionCount,
    required this.builder,
  });

  final double breakpoint;
  final int actionCount;
  final Widget Function(bool wrapped) builder;

  @override
  RenderObjectElement createElement() => _AdaptiveHeaderElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAdaptiveHeader(breakpoint);

  @override
  void updateRenderObject(BuildContext context, _RenderAdaptiveHeader renderObject) {
    renderObject.breakpoint = breakpoint;
  }
}

class _AdaptiveHeaderElement extends RenderObjectElement {
  _AdaptiveHeaderElement(_AdaptiveHeaderRow super.widget);

  Element? _child;

  @override
  _RenderAdaptiveHeader get renderObject => super.renderObject as _RenderAdaptiveHeader;

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null) visitor(_child!);
  }

  @override
  void forgetChild(Element child) {
    _child = null;
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.onBuild = _build;
    renderObject.measureActions = _measureActions;
  }

  @override
  void update(_AdaptiveHeaderRow newWidget) {
    super.update(newWidget);
    renderObject.markNeedsLayout();
  }

  @override
  void performRebuild() {
    renderObject.markNeedsLayout();
    super.performRebuild();
  }

  @override
  void unmount() {
    renderObject.onBuild = null;
    renderObject.measureActions = null;
    super.unmount();
  }

  void _build(bool wrapped) {
    owner!.buildScope(this, () {
      _child = updateChild(_child, (widget as _AdaptiveHeaderRow).builder(wrapped), null);
    });
  }

  /// The natural width of the actions row, or null if it cannot be measured.
  double? _measureActions() {
    double? width;
    void visit(Element element) {
      if (width != null) return;
      if (element.widget.key == AppPageHeader.actionsKey) {
        final box = element.renderObject;
        if (box is RenderBox) {
          try {
            width = box.getMaxIntrinsicWidth(double.infinity);
            // RenderWrap's intrinsic width is the children's sum without its
            // spacing; the one-row Row's already includes the gaps.
            if (box is RenderWrap) {
              width = width! + ((widget as _AdaptiveHeaderRow).actionCount - 1) * Spacing.sm;
            }
          } catch (_) {
            // An action that cannot report an intrinsic width: leave the
            // one-row layout as it was rather than guess.
            width = null;
          }
        }
        return;
      }
      element.visitChildren(visit);
    }

    visitChildren(visit);
    return width;
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.child = child as RenderBox;
  }

  @override
  void moveRenderObjectChild(RenderObject child, Object? oldSlot, Object? newSlot) {
    assert(false, 'a single child never moves');
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.child = null;
  }
}

class _RenderAdaptiveHeader extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  _RenderAdaptiveHeader(this._breakpoint);

  double _breakpoint;
  set breakpoint(double value) {
    if (value == _breakpoint) return;
    _breakpoint = value;
    markNeedsLayout();
  }

  bool? _wrapped;

  void Function(bool wrapped)? onBuild;
  double? Function()? measureActions;

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    void build(bool wrapped) {
      invokeLayoutCallback<BoxConstraints>((_) => onBuild!(wrapped));
      _wrapped = wrapped;
    }

    // Build what was mounted last time, so a rebuild of an unchanged decision
    // updates the tree in place (focus and State in the actions survive).
    final belowBreakpoint = maxWidth < _breakpoint;
    build(_wrapped ?? belowBreakpoint);
    var wrapped = belowBreakpoint;
    if (!wrapped && maxWidth.isFinite) {
      final actionsWidth = measureActions?.call();
      wrapped = actionsWidth != null &&
          actionsWidth + Spacing.md > maxWidth - AppPageHeader.minTitleWidth;
    }
    if (wrapped != _wrapped) build(wrapped);
    child!.layout(constraints, parentUsesSize: true);
    size = child!.size;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(debugCannotComputeDryLayout(reason: 'the header builds its child during layout'));
    return 0;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(debugCannotComputeDryLayout(reason: 'the header builds its child during layout'));
    return Size.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;
}
