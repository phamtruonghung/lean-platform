/// Adding an Org Unit beneath [parentId], or starting a new root branch when
/// [parentId] is null (issue #90, ADR-0008): `POST
/// /api/people/sites/:siteId/org-units`. `OrgUnitsScreen` only ever offers
/// the root form to an administrator, but this dialog carries no such check
/// itself — the server's own 403 (`OUTSIDE_GRANTED_ORG_UNITS`) is the real
/// gate for the child case, and `requireAdmin` is the real gate for the root
/// case, the same division every write surface in this Module keeps.
///
/// Add-only, like `SiteFormDialog` beside it — there is no correction route
/// for an Org Unit's own fields, only `PATCH .../org-units/:id`'s narrow
/// `isActive` flip, which `OrgUnitsScreen`'s own Retire/Reinstate buttons
/// dispatch directly with no dialog at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'org_unit.dart';
import 'org_unit_admin_bloc.dart';

class OrgUnitFormDialog extends StatefulWidget {
  const OrgUnitFormDialog({super.key, required this.siteId, required this.parentId});

  final String siteId;

  /// Null starts a new root branch (ADR-0008); non-null is the parent this
  /// row is being added beneath.
  final String? parentId;

  static const ValueKey<String> codeKey = ValueKey<String>('org-unit-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('org-unit-form-name');
  static const ValueKey<String> unitTypeKey = ValueKey<String>('org-unit-form-unit-type');
  static const ValueKey<String> sortOrderKey = ValueKey<String>('org-unit-form-sort-order');
  static const ValueKey<String> submitKey = ValueKey<String>('org-unit-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('org-unit-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('org-unit-form-failure');

  /// Opens the form over `OrgUnitsScreen` — the same explicit Bloc hand-off
  /// every dialog in this Module uses.
  static Future<void> open(BuildContext context, {required String siteId, required String? parentId}) {
    final bloc = context.read<OrgUnitAdminBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<OrgUnitAdminBloc>.value(
        value: bloc,
        child: OrgUnitFormDialog(siteId: siteId, parentId: parentId),
      ),
    );
  }

  @override
  State<OrgUnitFormDialog> createState() => _OrgUnitFormDialogState();
}

class _OrgUnitFormDialogState extends State<OrgUnitFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _sortOrder = TextEditingController();
  String _unitType = OrgUnitTypes.area;

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final sortOrderText = _sortOrder.text.trim();
    context.read<OrgUnitAdminBloc>().add(
          OrgUnitAdminOrgUnitCreated(
            siteId: widget.siteId,
            parentId: widget.parentId,
            code: _code.text.trim(),
            name: _name.text.trim(),
            unitType: _unitType,
            sortOrder: sortOrderText.isEmpty ? null : int.tryParse(sortOrderText),
          ),
        );
  }

  void _onAdminChanged(BuildContext context, OrgUnitAdminState state) {
    if (!_awaiting || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    // See `SiteFormDialog._onAdminChanged`'s own comment: cleared before
    // popping so the second, effect-consumed emission this same success
    // triggers at `OrgUnitsScreen` cannot pop a second time.
    _awaiting = false;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<OrgUnitAdminBloc, OrgUnitAdminState>(
      listener: _onAdminChanged,
      child: AlertDialog(
        title: Text(widget.parentId == null ? 'Add root Org Unit' : 'Add Org Unit'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: OrgUnitFormDialog.codeKey,
                  controller: _code,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: OrgUnitFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  key: OrgUnitFormDialog.unitTypeKey,
                  initialValue: _unitType,
                  decoration: const InputDecoration(labelText: 'Unit type', border: OutlineInputBorder()),
                  items: [
                    for (final unitType in OrgUnitTypes.values)
                      DropdownMenuItem<String>(value: unitType, child: Text(unitType)),
                  ],
                  onChanged: _awaiting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _unitType = value);
                        },
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: OrgUnitFormDialog.sortOrderKey,
                  controller: _sortOrder,
                  enabled: !_awaiting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort order (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: OrgUnitFormDialog.failureKey,
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
            key: OrgUnitFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: OrgUnitFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Add Org Unit'),
          ),
        ],
      ),
    );
  }
}
