/// Raising a Training record (issue #287, ADR-0043): the Org Unit it was given
/// at, a title, the day, how many hours it lasted, optionally who trained and
/// the objective. It starts as a draft.
///
/// Correction mode (issue #291): opened with a [TrainingRecord] the dialog
/// shows the record's own facts pre-filled and restates them in full - the
/// same fields, the same submit gate - on a draft and a sent record alike. The
/// Org Unit is not a correctable fact, so its picker is not drawn. It talks to
/// the record's own `TrainingDetailBloc` rather than the register's, and
/// closes when the server has taken the restatement.
///
/// Every value with a known set is chosen, never typed (AGENTS.md §7,
/// ADR-0023): the Org Unit is browsed from the tree, the day comes from
/// `AppDateField`, and the trainer is an `AppSearchField` over the Directory —
/// a set nobody can scan. The submit button stays shut until the Org Unit, a
/// title, a day and a positive number of hours are all present. A server
/// refusal (403 outside the caller's Org Units, 404, 400) is rendered beside
/// the button with what was entered still in place.
///
/// Opened with `showDialog` and an explicit Bloc hand-off, as every dialog in
/// this Module is (`AttendanceRecordDialog.open`'s own pattern).
///
/// **The module's one long form, in `AppDialog` (issues #394 and #398,
/// ADR-0058).** This is the multi-section form pattern the slice's brief asks
/// for, and every part of it comes from a primitive rather than from this file:
///
/// - the shell, the width and the sheet behaviour are `AppDialog`'s, at
///   [AppDialogSize.wide] (640) — a long form with its own picker, not the 520
///   an `AlertDialog` used to be told through a `SizedBox` inside its content;
/// - **the submit row is pinned**, because `AppDialog` gives the content area
///   the scroll and keeps the actions under it: on a short box the fields
///   scroll while Raise/Cancel stay reachable, which is the "sticky submit at
///   wide" the brief names and was not true of the `AlertDialog` version;
/// - **the fields are grouped under section headings** — what the training was,
///   who gave it and why, and where it was given — so five fields and a tree
///   read as three questions rather than as one column of boxes;
/// - **the field grid is one column at every box**, by construction rather than
///   by a missing branch: the widest shell is 640 and `formTwoColumn` is 900, so
///   the grid's own breakpoint (`AppBreakpoints.formTwoColumn`, §10) can never
///   be reached inside a dialog. The brief's "one column under 700px" holds
///   everywhere this form is drawn.
///
/// Nothing about the form's behaviour moved: the same controllers, the same
/// gate on submit, the same Bloc events, the same field keys, the same helper
/// texts, the same failure line in the same place. The two action keys are the
/// shell's (`AppDialog.actionKey` of this dialog's own ids), the rename #398
/// established.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_search_field.dart';
import 'employee.dart';
import 'org_unit.dart';
import 'org_unit_picker_bloc.dart';
import 'training_bloc.dart';
import 'training_detail_bloc.dart';
import 'training_record.dart';

class TrainingRaiseDialog extends StatefulWidget {
  const TrainingRaiseDialog({super.key, this.record});

  /// The record being corrected, or null when raising a new one.
  final TrainingRecord? record;

  static const ValueKey<String> siteKey = ValueKey<String>('training-raise-site');
  static const ValueKey<String> titleKey = ValueKey<String>('training-raise-title');
  static const ValueKey<String> trainedOnKey = ValueKey<String>('training-raise-trained-on');
  static const ValueKey<String> durationKey = ValueKey<String>('training-raise-duration');
  static const ValueKey<String> objectiveKey = ValueKey<String>('training-raise-objective');

  /// The two actions, named through the dialog shell that now draws them
  /// (`AppDialog.actionKey`, ADR-0058): same accessors, the shell's key values.
  static final ValueKey<String> submitKey = AppDialog.actionKey(_submitId);
  static final ValueKey<String> cancelKey = AppDialog.actionKey(_cancelId);

