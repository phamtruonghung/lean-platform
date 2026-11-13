/// The Shell: the persistent chrome around every Screen an admitted Account
/// can reach (CONTEXT.md's Shell).
///
/// Ported from `employee-management`'s `lib/src/app_shell.dart` — the collapse
/// behaviour, the 260/64 widths and the 700px rail breakpoint come across
/// unchanged. Two things deliberately do not: the sidebar renders its content
/// from `go_router`'s child rather than from a per-destination builder, so the
/// browser's history and back button work; and the predecessor's indigo
/// gradient is left behind for this Platform's own theme (theme.dart).
///
/// **The keyboard** (issue #401). The Shell carries the halves of the app's
/// focus policy that belong to chrome: a skip-to-content control drawn ahead of
/// everything (invisible until it takes focus, and out of the pointer's way with
/// `IgnorePointer`), and a Destination that wears the same 2px `focusRing` as
/// every other control and announces itself as `selected` when it is the current
/// one.
///
/// **The Shell owns the chrome's tab order, and that is a measured decision, not
/// a preference.** A Screen is a `Navigator` route of its own, so its controls
/// live in a scope the sidebar is not part of; the framework's reading-order
/// policy is what would have to bridge the two, and in this composition it
/// cannot. Measured on `/work-orders` at 1280x1000 in the pinned image: the
/// policy sorts the sidebar's *off-screen* items after the page (a
/// `SingleChildScrollView` lays every item out, so items below the fold have
/// `y > 1000` and sort behind a page that occupies `y 0..1000`), which interleaves
/// the Destinations with the page's own controls — `Meters`, `Job plans` and the
/// rest came *after* `work-order-actions-101`. Sixteen `Tab` presses never left
/// the register; from the skip control the framework bounced between it and
/// `Home`.
///
/// So `_onTraversalKey` walks one chain the Shell itself can name — the skip
/// control, every control the sidebar draws in build order, then the Screen's
/// own stops — and hands every other press straight back to the framework
/// (`KeyEventResult.ignored`), which is why the ring, the highlight mode and a
/// dialog's trap are untouched. The order it walks is the order the widgets are
/// built, which is the order a reader sees, and it is independent of scroll
/// position and of the framework's geometry heuristics.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../l10n/destination_labels.dart';
import '../people_api.dart';
import '../theme.dart';
import '../widgets/app_focus_ring.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/palette_toggle.dart';
import 'change_password_dialog.dart';
import 'destinations.dart';

class PlatformShell extends StatefulWidget {
  const PlatformShell({
    super.key,
    required this.destinations,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.account,
    required this.onSignOut,
    required this.darkPalette,
    required this.onToggleDarkPalette,
    required this.child,
  });

  /// Already filtered by role: the Shell offers what it is handed and gates
  /// nothing itself.
  final List<Destination> destinations;

  /// The address on screen, so the current destination can be marked.
  final String currentLocation;
  final ValueChanged<Destination> onDestinationSelected;

  final AccountActive account;
  final VoidCallback onSignOut;

  /// Whether the dark palette is the one on screen, so the account menu's
  /// `Dark palette` item can show a check mark (issue #366). A value and a
  /// callback rather than the cubit itself, so the Shell is pumped in a test
  /// with no provider.
  final bool darkPalette;

  /// Switches to the other palette. The Shell decides nothing about which.
  final VoidCallback onToggleDarkPalette;

  /// The Screen the sidebar wraps.
  final Widget child;

  /// Below this width the labels cost more than they are worth, and the
  /// sidebar becomes an icon rail.
  static const double railBreakpoint = 700;
  static const double expandedWidth = 260;

  /// The width of the bar drawn beside the selected Destination (issue #168)
  /// — narrow enough to read as a mark rather than a second border, wide
  /// enough to survive a scaled-down display. Its gutter is reserved on every
  /// Destination so selection never moves a label.
  static const double _selectedMarkWidth = 3;
  static const double collapsedWidth = 64;

  static const ValueKey<String> sidebarKey = ValueKey<String>('platform-shell-sidebar');

  /// The account footer's menu (issue #270) — the avatar, and the name beside
  /// it where there is room — and the one entry in it.
  static const ValueKey<String> accountMenuKey = ValueKey<String>('platform-shell-account-menu');

