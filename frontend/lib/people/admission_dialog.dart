/// Admitting an Account: choosing the role it will hold and the Org Units it
/// may work in, and submitting both as one act.
///
/// The Grant half is `OrgUnitPicker`, which this dialog composes and does not
/// own: its state lives in its own `OrgUnitPickerBloc`, built here for the
/// life of the dialog and read once, at submission. For the administrator role
/// the picker is not shown at all and the Grant set sent is empty — not a
/// shortfall but exactly right: an administrator acts everywhere by virtue of
/// the role and holds no Grant rows at all
/// (`backend/src/modules/people/authorization.js`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../l10n/vocabulary.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../platform/destinations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'approval_queue_bloc.dart';
import 'employee_link_picker.dart';
import 'org_unit_picker.dart';
import 'org_unit_picker_bloc.dart';
import 'pending_account.dart';
import 'role_choice.dart';

class AdmissionDialog extends StatefulWidget {
  const AdmissionDialog({super.key, required this.account});

  final PendingAccount account;

  static const ValueKey<String> adminWarningKey = ValueKey<String>('admission-admin-warning');
  static const ValueKey<String> noGrantsNoticeKey = ValueKey<String>('admission-no-grants');
  static const ValueKey<String> failureKey = ValueKey<String>('admission-failure');
  static final ValueKey<String> submitKey = AppDialog.actionKey('admission-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('admission-cancel');
  static ValueKey<String> roleKey(String role) => ValueKey<String>('admission-role-$role');

  /// Opens the decision over the queue.
  ///
  /// `showDialog` builds its route under the Navigator, which is not a
  /// descendant of the route-scoped `BlocProvider` the queue lives in — so the
  /// Bloc is handed across explicitly rather than looked up from inside.
  static Future<void> open(BuildContext context, PendingAccount account) {
    final bloc = context.read<ApprovalQueueBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      // A submission is in flight behind this barrier; dismissing it by
      // tapping away would leave the administrator with no report of how it
      // went.
      barrierDismissible: false,
      builder: (dialogContext) => MultiBlocProvider(
        providers: [
          BlocProvider<ApprovalQueueBloc>.value(value: bloc),
          // Dialog-scoped: created here, closed when this route is popped.
          // The picker is reusable because widget and Bloc travel together,
          // not because either outlives the Screen that mounted it.
          BlocProvider<OrgUnitPickerBloc>(
            create: (_) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
              ..add(const OrgUnitPickerStarted()),
          ),
        ],
        child: AdmissionDialog(account: account),
      ),
    );
  }

  @override
  State<AdmissionDialog> createState() => _AdmissionDialogState();
}

class _AdmissionDialogState extends State<AdmissionDialog> {
  /// Null until an administrator chooses — never defaulted to the first role,
  /// which would make "a role is chosen" true without anybody choosing it.
  ///
  /// Owned by this State, not by the Bloc: a failed Approval emits a new state
  /// and rebuilds this dialog's *builder*, but leaves this object alone, which
  /// is what keeps the choice on screen for a second attempt.
  String? _role;

  /// The Employee to confirm at Approval (issue #116, ADR-0022) — starts on
  /// the queue's own suggestion, if it carried one, and changes only when
  /// [EmployeeLinkPicker] reports a different choice. Null means no
  /// `employeeId` is sent at all, which is ordinary, not a shortfall.
  late String? _employeeId = widget.account.suggestedEmployee?.id;

  /// An Approval has been dispatched and has not settled yet. Local rather
  /// than read off the Bloc so it is already true within the same frame as the
  /// tap: a second tap before the first emit lands finds it set.
  bool _awaiting = false;

  /// The server's own message from the last attempt, if it failed.
  String? _failure;

