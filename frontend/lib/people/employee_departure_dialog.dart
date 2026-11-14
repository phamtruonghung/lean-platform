/// Recording that an Employee has departed (issue #87): a flag and the date
/// it took effect, never a deletion — CONTEXT.md's own Departed entry, and
/// the reason this dialog reads "has left", never "delete" or "remove".
///
/// The date is optional, mirroring `setEmployeeDeparted`'s own default
/// (directory.js): left blank, the server records today.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_dialog.dart';
import 'employee.dart';
import 'employee_detail_bloc.dart';
import '../widgets/notice_text.dart';

class EmployeeDepartureDialog extends StatefulWidget {
  const EmployeeDepartureDialog({super.key, required this.employee});

  final EmployeeDetail employee;

  static const ValueKey<String> terminatedOnKey = ValueKey<String>('employee-departure-terminated-on');
  static final ValueKey<String> submitKey = AppDialog.actionKey('employee-departure-submit');
  static final ValueKey<String> cancelKey = AppDialog.actionKey('employee-departure-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('employee-departure-failure');

  /// The second step (issue #116, ADR-0022), shown only when the departure
  /// just recorded found a linked Account — the departure has already landed
  /// by the time any of these three render, so none of them can block it.
  static const ValueKey<String> linkedAccountWarningKey =
      ValueKey<String>('employee-departure-linked-account-warning');
  static final ValueKey<String> deactivateLinkedAccountKey =
      AppDialog.actionKey('employee-departure-deactivate');
  static final ValueKey<String> skipDeactivationKey =
      AppDialog.actionKey('employee-departure-skip');

  /// Opens the dialog over the detail Screen — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider`.
  static Future<void> open(BuildContext context, EmployeeDetail employee) {
    final bloc = context.read<EmployeeDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<EmployeeDetailBloc>.value(
        value: bloc,
        child: EmployeeDepartureDialog(employee: employee),
      ),
    );
  }

  @override
  State<EmployeeDepartureDialog> createState() => _EmployeeDepartureDialogState();
}

class _EmployeeDepartureDialogState extends State<EmployeeDepartureDialog> {
  /// No `TextEditingController` here — `AppDateField` is controlled
  /// (`value`/`onChanged`), so this dialog holds the date itself. Null means
  /// genuinely unset (never a defaulted date), which is exactly what leaves
  /// the server free to record today, mirroring `setEmployeeDeparted`'s own
  /// default (this file's own header).
  String? _terminatedOn;

  bool _awaiting = false;
  String? _failure;

  /// Set only once the departure has landed and found a linked Account
  /// (issue #116, ADR-0022) — its presence is what switches this dialog's
  /// own content from the departure form to the warning step. The departure
  /// itself has already been recorded by the time this is ever non-null, so
  /// nothing below can block it.
  LinkedAccountSummary? _linkedAccount;

  void _submit() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<EmployeeDetailBloc>().add(
          EmployeeDetailDepartureConfirmed(terminatedOn: _terminatedOn),
        );
  }

  void _deactivateLinkedAccount() {
    if (_awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<EmployeeDetailBloc>().add(
          EmployeeDetailLinkedAccountDeactivationConfirmed(accountId: _linkedAccount!.id),
        );
  }

  void _onDetailChanged(BuildContext context, EmployeeDetailState state) {
    if (!_awaiting || state is! EmployeeDetailLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    if (_linkedAccount == null && state.departureLinkedAccount != null) {
      // The departure just landed, and left a linked Account behind — one
      // extra step, not a second dialog, and the departure itself already
      // happened regardless of what is chosen next.
      setState(() {
        _awaiting = false;
        _linkedAccount = state.departureLinkedAccount;
      });
      return;
    }
    // Either there was nothing to warn about, or the warning has just been
    // dealt with (deactivated, or a plain reinstatement/correction settling
    // while this dialog happened to still be open).
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final linkedAccount = _linkedAccount;
    return BlocListener<EmployeeDetailBloc, EmployeeDetailState>(
      listener: _onDetailChanged,
      child: AppDialog(
        title: linkedAccount == null
            ? l10n.employeeDepartureRecordThatHasLeft(widget.employee.displayName)
            : l10n.employeeDepartureAccountStillLinked,
        size: AppDialogSize.picker,
        // `child` last, as `sort_child_properties_last` requires.
        actions: linkedAccount == null ? _departureActions() : _linkedAccountActions(),
        child: linkedAccount == null
            ? _departureForm(theme)
            : _linkedAccountWarning(theme, linkedAccount),
      ),
    );
  }

  Widget _departureForm(ThemeData theme) => SizedBox(
        width: double.infinity,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).employeeDepartureTheRecordStaysNothingIsDeletedAnd,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              AppDateField(
                key: EmployeeDepartureDialog.terminatedOnKey,
                name: 'departure-terminated-on',
                label: AppLocalizations.of(context).employeeDepartureEffectiveDateOptional,
                helperText: AppLocalizations.of(context).commonLeftBlankTodayIsRecorded,
                value: _terminatedOn,
                onChanged: (value) => setState(() => _terminatedOn = value),
                optional: true,
                enabled: !_awaiting,
              ),
              if (_failure != null)
                Padding(
                  key: EmployeeDepartureDialog.failureKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: NoticeText(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
      );

  List<AppDialogAction> _departureActions() => [
        AppDialogAction(
          id: 'employee-departure-cancel',
          label: AppLocalizations.of(context).commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'employee-departure-submit',
          label: _awaiting
              ? AppLocalizations.of(context).employeeDepartureRecording
              : AppLocalizations.of(context).commonRecordDeparture,
          onPressed: _awaiting ? null : _submit,
        ),
      ];

  Widget _linkedAccountWarning(ThemeData theme, LinkedAccountSummary linkedAccount) => SizedBox(
        key: EmployeeDepartureDialog.linkedAccountWarningKey,
        width: double.infinity,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).employeeDepartureHasLeftAndTheirAccountCanStill(
                    widget.employee.displayName, linkedAccount.email),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_failure != null)
                Padding(
                  key: EmployeeDepartureDialog.failureKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: NoticeText(
                    _failure!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
      );

  List<AppDialogAction> _linkedAccountActions() => [
        AppDialogAction(
          id: 'employee-departure-skip',
          label: AppLocalizations.of(context).employeeDepartureNotNow,
          kind: AppDialogActionKind.dismiss,
          onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: 'employee-departure-deactivate',
          label: _awaiting
              ? AppLocalizations.of(context).employeeDepartureDeactivating
              : AppLocalizations.of(context).employeeDepartureDeactivateAccount,
          onPressed: _awaiting ? null : _deactivateLinkedAccount,
        ),
      ];
}
