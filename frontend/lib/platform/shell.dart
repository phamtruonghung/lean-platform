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
                      for (final destination in destinations)
                        _NavItem(
                          destination: destination,
                          selected: destination.matches(currentLocation),
                          collapsed: collapsed,
                          onTap: () => onDestinationSelected(destination),
                        ),
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
