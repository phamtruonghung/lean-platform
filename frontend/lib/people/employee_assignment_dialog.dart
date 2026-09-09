/// Assigning an Employee to an Org Unit, and transferring one who already
/// holds an open Assignment (issue #88) — one action either way, exactly the
/// shape the issue's own header describes: `createAssignment` (directory.js)
/// decides "first Assignment" or "transfer" from whether an open one already
/// exists, so this dialog never asks which it is.
///
/// The destination is chosen through `OrgUnitPickerBloc`, driven directly —
/// this file lives inside the People Module itself, the same reason
/// `directory_org_unit_filter_dialog.dart` imports it directly rather than
/// through `people.dart` (that entry point is for a *different* Module to
/// reach People's Bloc, `maintenance/org_unit_chooser.dart`'s own header).
/// `OrgUnitPicker` the widget is not reused, for the same reason
/// `org_unit_chooser.dart` gives: it is a Grant editor built for the Approval
/// flow, add/remove semantics and a Granted pane included, and this dialog
/// wants a single-select choice with none of that. What is drawn here is a
/// third *view* over the one shared Bloc — `_DestinationPicker` below,
/// deliberately close in shape to `org_unit_chooser.dart`'s own
/// `_ChooserRow`, since a second Module-local copy of "browse a tree,
/// highlight the chosen row" is what that file's own header already accepts
/// as the right amount of duplication (the Bloc is shared; the view is not).
///
/// The tree itself is not narrowed to write-reachable Org Units only: the
/// root-level request already answers with this caller's own entry points
/// for anyone but an administrator (ADR-0008), and `OrgUnitNode` carries no
/// read/write distinction at all for this client to filter on further — the
/// same limitation `AssetFormDialog`'s own `OrgUnitChooser` already accepts
/// for placing an Asset. Picking a view-only entry point here is still
/// possible; the server's own 403 (`OUTSIDE_GRANTED_ORG_UNITS`) is the real
/// gate, surfaced on this form exactly like any other refusal.
///
/// [EmployeeDetailScreen] offers this action to any caller
/// `OrgUnitScope.canWriteSomewhere` allows — not only an administrator
/// (ADR-0010) — which is why this dialog, unlike `EmployeeCorrectionDialog`
/// and `EmployeeDepartureDialog` beside it, has no `isAdmin` anywhere in its
/// own path.
///
/// [effectiveFrom] is required on this form even though `createAssignment`
/// itself would default a missing one to today (directory.js): the ticket's
/// own contract names it required, and a caller assigning someone should say
/// which date on purpose rather than lean on a silent default they may not
/// have meant.
///
/// The word "transfer" never appears on this Screen — CONTEXT.md's own
/// Assignment entry lists it under `_Avoid_` for naming the record, and
/// "Assign" already covers both the first Assignment and every later one
/// (the issue's own header), so there is no second word needed here at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import 'employee.dart';
import 'employee_detail_bloc.dart';
import 'job_role.dart';
import 'org_unit.dart';
import 'org_unit_picker_bloc.dart';

class EmployeeAssignmentDialog extends StatefulWidget {
  const EmployeeAssignmentDialog({super.key, required this.employee});

  final EmployeeDetail employee;

  static const ValueKey<String> siteKey = ValueKey<String>('employee-assignment-site');
  static const ValueKey<String> jobRoleKey = ValueKey<String>('employee-assignment-job-role');
  static const ValueKey<String> effectiveFromKey = ValueKey<String>('employee-assignment-effective-from');
  static const ValueKey<String> submitKey = ValueKey<String>('employee-assignment-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('employee-assignment-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('employee-assignment-failure');
  static ValueKey<String> expandKey(String id) => ValueKey<String>('employee-assignment-expand-$id');
  static ValueKey<String> orgUnitKey(String id) => ValueKey<String>('employee-assignment-org-unit-$id');

  /// Opens the dialog over the detail Screen — the same explicit Bloc
  /// hand-off every dialog in this Module uses, `showDialog`'s route sitting
  /// outside the route-scoped `BlocProvider`s. Unlike `EmployeeCorrectionDialog`
  /// and its siblings, this dialog needs a second Bloc of its own
  /// (`OrgUnitPickerBloc`), the same pairing
  /// `DirectoryOrgUnitFilterDialog.open` already sets up for the Directory's
  /// own Org Unit filter.
  static Future<void> open(BuildContext context, EmployeeDetail employee) {
    final detailBloc = context.read<EmployeeDetailBloc>();
    final peopleApi = context.read<PeopleApi>();
    final authGateway = context.read<AuthGateway>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<EmployeeDetailBloc>.value(
        value: detailBloc,
        child: BlocProvider<OrgUnitPickerBloc>(
          create: (context) => OrgUnitPickerBloc(peopleApi: peopleApi, authGateway: authGateway)
            ..add(const OrgUnitPickerStarted()),
          child: EmployeeAssignmentDialog(employee: employee),
        ),
      ),
    );
  }

