/// Shown instead of an error when an Account exists but has not been
/// admitted yet — issue #6's acceptance criterion, in the one place it's
/// visible: signing in successfully is not admission (CONTEXT.md's Approval
/// entry), so this screen is what tells a real person that plainly, without
/// looking like something broke.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('Awaiting approval', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      "You're signed in as $email, but an administrator hasn't "
                      'admitted you to the Platform yet. Check back once they have.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
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
