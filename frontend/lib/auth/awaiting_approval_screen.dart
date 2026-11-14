/// Shown instead of an error when an Account exists but has not been
/// admitted yet — issue #6's acceptance criterion, in the one place it's
/// visible: signing in successfully is not admission (CONTEXT.md's Approval
/// entry), so this screen is what tells a real person that plainly, without
/// looking like something broke.
///
/// **The composition** is issue #396's, shared by all five platform states: a
/// bounded 460px card at the centre of the canvas, a 40px mark, the title and
/// the sentence in the shared `AppPageHeader` rhythm, and the two things a
/// person can do about it at the `AppTouchTarget.min` floor — check again, or
/// sign out. The mark is the palette's neutral tile rather than a warning: an
/// Account waiting on an administrator is not a fault, and the sentence is what
/// carries the meaning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../platform/account_bloc.dart';
import '../theme.dart';
import '../widgets/app_page_header.dart';

class AwaitingApprovalScreen extends StatelessWidget {
  const AwaitingApprovalScreen({super.key, required this.email});

  final String email;

  static const ValueKey<String> checkAgainKey = ValueKey<String>('awaiting-approval-check-again');
  static const ValueKey<String> signOutKey = ValueKey<String>('awaiting-approval-sign-out');

  static const double markSize = 40;
  static const double markRadius = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shellBrand)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Card(
              // A `Card`'s own 4px margin would inset the block off the bound
              // it was given; the padding is the block's, and the margin is
              // zero (issue #396).
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: markSize,
                        height: markSize,
                        decoration: BoxDecoration(
                          color: palette.navSelectedBackground,
                          borderRadius: BorderRadius.circular(markRadius),
                        ),
                        child: Icon(Icons.hourglass_top, color: palette.navSelectedForeground),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    AppPageHeader(
                      title: l10n.titleAwaitingApproval,
                      description: l10n.awaitingApprovalYouReSignedInAsButAn(email),
                    ),
                    const SizedBox(height: Spacing.lg),
                    // Being admitted changes nothing in this browser — the
                    // Account's role and is_active are re-read from the server
                    // on every request, so asking again is all it takes. No
                    // signing out, no clearing anything (issue #41).
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: [
                        FilledButton(
                          key: checkAgainKey,
                          onPressed: () =>
                              context.read<AccountBloc>().add(const AccountRefreshRequested()),
                          child: Text(l10n.awaitingApprovalCheckAgain),
                        ),
                        OutlinedButton(
                          // Dispatched through AccountBloc, not called on
                          // the gateway directly (issue #38): the Bloc is the
                          // only place the session is resolved, so it must
                          // also be the only place it ends.
                          key: signOutKey,
                          onPressed: () => context
                              .read<AccountBloc>()
                              .add(const AccountSignOutRequested()),
                          child: Text(l10n.shellSignOut),
                        ),
                      ],
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