  @override
  State<EmployeeAssignmentDialog> createState() => _EmployeeAssignmentDialogState();
}

class _EmployeeAssignmentDialogState extends State<EmployeeAssignmentDialog> {
  final TextEditingController _effectiveFrom = TextEditingController();

  String? _orgUnitId;
  String? _jobRoleId;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _effectiveFrom.dispose();
    super.dispose();
  }

  bool get _complete => _orgUnitId != null && _effectiveFrom.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<EmployeeDetailBloc>().add(
          EmployeeDetailAssignmentConfirmed(
            orgUnitId: _orgUnitId!,
            jobRoleId: _jobRoleId,
            effectiveFrom: _effectiveFrom.text.trim(),
          ),
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailState = context.watch<EmployeeDetailBloc>().state;
    final jobRoles = detailState is EmployeeDetailLoaded ? detailState.jobRoles : const <JobRole>[];

    return BlocListener<EmployeeDetailBloc, EmployeeDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: Text('Assign ${widget.employee.displayName} to an Org Unit'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Where it works now', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xs),
                _DestinationPicker(
                  selectedId: _orgUnitId,
                  enabled: !_awaiting,
                  onSelected: (node) => setState(() => _orgUnitId = node.id),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: EmployeeAssignmentDialog.jobRoleKey,
                  initialValue: _jobRoleId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Job role (optional)', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('No job role')),
                    for (final jobRole in jobRoles)
                      DropdownMenuItem<String>(value: jobRole.id, child: Text(jobRole.name)),
                  ],
                  onChanged: _awaiting ? null : (value) => setState(() => _jobRoleId = value),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: EmployeeAssignmentDialog.effectiveFromKey,
                  controller: _effectiveFrom,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Effective date',
                    helperText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: EmployeeAssignmentDialog.failureKey,
                    padding: const EdgeInsets.only(top: Spacing.md),
                    child: Text(
                      _failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: EmployeeAssignmentDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: EmployeeAssignmentDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Assigning…' : 'Assign'),
          ),
        ],
      ),
    );
  }
}

/// The tree pane itself — a Site switch (when there is more than one to
/// choose from) over a bounded-height, single-select view of
/// `OrgUnitPickerBloc`'s own rows. See this file's own header for why this is
/// a third view rather than a shared widget with `org_unit_chooser.dart`.
class _DestinationPicker extends StatelessWidget {
  const _DestinationPicker({required this.selectedId, required this.enabled, required this.onSelected});

  final String? selectedId;
  final bool enabled;
  final ValueChanged<OrgUnitNode> onSelected;

  @override
  Widget build(BuildContext context) {
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
      body = const _PickerMessage(message: 'Nothing to browse in this Site.');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        itemCount: state.rows.length,
        itemBuilder: (context, index) => _DestinationRow(
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
            key: EmployeeAssignmentDialog.siteKey,
            initialValue: state.siteId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
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
          height: 220,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.edge),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium!, child: body),
        ),
      ],
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
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
                    key: EmployeeAssignmentDialog.expandKey(row.node.id),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: row.isExpanded ? 'Collapse' : 'Expand',
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
              key: EmployeeAssignmentDialog.orgUnitKey(row.node.id),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Spacing.xs),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
