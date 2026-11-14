/// The state a person meets when the Account's own status could not be read:
/// the one failure that blocks every Screen, because no address can decide
/// whether to open without an Account in hand.
///
/// **The composition** is issue #396's, shared by all five platform states: a
/// bounded 460px card at the centre of the canvas, a 40px mark, the title and
/// the failing message in the shared `AppPageHeader` rhythm, and the actions
/// that get the reader out — `Try again` and `Sign out` — at the
/// `AppTouchTarget.min` floor. The mark wears the palette's `error` here: unlike
/// a refusal, this one *is* a fault, and the palette reserves that colour for
/// exactly that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_page_header.dart';
import 'account_bloc.dart';

class SessionErrorScreen extends StatelessWidget {
  const SessionErrorScreen({super.key, required this.message});

  final String message;

  static const ValueKey<String> retryKey = ValueKey<String>('session-error-retry');
  static const ValueKey<String> signOutKey = ValueKey<String>('session-error-sign-out');

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
                        child: Icon(Icons.error_outline, color: palette.statusDanger),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    AppPageHeader(
                      title: l10n.sessionErrorTheSessionCouldNotBeChecked,
                      description: l10n.sessionErrorCouldNotCheckThisAccountSStatus(message),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: [
                        FilledButton(
                          key: retryKey,
                          onPressed: () =>
                              context.read<AccountBloc>().add(const AccountRefreshRequested()),
                          child: Text(l10n.commonTryAgain),
                        ),
                        TextButton(
                          key: signOutKey,
                          onPressed: () =>
                              context.read<AccountBloc>().add(const AccountSignOutRequested()),
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