  /// The build's version in the account footer (issue #297). Drawn only on the
  /// expanded sidebar; the 64px rail has no room for it.
  static const ValueKey<String> appVersionKey = ValueKey<String>('platform-shell-app-version');
  static const ValueKey<String> changePasswordKey =
      ValueKey<String>('platform-shell-change-password');

  /// The account menu's `Dark palette` item (issue #366), and — since issue
  /// #415 — the same switch drawn beside sign-out through
  /// `PaletteToggle.buttonKey`.
  static const ValueKey<String> themeToggleKey =
      ValueKey<String>('platform-shell-theme-toggle');

  /// The skip-to-content control (issue #401): drawn ahead of the sidebar in
  /// reading order, invisible until it takes focus, and the one control that
  /// moves the reader past the Destinations in a single press.
  static const ValueKey<String> skipToContentKey =
      ValueKey<String>('platform-shell-skip-to-content');

  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  /// The Screen's own box. A **scope**, not a plain node: a Screen is a
  /// `Navigator` route of its own, so its focus nodes attach to the nearest
  /// enclosing *scope* and would otherwise be siblings of the sidebar rather
  /// than children of this box. `skipTraversal` because the box itself is not a
  /// stop — it is the fallback for a Screen with nothing focusable in it.
  final FocusScopeNode _content = FocusScopeNode(
    debugLabel: 'platform shell content',
    skipTraversal: true,
  );

  /// The skip control's own node. The Shell has to be able to *land* the reader
  /// on it when the Screen's run ends, and a Material button keeps its node
  /// private to its state otherwise.
  final FocusNode _skipFocus = FocusNode(debugLabel: 'platform shell skip');

  /// The sidebar's element. The chrome's stops are read off the focus tree in
  /// the order the widgets are built — the Destinations in their groups' order,
  /// then the account footer — and this is what tells the tree's nodes apart
  /// from the Screen's.
  final GlobalKey _sidebarAnchor = GlobalKey(debugLabel: 'platform shell sidebar anchor');

  /// A node a keyboard can stop on. Scopes are structure, not controls, and a
  /// control that refuses or skips traversal is not a stop either.
  static bool _isStop(FocusNode node) =>
      node is! FocusScopeNode && node.canRequestFocus && !node.skipTraversal;

