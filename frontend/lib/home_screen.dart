/// What an active Account sees. There is no real Module screen yet — People,
/// Maintenance and the Tier Board's own screens land with their respective
/// issues — so this is a placeholder that proves the whole authenticated
/// path works: the app knows who signed in. It no longer ends the session
/// itself — the Shell's footer does that (issue #39).
library;

import 'package:flutter/material.dart';

import 'people_api.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.account});

  final AccountActive account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // AppColors.statusSuccess replaces the old raw green
                    // (issue #102) — that literal measured 4.12:1 against
                    // white, below the 4.5:1 floor; this one measures 6.53:1.
                    Icon(Icons.check_circle_outline, size: 48, color: AppColors.statusSuccess),
                    const SizedBox(height: Spacing.md),
                    Text('Welcome, ${account.displayName}', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.sm),
                    // Body copy reaches for AppTypography.body (bodyLarge,
                    // 16/24) rather than bodyMedium, per #102's type scale —
                    // this Screen is updated since #102 is already touching
                    // it for the colour fix above.
                    Text('${account.email} · ${account.role}', style: AppTypography.body(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