  static const ValueKey<String> failureKey = ValueKey<String>('training-raise-failure');
  static ValueKey<String> expandKey(String id) => ValueKey<String>('training-raise-expand-$id');
  static ValueKey<String> orgUnitKey(String id) => ValueKey<String>('training-raise-org-unit-$id');

  static const String _submitId = 'training-raise-submit';
  static const String _cancelId = 'training-raise-cancel';

  /// The trainer picker's own name, which its `Key`s are derived from.
  static const String trainerFieldName = 'training-raise-trainer';
  static ValueKey<String> trainerFieldKey() => AppSearchField.fieldKey(trainerFieldName);
  static ValueKey<String> trainerSuggestionKey(String id) =>
      AppSearchField.suggestionKey(trainerFieldName, id);

  /// Opens the dialog over the register — handing across the register's own
  /// [TrainingBloc] (`showDialog`'s route sits outside the route-scoped
  /// provider) and giving the dialog an `OrgUnitPickerBloc` of its own.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<TrainingBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TrainingBloc>.value(
        value: bloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (context) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
          child: const TrainingRaiseDialog(),
        ),
      ),
    );
  }

  /// Opens the dialog in correction mode over the record's Screen, handing
  /// across its own [TrainingDetailBloc] (`showDialog`'s route sits outside the
  /// route-scoped provider).
  static Future<void> openCorrection(BuildContext context, TrainingRecord record) {
    final bloc = context.read<TrainingDetailBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<TrainingDetailBloc>.value(
        value: bloc,
        child: TrainingRaiseDialog(record: record),
      ),
    );
  }

  @override
  State<TrainingRaiseDialog> createState() => _TrainingRaiseDialogState();
}