  void _submit() {
    final role = _role;
    if (role == null || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    // Read once, here: the picker's state is the whole Grant set at the moment
    // of submitting, and an administrator's is empty regardless of what was
    // picked, because the role holds no Grant rows.
    final grants = role == Roles.admin
        ? const <Map<String, Object?>>[]
        : context.read<OrgUnitPickerBloc>().state.grantsPayload;
    context.read<ApprovalQueueBloc>().add(
          ApprovalQueueAdmissionConfirmed(
            accountId: widget.account.id,
            role: role,
            grants: grants,
            employeeId: _employeeId,
          ),
        );
  }

  void _onQueueChanged(BuildContext context, ApprovalQueueState state) {
    if (!_awaiting || state is! ApprovalQueueLoaded) return;
    if (state.admittingId == widget.account.id) return; // Still in flight.

    // Settled. Gone from the queue means the Approval landed — or that a 409
    // forced a re-read which no longer carries this row; either way this
    // decision is over and the queue itself reports what happened.
    if (!state.accounts.any((account) => account.id == widget.account.id)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _awaiting = false;
      _failure = state.notice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return BlocConsumer<ApprovalQueueBloc, ApprovalQueueState>(
      listener: _onQueueChanged,
      builder: (context, state) {
        return AppDialog(
          title: l10n.admissionAdmitThisAccount,
          size: AppDialogSize.wide,
          // `child` last, as `sort_child_properties_last` requires. The 880 the
          // old box computed is now the shell's `wide` width (#398, #392); the
          // Grant picker's two panes are `Expanded`, so they narrow with it.
          actions: [
            AppDialogAction(
              id: 'admission-cancel',
              label: l10n.commonCancel,
              kind: AppDialogActionKind.dismiss,
              onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            ),
            AppDialogAction(
              id: 'admission-submit',
              label: _awaiting ? l10n.commonAdmitting : l10n.commonAdmit,
              // Disabled, not merely refused on tap: nothing is sent, and the
              // reason is visible before anybody tries.
              onPressed: _role == null || _awaiting ? null : _submit,
            ),
          ],
          child: SizedBox(
            width: double.infinity,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.admissionWillBeLetInToThePlatform(widget.account.email),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Spacing.md),
                  EmployeeLinkPicker(
                    suggestion: widget.account.suggestedEmployee,
                    initial: widget.account.suggestedEmployee,
                    enabled: !_awaiting,
                    onChanged: (employee) => setState(() => _employeeId = employee?.id),
                  ),
                  const SizedBox(height: Spacing.md),
                  RadioGroup<String>(
                    groupValue: _role,
                    // Guarded rather than nulled out: RadioGroup.onChanged is
                    // not nullable, and the tiles below are disabled anyway
                    // while an Approval is in flight.
                    onChanged: (role) {
                      if (_awaiting) return;
                      setState(() => _role = role);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final choice in admissionRoles)
                          RadioListTile<String>(
                            key: AdmissionDialog.roleKey(choice.role),
                            value: choice.role,
                            title: Text(admissionRoleLabel(l10n, choice.role)),
                            subtitle: Text(admissionRoleDescription(l10n, choice.role)),
                            enabled: !_awaiting,
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  if (_role == Roles.admin)
                    _Callout(
                      key: AdmissionDialog.adminWarningKey,
                      icon: Icons.warning_amber_outlined,
                      background: theme.colorScheme.errorContainer,
                      foreground: theme.colorScheme.onErrorContainer,
                      message: l10n.admissionAnAdministratorCanActEverywhereThisAccount,
                    )
                  else ...[
                    const SizedBox(height: Spacing.md),
                    // Hidden for the administrator role, and only for it: an
                    // administrator's Grant set is empty by definition, so
                    // offering a picker there would contradict the warning
                    // directly above.
                    OrgUnitPicker(enabled: !_awaiting),
                    // An empty Grant set is allowed, and said out loud rather
                    // than left for the administrator to notice afterwards.
                    if (_role != null &&
                        context.watch<OrgUnitPickerBloc>().state.granted.isEmpty)
                      _Callout(
                        key: AdmissionDialog.noGrantsNoticeKey,
                        icon: Icons.info_outline,
                        background: theme.colorScheme.secondaryContainer,
                        foreground: theme.colorScheme.onSecondaryContainer,
                        message: l10n.admissionThisAccountWillBeAdmittedWithNo,
                      ),
                  ],
                  if (_failure != null)
                    _Callout(
                      key: AdmissionDialog.failureKey,
                      icon: Icons.error_outline,
                      background: theme.colorScheme.errorContainer,
                      foreground: theme.colorScheme.onErrorContainer,
                      message: _failure!,
                    ),
                ],
              ),
          ),
        );
      },
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    super.key,
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