  /// Whether [node] is a *control*, rather than the scroll view it sits in: the
  /// sidebar's `SingleChildScrollView` carries a focus node of its own, and
  /// stopping on it would be a stop with nothing to read. Read as "an ancestor
  /// inside the sidebar is an ink response or a button", which is true of every
  /// Destination and of the footer's controls and false of the viewport.
  static bool _isControlInside(FocusNode node, Element anchor) {
    final context = node.context;
    if (context is! Element) return false;
    var control = false;
    var reachedAnchor = false;
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor, anchor)) {
        reachedAnchor = true;
        return false;
      }
      final widget = ancestor.widget;
      if (widget is InkResponse ||
          widget is InkWell ||
          widget is IconButton ||
          widget is TextButton ||
          widget is PopupMenuButton ||
          widget is EditableText) {
        control = true;
      }
      return true;
    });
    return control && reachedAnchor;
  }

  /// Every stop the chrome draws, in build order: the skip control first, then
  /// the Destinations, then the account footer.
  List<FocusNode> _chromeStops() {
    final stops = <FocusNode>[_skipFocus];
    final anchor = _sidebarAnchor.currentContext;
    if (anchor is Element) {
      stops.addAll(
        FocusScope.of(context)
            .traversalDescendants
            .where(_isStop)
            .where((node) => _isControlInside(node, anchor)),
      );
    }
    return stops;
  }

  /// Every stop the Screen beneath offers, in the order `Tab` meets them.
  ///
  /// Sorted by the app's own traversal policy, not read off the tree: inside a
  /// Screen the geometry is coherent (a page is one scroll area), and the
  /// policy's order is the order a reader already walks. It is only across the
  /// sidebar/page seam that the policy's geometry stops being trustworthy —
  /// which is the whole reason this file walks the chrome itself.
  List<FocusNode> _pageStops() {
    final stops = _content.traversalDescendants.where(_isStop).toList();
    final current = FocusManager.instance.primaryFocus;
    if (stops.isEmpty || current == null) return stops;
    return _ScreenOrder().stopsOf(stops, current);
  }

  /// Moves focus to [target] once the current frame is done.
  ///
  /// Not immediate: the request is made from inside a key handler, and the
  /// sidebar's scroll-follow lays the newly focused item out on the same frame,
  /// so a mid-event request loses the race and lands on alternate presses only
  /// (measured). After the frame it landed on every press.
  void _moveTo(FocusNode target) {
    WidgetsBinding.instance.addPostFrameCallback((_) => target.requestFocus());
  }

  /// One `Tab` at a time, across the seam the framework cannot cross.
  ///
  /// The chrome's stops and the Screen's stops are two runs, and this joins
  /// them: the last chrome control hands over to the Screen's first control, the
  /// Screen's last hands over to the skip control, and each end also works
  /// backwards. A press that is not at a seam is `ignored`, so the framework
  /// keeps doing what it already does well — the order *inside* a Screen, the
  /// dialog trap, `Shift+Tab` within a run.
  KeyEventResult _onTraversalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final backward = HardwareKeyboard.instance.isShiftPressed;
    final chrome = _chromeStops();
    final page = _pageStops();
    if (chrome.isEmpty) return KeyEventResult.ignored;

    final chromeIndex = chrome.indexOf(primary);
    if (chromeIndex >= 0) {
      final target = backward ? chromeIndex - 1 : chromeIndex + 1;
      if (target >= 0 && target < chrome.length) {
        _moveTo(chrome[target]);
        return KeyEventResult.handled;
      }
      // Off the end of the chrome: back into the Screen, at the end the reader
      // is heading towards.
      if (page.isEmpty) return KeyEventResult.ignored;
      _moveTo(backward ? page.last : page.first);
      return KeyEventResult.handled;
    }

    if (page.isEmpty) return KeyEventResult.ignored;
    final pageIndex = page.indexOf(primary);
    if (pageIndex < 0) return KeyEventResult.ignored;
    if (!backward && pageIndex == page.length - 1) {
      _moveTo(_skipFocus);
      return KeyEventResult.handled;
    }
    if (backward && pageIndex == 0) {
      _moveTo(chrome.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _content.dispose();
    _skipFocus.dispose();
    super.dispose();
  }

  /// Moves focus past the sidebar — the whole reason the control exists — onto
  /// the first control the Screen offers, in the order a keyboard would meet it.
  ///
  /// A node the tree lists as focusable can still refuse the focus: asking one
  /// that is not laid out leaves *nothing* focused, which would drop the reader
  /// out of the app rather than into the page. So each candidate is tried and
  /// the landing is checked, and the Screen's own box is the fallback for a page
  /// with nothing focusable in it at all.
  void _skipToContent() {
    for (final node in _pageStops()) {
      node.requestFocus();
      if (identical(FocusManager.instance.primaryFocus, node)) return;
    }
    _content.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = MediaQuery.sizeOf(context).width < PlatformShell.railBreakpoint;

    return Scaffold(
      body: Focus(
        // An observer of the seam, not a stop: it watches `Tab` on its way up
        // from whatever has focus, and only acts where the chrome and the
        // Screen meet.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onTraversalKey,
        child: Stack(
          // The skip control is the Stack's first child, so it is first in
          // reading order and first in the paint — the place a skip link
          // belongs.
          children: [
            Positioned(
              left: Spacing.md,
              top: Spacing.sm,
              child: _SkipToContent(
                key: PlatformShell.skipToContentKey,
                focusNode: _skipFocus,
                onPressed: _skipToContent,
              ),
            ),
            Row(
              // Stretch, so the sidebar runs the full height of the app rather
              // than only as far as its own contents reach.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  key: _sidebarAnchor,
                  destinations: widget.destinations,
                  currentLocation: widget.currentLocation,
                  onDestinationSelected: widget.onDestinationSelected,
                  collapsed: collapsed,
                  account: widget.account,
                  onSignOut: widget.onSignOut,
                  darkPalette: widget.darkPalette,
                  onToggleDarkPalette: widget.onToggleDarkPalette,
                ),
                Expanded(child: FocusScope(node: _content, child: widget.child)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The skip-to-content control (issue #401): a real button, drawn at the top of
/// the Shell's first column and invisible until it takes focus.
///
/// A web page's skip link is absolutely positioned so it costs the page no
/// layout, and appears when it is focused. This is the same idea: the control
/// sits in a `Stack` beside the Shell's own row, so it takes no space and moves
/// no pixel, and it is drawn at `Opacity` 0 until a keyboard reaches it.
///
/// It is not `Offstage` or `Visibility`: a control that is not in the tree is not
/// a tab stop, and this one exists precisely to be a tab stop. `IgnorePointer`
/// is what keeps it out of the pointer's way in the meantime — an invisible
/// button over the brand mark would otherwise eat a click.
///
/// Its position is also its place in the traversal order: the reading-order
/// policy sorts by where a control is drawn, and this one is at the top-left of
/// everything the Shell draws.
///
/// Its label is the visible text — "Skip to content" — so it needs no semantics
/// of its own, and its height is [AppTouchTarget.min] like every other
/// control's.
class _SkipToContent extends StatefulWidget {
  const _SkipToContent({super.key, required this.onPressed, this.focusNode});

  final VoidCallback onPressed;

  /// The node the Shell lands a reader on when the Screen's run ends. Owned by
  /// the Shell so the crossing has a target it can name; null when the control
  /// is pumped on its own.
  final FocusNode? focusNode;

  @override
  State<_SkipToContent> createState() => _SkipToContentState();
}

class _SkipToContentState extends State<_SkipToContent> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return IgnorePointer(
      ignoring: !_focused,
      child: Focus(
        // An observer, not a stop: the button inside it is the control a
        // keyboard lands on, and this node only watches whether it has focus.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused != _focused) setState(() => _focused = focused);
        },
        child: Opacity(
          opacity: _focused ? 1 : 0,
          child: Material(
            color: palette.canvas,
            elevation: 0,
            borderRadius: BorderRadius.circular(AppRadius.card),
            // The same 2px ring every other focused control wears.
            child: AppFocusRing(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: TextButton.icon(
                focusNode: widget.focusNode,
                onPressed: widget.onPressed,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppTouchTarget.min),
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                ),
                icon: const Icon(Icons.keyboard_tab),
                label: Text(AppLocalizations.of(context).shellSkipToContent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    super.key,
    required this.destinations,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.collapsed,
    required this.account,
    required this.onSignOut,
    required this.darkPalette,
    required this.onToggleDarkPalette,
  });

  final List<Destination> destinations;
  final String currentLocation;
  final ValueChanged<Destination> onDestinationSelected;
  final bool collapsed;
  final AccountActive account;
  final VoidCallback onSignOut;
  final bool darkPalette;
  final VoidCallback onToggleDarkPalette;

  @override
  Widget build(BuildContext context) {
    // Which Destination is current, asked once for the whole sidebar: the most
    // specific match rather than every path-prefix of the address, because the
    // CAPA list lives under the action log's own `/actions` (issue #211).
    final selectedPath = selectedDestinationPath(destinations, currentLocation);
    final palette = AppColors.of(context);
    // The sidebar's own words, in the reader's language (issue t_c68dfd6e).
    // `Destination.label` stays the table's English identity — tests key on
    // it — so the heading and each entry are translated at the point they are
    // drawn, from the address that identifies them.
    final l10n = AppLocalizations.of(context);

    return Container(
      key: PlatformShell.sidebarKey,
      width: collapsed ? PlatformShell.collapsedWidth : PlatformShell.expandedWidth,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(right: BorderSide(color: palette.edge)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Brand(collapsed: collapsed),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Grouped by heading (#100, ADR-0020) rather than a flat
                      // column of every destination. A heading only renders
                      // where the rail has room for text; below the
                      // breakpoint a hairline marks the same boundary
                      // instead, so the grouping survives as rhythm rather
                      // than a truncated label. Never before the very first
                      // group — there is nothing to divide it from.
                      for (final (index, group) in groupDestinations(destinations).indexed) ...[
                        if (index > 0)
                          if (collapsed)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.sm,
                                vertical: Spacing.xs,
                              ),
                              child: Divider(height: 1, color: palette.edge),
                            )
                          else if (group.name != null)
                            _GroupHeading(name: destinationGroupLabel(l10n, group.name!)),
                        for (final destination in group.destinations)
                          _NavItem(
                            destination: destination,
                            selected: destination.path == selectedPath,
                            collapsed: collapsed,
                            onTap: () => onDestinationSelected(destination),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              _AccountFooter(
                account: account,
                collapsed: collapsed,
                onSignOut: onSignOut,
                darkPalette: darkPalette,
                onToggleDarkPalette: onToggleDarkPalette,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 0 : Spacing.lg,
        Spacing.xl,
        collapsed ? 0 : Spacing.lg,
        Spacing.md,
      ),
      child: Row(
        mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(Icons.dashboard_outlined, color: theme.colorScheme.primary),
          if (!collapsed) ...[
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                AppLocalizations.of(context).shellBrand,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A [DestinationGroup]'s heading — a label and nothing more (#100,
/// ADR-0020). It carries no address, cannot be selected, and opens nothing;
/// this is what keeps the reversal of #39's "no destination names a Module"
/// rule honest — giving a heading an address is the exact failure mode
/// ADR-0020's "What this costs" section names to watch for.
///
/// Deliberately quieter than a [_NavItem]: uppercase, letter-spaced and
/// [AppPalette.textMuted], so it reads as a heading over the destinations filed
/// beneath it rather than competing with them — never the word "section",
/// which CONTEXT.md lists under `_Avoid_` for a Destination group. Never
/// rendered into the collapsed rail — see the boundary hairline in
/// `_Sidebar.build` instead.
///
/// **At the Platform's own type floor** (issue #168). This used `labelSmall`
/// — 11px — which is below the floor [AppTypography]'s own doc comment
/// declares ("Nothing in the Platform goes below this": `bodySmall`, 12px).
/// A heading was the wrong place to break that rule: it is the label that
/// organizes everything under it, and it was the smallest type on the
/// surface. `labelMedium` is that floor, and being quieter is now carried by
/// the colour and the letter-spacing alone.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, Spacing.xs),
      child: Text(
        name.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: AppColors.of(context).textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final Destination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The label the reader sees (issue t_c68dfd6e) — English by default, the
    // catalogue's own word once they have chosen another language. The
    // `nav-item-<English label>` key below deliberately keeps the English
    // identity, which is what a test finds.
    final label = destinationLabel(AppLocalizations.of(context), destination);
    // The selected state's fill and foreground are a component binding
    // (issue #102's AppComponentColors) — this exact pairing repeats
    // nowhere else yet, but it is the shape #102 named the token for.
    final foreground =
        selected ? AppColors.of(context).navSelectedForeground : theme.colorScheme.onSurfaceVariant;

    Widget item = InkWell(
      borderRadius: BorderRadius.circular(Spacing.md),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).navSelectedBackground : null,
          borderRadius: BorderRadius.circular(Spacing.md),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : Spacing.md,
          vertical: Spacing.md,
        ),
        child: Row(
          mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            // The selected Destination's own mark (issue #168) — a short bar
            // in the action colour, and the one selected-state cue that is
            // not a colour difference: fill, foreground and weight all
            // already change, and all three are the kind of cue a monochrome
            // display or a low-vision reader loses. Its width is reserved on
            // every Destination, selected or not, so the icons and labels
            // below it never shift sideways as the selection moves.
            //
            // Not drawn on the rail: below [railBreakpoint] the Destination
            // is an icon alone, and there is no room for a mark beside it
            // without moving the icon off centre.
            if (!collapsed) ...[
              SizedBox(
                width: PlatformShell._selectedMarkWidth,
                child: selected
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.of(context).navSelectedAccent,
                          borderRadius: BorderRadius.circular(PlatformShell._selectedMarkWidth / 2),
                        ),
                        child: const SizedBox(height: 20, width: PlatformShell._selectedMarkWidth),
                      )
                    : null,
              ),
              const SizedBox(width: Spacing.sm),
            ],
            Icon(destination.icon, size: 20, color: foreground),
            if (!collapsed) ...[
              const SizedBox(width: Spacing.md),
              Expanded(
                // Wraps rather than ellipsizing on one line (issue #385's sweep):
                // at twice the text a 260px rail leaves ~168px for the label and
                // "Product standard costs" needs 298, so as one line it
                // ellipsized the longer half of the Destination list with no way
                // to read it. Three lines is what the longest label takes at 200%
                // text (word boundaries make it three, not two); the `Tooltip` is
                // the disclosure for anything still longer, the same route
                // `DisclosingText` gives a clipped table cell (hover, long press,
                // and the label read out to assistive technology).
                child: Tooltip(
                  message: label,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // A Destination is a control a keyboard can reach — it has always been an
    // InkWell, so Tab stops on it and Enter activates it — and it now says
    // where the reader is: [AppFocusRing] traces the item's own rounded fill,
    // and the `selected` flag tells a screen reader which one is current. The
    // tint, the weight and the 3px mark are the sighted reader's half of the
    // same fact (issue #401).
    item = AppFocusRing(
      borderRadius: BorderRadius.circular(Spacing.md),
      child: Semantics(container: true, selected: selected, child: item),
    );

    // On the rail the icon is all there is, so the label has to come back as a
    // tooltip or the destination is a guess.
    if (collapsed) item = Tooltip(message: destination.label, child: item);

    return KeyedSubtree(
      key: ValueKey('nav-item-${destination.label}'),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? Spacing.sm : Spacing.md,
          vertical: Spacing.xxs,
        ),
        child: item,
      ),
    );
  }
}

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({
    required this.account,
    required this.collapsed,
    required this.onSignOut,
    required this.darkPalette,
    required this.onToggleDarkPalette,
  });

  final AccountActive account;
  final bool collapsed;
  final VoidCallback onSignOut;
  final bool darkPalette;
  final VoidCallback onToggleDarkPalette;

  static const String _changePasswordValue = 'change-password';
  static const String _themeToggleValue = 'theme-toggle';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final name = account.displayName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      // The one ad hoc `fontSize` the client still carried, routed through
      // the scale instead (issue #102). `dense` is 14/20 against the old
      // hand-written 13 — a pixel wider in a 32px circle, and the last
      // place a Screen sized text by hand.
      child: Text(initial, style: AppTypography.dense(context)),
    );
    // The account menu wraps what is already drawn rather than adding a
    // control beside it, so the footer looks exactly as it did (issue #270).
    Widget menu(Widget child) => PopupMenuButton<String>(
          key: PlatformShell.accountMenuKey,
          tooltip: l10n.shellAccountMenu,
          padding: EdgeInsets.zero,
          onSelected: (value) {
            switch (value) {
              case _changePasswordValue:
                ChangePasswordDialog.open(context);
              case _themeToggleValue:
                onToggleDarkPalette();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              key: PlatformShell.changePasswordKey,
              value: _changePasswordValue,
              child: Text(l10n.shellChangePassword),
            ),
            // One item that switches between the two palettes (issue #366),
            // checked while the dark one is on screen.
            PopupMenuItem<String>(
              key: PlatformShell.themeToggleKey,
              value: _themeToggleValue,
              child: Row(
                children: [
                  Expanded(child: Text(l10n.shellDarkPalette)),
                  if (darkPalette) const Icon(Icons.check, size: 20),
                ],
              ),
            ),
          ],
          child: child,
        );
    final signOut = IconButton(
      tooltip: l10n.shellSignOut,
      onPressed: onSignOut,
      icon: const Icon(Icons.logout, size: 20),
      color: theme.colorScheme.onSurfaceVariant,
    );
    // The palette switch, beside sign-out (issue #415). The menu item below is
    // still there; this is the visible route to the same cubit, because a
    // setting a person has to find under their own name is one they report as
    // missing.
    final paletteToggle = PaletteToggle(
      darkPalette: darkPalette,
      onPressed: onToggleDarkPalette,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: AppColors.of(context).edge),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? Spacing.xs : Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: collapsed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [menu(avatar), paletteToggle, signOut],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: menu(
                            Row(
                              children: [
                                avatar,
                                const SizedBox(width: Spacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Disclosed rather than silently ellipsized
                                      // (issue #385's sweep): at twice the text
                                      // neither fits the footer's 91px, and the
                                      // only `Tooltip` above them is the account
                                      // menu's, whose message is not the value it
                                      // is hiding.
                                      DisclosingText(
                                        account.displayName,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      DisclosingText(
                                        account.email,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        paletteToggle,
                        signOut,
                      ],
                    ),
                    Text(
                      appVersion,
                      key: PlatformShell.appVersionKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Sorts a Screen's own stops the way `Tab` already walks them inside that
/// Screen's page (issue #401).
///
/// `sortDescendants` is protected — the framework calls it from its own
/// traversal — so this is the thinnest possible subclass: one public door onto
/// the policy's own order. Re-implementing the geometry here would be a second
/// reading-order policy that could drift from the one the app actually uses.
class _ScreenOrder extends ReadingOrderTraversalPolicy {
  List<FocusNode> stopsOf(Iterable<FocusNode> nodes, FocusNode current) =>
      sortDescendants(nodes, current).toList();
}
