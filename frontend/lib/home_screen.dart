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
                    // A one-off status colour, not a token — a single caller
                    // doesn't earn its own AppColors.success.
                    Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade700),
                    const SizedBox(height: Spacing.md),
                    Text('Welcome, ${account.displayName}', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.sm),
                    Text('${account.email} · ${account.role}', style: theme.textTheme.bodyMedium),
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
