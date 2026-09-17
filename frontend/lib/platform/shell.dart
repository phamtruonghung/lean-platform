/// The Shell: the persistent chrome around every Screen an admitted Account
/// can reach (CONTEXT.md's Shell).
///
/// Ported from `employee-management`'s `lib/src/app_shell.dart` — the collapse
/// behaviour, the 260/64 widths and the 700px rail breakpoint come across
/// unchanged. Two things deliberately do not: the sidebar renders its content
/// from `go_router`'s child rather than from a per-destination builder, so the
/// browser's history and back button work; and the predecessor's indigo
/// gradient is left behind for this Platform's own theme (theme.dart).
library;

import 'package:flutter/material.dart';

import '../people_api.dart';
import '../theme.dart';
import 'destinations.dart';

class PlatformShell extends StatelessWidget {
  const PlatformShell({
    super.key,
    required this.destinations,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.account,
    required this.onSignOut,
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

  @override
  Widget build(BuildContext context) {
    final collapsed = MediaQuery.sizeOf(context).width < railBreakpoint;

    return Scaffold(
      body: Row(
        // Stretch, so the sidebar runs the full height of the app rather than
        // only as far as its own contents reach.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            destinations: destinations,
            currentLocation: currentLocation,
            onDestinationSelected: onDestinationSelected,
            collapsed: collapsed,
            account: account,
            onSignOut: onSignOut,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.collapsed,
    required this.account,
    required this.onSignOut,
  });

  final List<Destination> destinations;
  final String currentLocation;
  final ValueChanged<Destination> onDestinationSelected;
  final bool collapsed;
  final AccountActive account;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    // Which Destination is current, asked once for the whole sidebar: the most
    // specific match rather than every path-prefix of the address, because the
    // CAPA list lives under the action log's own `/actions` (issue #211).
    final selectedPath = selectedDestinationPath(destinations, currentLocation);

    return Container(
      key: PlatformShell.sidebarKey,
      width: collapsed ? PlatformShell.collapsedWidth : PlatformShell.expandedWidth,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(right: BorderSide(color: AppColors.edge)),
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
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: Spacing.sm,
                                vertical: Spacing.xs,
                              ),
                              child: Divider(height: 1, color: AppColors.edge),
                            )
                          else if (group.name != null)
                            _GroupHeading(name: group.name!),
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
                'Platform',
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
/// [AppColors.textMuted], so it reads as a heading over the destinations filed
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
          color: AppColors.textMuted,
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
    // The selected state's fill and foreground are a component binding
    // (issue #102's AppComponentColors) — this exact pairing repeats
    // nowhere else yet, but it is the shape #102 named the token for.
    final foreground =
        selected ? AppComponentColors.navSelectedForeground : theme.colorScheme.onSurfaceVariant;

    Widget item = InkWell(
      borderRadius: BorderRadius.circular(Spacing.md),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppComponentColors.navSelectedBackground : null,
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
                          color: AppComponentColors.navSelectedAccent,
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
                child: Text(
                  destination.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
  });

  final AccountActive account;
  final bool collapsed;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final signOut = IconButton(
      tooltip: 'Sign out',
      onPressed: onSignOut,
      icon: const Icon(Icons.logout, size: 20),
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, color: AppColors.edge),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? Spacing.xs : Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: collapsed
              ? Column(mainAxisSize: MainAxisSize.min, children: [avatar, signOut])
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            account.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            account.email,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    signOut,
                  ],
                ),
        ),
      ],
    );
  }
}
