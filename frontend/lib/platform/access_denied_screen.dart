/// What a caller gets at a real address their role does not earn.
///
/// Deliberately not the not-found Screen. The backend already settled this
/// order for itself (`authorization.js`: existence first, scope second) — a
/// 404 there is reserved for a thing that genuinely is not there, and a
/// refusal says so plainly with a 403. The same reasoning holds here: the
/// Approval queue's address is part of the Platform's own published surface,
/// not a secret an id could leak, so pretending it does not exist would only
/// leave a non-administrator debugging a broken link.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

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
                    Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: Spacing.md),
                    Text('Not available to you', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'This part of the Platform is for administrators. Ask one '
                      'if you need what is here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
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
