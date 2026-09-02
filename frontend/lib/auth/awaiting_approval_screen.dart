/// Shown instead of an error when an Account exists but has not been
/// admitted yet — issue #6's acceptance criterion, in the one place it's
/// visible: signing in successfully is not admission (CONTEXT.md's Approval
/// entry), so this screen is what tells a real person that plainly, without
/// looking like something broke.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/account_bloc.dart';
import '../theme.dart';

class AwaitingApprovalScreen extends StatelessWidget {
  const AwaitingApprovalScreen({super.key, required this.email});

  final String email;

  static const ValueKey<String> checkAgainKey = ValueKey<String>('awaiting-approval-check-again');

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
                    // Being admitted changes nothing in this browser — the
                    // Account's role and is_active are re-read from the server
                    // on every request, so asking again is all it takes. No
                    // signing out, no clearing anything (issue #41).
                    FilledButton(
                      key: checkAgainKey,
                      onPressed: () =>
                          context.read<AccountBloc>().add(const AccountRefreshRequested()),
                      child: const Text('Check again'),
                    ),
                    const SizedBox(height: Spacing.sm),
                    OutlinedButton(
                      // Dispatched through AccountBloc, not called on
                      // Supabase directly (issue #38): the Bloc is the only
                      // place the session is resolved, so it must also be the
                      // only place it ends.
                      onPressed: () => context.read<AccountBloc>().add(const AccountSignOutRequested()),
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
