/// Shown instead of an error when an Account exists but has not been
/// admitted yet — issue #6's acceptance criterion, in the one place it's
/// visible: signing in successfully is not admission (CONTEXT.md's Approval
/// entry), so this screen is what tells a real person that plainly, without
/// looking like something broke.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

class AwaitingApprovalScreen extends StatelessWidget {
  const AwaitingApprovalScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Platform')),
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
                    Icon(Icons.hourglass_top, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: Spacing.md),
                    Text('Awaiting approval', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      "You're signed in as $email, but an administrator hasn't "
                      'admitted you to the Platform yet. Check back once they have.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    // 20 is not on the Spacing scale; rounding it to 16 or 24
                    // would change this layout, which this ticket forbids.
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Sign out'),
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