class _TrainingRaiseDialogState extends State<TrainingRaiseDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.record?.title ?? '');
  late final TextEditingController _duration = TextEditingController(
    text: widget.record == null ? '' : _hoursText(widget.record!.durationHours),
  );
  late final TextEditingController _objective = TextEditingController(text: widget.record?.objective ?? '');

  String? _orgUnitId;
  late String? _trainedOn = widget.record?.trainedOn;
  late Employee? _trainer = _trainerOf(widget.record);

  bool _awaiting = false;
  String? _failure;

  bool get _correcting => widget.record != null;

  // Whole hours without a decimal point, so 2.0 pre-fills as `2`.
  static String _hoursText(double hours) =>
      hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();

  // The record names its trainer by id and name only; the picker's value is an
  // Employee, of which only those two are shown or sent.
  static Employee? _trainerOf(TrainingRecord? record) {
    final id = record?.trainerEmployeeId;
    if (record == null || id == null) return null;
    return Employee(
      id: id,
      employeeNo: '',
      displayName: record.trainerName ?? '',
      employmentType: '',
      isActive: true,
      orgUnitName: null,
      jobRoleName: null,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _objective.dispose();
    super.dispose();
  }

  double? get _hours {
    final hours = double.tryParse(_duration.text.trim());
    return hours != null && hours.isFinite && hours > 0 ? hours : null;
  }

  bool get _complete =>
      (_correcting || _orgUnitId != null) && _title.text.trim().isNotEmpty && _trainedOn != null && _hours != null;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final objective = _objective.text.trim();
    if (_correcting) {
      context.read<TrainingDetailBloc>().add(
            TrainingRecordCorrected(
              title: _title.text.trim(),
              trainedOn: _trainedOn!,
              durationHours: _hours!,
              trainerEmployeeId: _trainer?.id,
              objective: objective.isEmpty ? null : objective,
            ),
          );
      return;
    }
    context.read<TrainingBloc>().add(
          TrainingRaised(
            orgUnitId: _orgUnitId!,
            title: _title.text.trim(),
            trainedOn: _trainedOn!,
            durationHours: _hours!,
            trainerEmployeeId: _trainer?.id,
            objective: objective.isEmpty ? null : objective,
          ),
        );
  }

  void _onRegisterChanged(BuildContext context, TrainingState state) {
    if (!_awaiting || state.isRaising) return;
    if (state.raiseFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.raiseFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _onRecordChanged(BuildContext context, TrainingDetailState state) {
    if (!_awaiting || state is! TrainingDetailLoaded || state.isWriting) return;
    if (state.correctFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.correctFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dialog = _buildDialog(context);
    if (_correcting) {
      return BlocListener<TrainingDetailBloc, TrainingDetailState>(
        listener: _onRecordChanged,
        child: dialog,
      );
    }
    return BlocListener<TrainingBloc, TrainingState>(listener: _onRegisterChanged, child: dialog);
  }

  Widget _buildDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failure = _failure;
    return AppDialog(
      title: _correcting ? l10n.trainingRaiseCorrectTrainingRecord : l10n.commonRaiseTrainingRecord,
      size: AppDialogSize.wide,
      actions: [
        AppDialogAction(
          id: TrainingRaiseDialog._cancelId,
          label: l10n.commonCancel,
          kind: AppDialogActionKind.dismiss,
          onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          id: TrainingRaiseDialog._submitId,
          label: _correcting
              ? (_awaiting ? l10n.trainingRaiseCorrecting : l10n.trainingRaiseCorrectTrainingRecord)
              : (_awaiting ? l10n.trainingRaiseRaising : l10n.commonRaiseTrainingRecord),
          onPressed: _complete && !_awaiting ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SectionHeading('What it was'),
          TextField(
            key: TrainingRaiseDialog.titleKey,
            controller: _title,
            enabled: !_awaiting,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.trainingRaiseTitle,
              helperText: l10n.trainingRaiseWhatTheTrainingWas,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          AppDateField(
            key: TrainingRaiseDialog.trainedOnKey,
            name: 'training-raise-trained-on',
            label: l10n.commonTrainedOn,
            helperText: l10n.trainingRaiseTheDayItWasGiven,
            value: _trainedOn,
            enabled: !_awaiting,
            onChanged: (value) => setState(() => _trainedOn = value),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: TrainingRaiseDialog.durationKey,
            controller: _duration,
            enabled: !_awaiting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.trainingRaiseDurationHours,
              helperText: l10n.trainingRaiseHowLongItLastedEG1,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          const _SectionHeading('Who gave it, and why'),
          AppSearchField<Employee>(
            name: TrainingRaiseDialog.trainerFieldName,
            label: l10n.trainingRaiseTrainerOptional,
            helperText: l10n.trainingRaiseWhoGaveItFoundInTheDirectory,
            value: _trainer,
            enabled: !_awaiting,
            onChanged: (employee) => setState(() => _trainer = employee),
            onSelected: (employee) => setState(() => _trainer = employee),
            fetchSuggestions: (term) async {
              final token = context.read<AuthGateway>().currentAccessToken;
              if (token == null) return const [];
              return context.read<PeopleApi>().fetchEmployees(token, search: term, limit: 10);
            },
            suggestionBuilder: (context, employee) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
              child: Text(employee.displayName),
            ),
            idOf: (employee) => employee.id,
            displayStringFor: (employee) => employee.displayName,
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: TrainingRaiseDialog.objectiveKey,
            controller: _objective,
            enabled: !_awaiting,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.trainingRaiseObjectiveOptional,
              helperText: l10n.trainingRaiseWhatTheTrainingSetOutToTeach,
              border: OutlineInputBorder(),
            ),
          ),
          if (!_correcting) ...[
            const SizedBox(height: Spacing.lg),
            const _SectionHeading('Where it was given'),
            _OrgUnitPicker(
              selectedId: _orgUnitId,
              enabled: !_awaiting,
              onSelected: (node) => setState(() => _orgUnitId = node.id),
            ),
          ],
          if (failure != null)
            Padding(
              key: TrainingRaiseDialog.failureKey,
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Text(
                failure,
                style: AppTypography.dense(context)
                    ?.copyWith(color: AppColors.of(context).statusForeground(StatusTone.danger)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A section's own heading inside a long form: the same weight a section title
/// carries on a detail page, so the form reads as three questions. It is not
/// `AppDetailSection` — that is a card on a page, and a dialog's content is
/// already inside one.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Semantics(
        header: true,
        container: true,
        child: Text(
          title,
          style: AppTypography.dense(context)?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).textPrimary,
          ),
        ),
      ),
    );
  }
}

/// A single-select view over `OrgUnitPickerBloc`'s rows — the same shape
/// `EmployeeAssignmentDialog`'s destination picker takes (its header explains
/// why each caller draws its own view over the one shared Bloc).
class _OrgUnitPicker extends StatelessWidget {
  const _OrgUnitPicker({required this.selectedId, required this.enabled, required this.onSelected});

  final String? selectedId;
  final bool enabled;
  final ValueChanged<OrgUnitNode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<OrgUnitPickerBloc>().state;
    final bloc = context.read<OrgUnitPickerBloc>();

    Widget body;
    if (state.sitesStatus == SitesStatus.loading || state.rootsLoading) {
      body = const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (state.sitesStatus == SitesStatus.failed) {
      body = _PickerMessage(
        message: state.sitesFailure!,
        onRetry: enabled ? () => bloc.add(const OrgUnitPickerStarted()) : null,
      );
    } else if (state.rootsFailure != null) {
      body = _PickerMessage(
        message: state.rootsFailure!,
        onRetry: enabled ? () => bloc.add(OrgUnitPickerSiteSelected(state.siteId!)) : null,
      );
    } else if (state.rows.isEmpty) {
      body = _PickerMessage(message: l10n.commonNothingToBrowseInThisSite);
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: state.rows.length,
        itemBuilder: (context, index) => _OrgUnitPickerRow(
          row: state.rows[index],
          isSelected: state.rows[index].node.id == selectedId,
          enabled: enabled,
          onSelected: onSelected,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.sites.length > 1) ...[
          DropdownButtonFormField<String>(
            key: TrainingRaiseDialog.siteKey,
            initialValue: state.siteId,
            isDense: true,
            decoration: InputDecoration(labelText: l10n.commonSite, border: OutlineInputBorder()),
            items: [
              for (final site in state.sites)
                DropdownMenuItem<String>(value: site.id, child: Text(site.name)),
            ],
            onChanged: enabled
                ? (siteId) {
                    if (siteId == null) return;
                    bloc.add(OrgUnitPickerSiteSelected(siteId));
                  }
                : null,
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Container(
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.of(context).edge),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
        ),
      ],
    );
  }
}

class _OrgUnitPickerRow extends StatelessWidget {
  const _OrgUnitPickerRow({
    required this.row,
    required this.isSelected,
    required this.enabled,
    required this.onSelected,
  });

  final OrgUnitRow row;
  final bool isSelected;
  final bool enabled;
  final ValueChanged<OrgUnitNode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bloc = context.read<OrgUnitPickerBloc>();

    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.sm + row.depth * Spacing.lg, 0, Spacing.sm, 0),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: row.isLoadingChildren
                ? const Padding(
                    padding: EdgeInsets.all(Spacing.sm),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    key: TrainingRaiseDialog.expandKey(row.node.id),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? l10n.commonCollapse : l10n.commonExpand,
                    onPressed: enabled
                        ? () => bloc.add(
                              row.isExpanded
                                  ? OrgUnitPickerCollapsed(row.node.id)
                                  : OrgUnitPickerExpanded(row.node.id),
                            )
                        : null,
                    icon: Icon(row.isExpanded ? Icons.expand_more : Icons.chevron_right),
                  ),
          ),
          Expanded(
            child: TextButton(
              key: TrainingRaiseDialog.orgUnitKey(row.node.id),
              onPressed: enabled ? () => onSelected(row.node) : null,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(child: Text(row.node.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({this.message = '', this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Spacing.xs),
            TextButton(onPressed: onRetry, child: Text(l10n.commonTryAgain)),
          ],
        ],
      ),
    );
  }
}
