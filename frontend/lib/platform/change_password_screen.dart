/// The Screen an Account is held on after an administrator reset its password
/// (`mustChangePassword`): the password it holds is temporary, so nothing else
/// opens until it has chosen its own. `accountRedirect` (router.dart) sends it
/// here from every address and moves it on once the flag is clear.
///
/// Unlike [ChangePasswordDialog], which a person opens from the Shell by
/// choice, this is a Screen with an address because the router must be able to
/// put someone on it. It shares [ChangePasswordBloc]; on success it asks
/// [AccountBloc] to re-read the Account, and the cleared flag is what lets the
/// redirect leave.
///
/// **The composition** (issue #396): the same bounded 460px card every platform
/// state uses, the title and its sentence in the shared `AppPageHeader` rhythm,
/// the two fields at the card's own `Spacing.lg` gutter with the failure line
/// under them, and the two actions in a `Wrap` so a narrow box stacks them
/// instead of squeezing them. A form on a card is the one screen here that needs
/// its `SingleChildScrollView`: at 200% text the card is taller than a phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../theme.dart';
import '../widgets/app_page_header.dart';
import 'account_bloc.dart';
import 'auth_gateway.dart';
import 'change_password_bloc.dart';
import '../widgets/notice_text.dart';

class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key});

  static const ValueKey<String> cardKey = ValueKey<String>('change-password-screen-card');
  static const ValueKey<String> currentFieldKey = ValueKey<String>('change-password-screen-current');
  static const ValueKey<String> newFieldKey = ValueKey<String>('change-password-screen-new');
  static const ValueKey<String> failureKey = ValueKey<String>('change-password-screen-failure');
  static const ValueKey<String> submitKey = ValueKey<String>('change-password-screen-submit');
  static const ValueKey<String> signOutKey = ValueKey<String>('change-password-screen-sign-out');

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChangePasswordBloc>(
      create: (context) => ChangePasswordBloc(
        peopleApi: context.read<PeopleApi>(),
        authGateway: context.read<AuthGateway>(),
      ),
      child: const _ChangePasswordForm(),
    );
  }
}

class _ChangePasswordForm extends StatefulWidget {
  const _ChangePasswordForm();

  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  String? _localFailure;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  void _submit(ChangePasswordState state) {
    if (state is ChangePasswordInProgress) return;
    if (_current.text.isEmpty) {
      setState(() => _localFailure = 'Enter your current password.');
      return;
    }
    if (_new.text.length < PeopleApi.minimumPasswordLength) {
      setState(() => _localFailure =
          'Use at least ${PeopleApi.minimumPasswordLength} characters for the new password.');
      return;
    }
    setState(() => _localFailure = null);
    context.read<ChangePasswordBloc>().add(
          ChangePasswordSubmitted(currentPassword: _current.text, newPassword: _new.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return BlocConsumer<ChangePasswordBloc, ChangePasswordState>(
      listener: (context, state) {
        if (state is ChangePasswordSucceeded) {
          context.read<AccountBloc>().add(const AccountRefreshRequested());
        }
      },
      builder: (context, state) {
        final awaiting = state is ChangePasswordInProgress || state is ChangePasswordSucceeded;
        final failure = _localFailure ?? (state is ChangePasswordFailed ? state.message : null);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.shellBrand)),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Card(
                  key: ChangePasswordScreen.cardKey,
                  // A `Card`'s own 4px margin would inset the block off the
                  // bound it was given; the padding is the block's, and the
                  // margin is zero (issue #396).
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppPageHeader(
                          title: l10n.titleChooseNewPassword,
                          description: l10n.changePasswordAnAdministratorResetYourPasswordSoThe,
                        ),
                        const SizedBox(height: Spacing.lg),
                        TextField(
                          key: ChangePasswordScreen.currentFieldKey,
                          controller: _current,
                          enabled: !awaiting,
                          obscureText: true,
                          autofocus: true,
                          decoration: InputDecoration(labelText: l10n.accountPasswordCurrent),
                        ),
                        const SizedBox(height: Spacing.md),
                        TextField(
                          key: ChangePasswordScreen.newFieldKey,
                          controller: _new,
                          enabled: !awaiting,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: l10n.accountPasswordNew,
                            helperText: l10n.accountPasswordAtLeastCharacters(PeopleApi.minimumPasswordLength),
                          ),
                          onSubmitted: (_) => _submit(state),
                        ),
                        if (failure != null)
                          Padding(
                            key: ChangePasswordScreen.failureKey,
                            padding: const EdgeInsets.only(top: Spacing.md),
                            child: NoticeText(
                              failure,
                              style: AppTypography.dense(context)
                                  ?.copyWith(color: palette.statusDanger),
                            ),
                          ),
                        const SizedBox(height: Spacing.lg),
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.sm,
                          children: [
                            FilledButton(
                              key: ChangePasswordScreen.submitKey,
                              onPressed: awaiting ? null : () => _submit(state),
                              child: Text(awaiting ? l10n.commonSaving : l10n.shellChangePassword),
                            ),
                            OutlinedButton(
                              key: ChangePasswordScreen.signOutKey,
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
      },
    );
  }
}
