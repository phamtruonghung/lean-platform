import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'account_bloc.dart';

class SessionErrorScreen extends StatelessWidget {
  const SessionErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: Spacing.md),
                Text("Could not check this Account's status: $message",
                    textAlign: TextAlign.center),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: () =>
                      context.read<AccountBloc>().add(const AccountRefreshRequested()),
                  child: const Text('Try again'),
                ),
                const SizedBox(height: Spacing.sm),
                TextButton(
                  onPressed: () =>
                      context.read<AccountBloc>().add(const AccountSignOutRequested()),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
