/// Decides which screen to show, layered on top of two questions: is there
/// a Supabase session at all (an identity), and if so, is the Account that
/// identity resolves to admitted yet (issue #6 — signing in successfully is
/// not admission; see CONTEXT.md's Approval entry).
///
/// Supabase persists its own session locally and replays it as the first
/// event on `onAuthStateChange` once `Supabase.initialize()` has run — that
/// replay is what makes a session survive a page reload without this widget
/// doing anything special for it.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home_screen.dart';
import '../people_api.dart';
import 'awaiting_approval_screen.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _peopleApi = PeopleApi();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;

        if (session == null) {
          return const SignInScreen();
        }

        return _AccountGate(peopleApi: _peopleApi, accessToken: session.accessToken);
      },
    );
  }
}

/// Resolves the signed-in session's own Account status. Keyed by access
/// token, so a token refresh (Supabase rotates these periodically) re-checks
/// status with the API rather than trusting a stale answer for as long as
/// the tab stays open.
class _AccountGate extends StatefulWidget {
  const _AccountGate({required this.peopleApi, required this.accessToken});

  final PeopleApi peopleApi;
  final String accessToken;

  @override
  State<_AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<_AccountGate> {
  late Future<AccountStatus> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.peopleApi.fetchMe(widget.accessToken);
  }

  @override
  void didUpdateWidget(covariant _AccountGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessToken != widget.accessToken) {
      _refetch();
    }
  }

  void _refetch() {
    setState(() => _future = widget.peopleApi.fetchMe(widget.accessToken));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountStatus>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return _ErrorScreen(
            message: "Could not check this Account's status: ${snapshot.error}",
            onRetry: _refetch,
          );
        }

        return switch (snapshot.data!) {
          AccountPendingApproval(email: final email) => AwaitingApprovalScreen(email: email),
          final AccountActive account => HomeScreen(account: account),
        };
      },
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Try again')),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
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
