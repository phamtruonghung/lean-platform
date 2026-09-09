/// Importing a whole branch (or several) of a Site's Org Unit hierarchy in
/// one call (issue #90, ADR-0011): `POST
/// /api/people/sites/:siteId/org-units/import`. "A file" in the issue's own
/// words means a JSON body of rows over this API (ADR-0011's own decision) —
/// this dialog is the thinnest honest way to submit that shape from the
/// client: a caller pastes the JSON array a spreadsheeter or a script already
/// produced, this dialog decodes it locally and hands the decoded list
/// straight to `OrgUnitAdminBloc`, and does not try to be a spreadsheet
/// editor of its own.
///
/// Every row is validated whole before anything is applied (ADR-0011's own
/// point); a `422` renders as [OrgUnitImportException.errors], one entry per
/// offending row, never flattened to a single message — the whole reason
/// `PeopleApi.importOrgUnits` throws that type instead of an ordinary
/// [PeopleApiException]. Nothing here implies a partial import happened: the
/// failure banner names every row's own reason, and the dialog stays open
/// exactly as it was, the same "nothing landed" honesty the 422 itself
/// carries.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../theme.dart';
import 'org_unit_admin_bloc.dart';

class OrgUnitImportDialog extends StatefulWidget {
  const OrgUnitImportDialog({super.key, required this.siteId});

  final String siteId;

  static const ValueKey<String> payloadKey = ValueKey<String>('org-unit-import-payload');
  static const ValueKey<String> submitKey = ValueKey<String>('org-unit-import-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('org-unit-import-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('org-unit-import-failure');
  static const ValueKey<String> parseFailureKey = ValueKey<String>('org-unit-import-parse-failure');
  static ValueKey<String> rowErrorKey(int row) => ValueKey<String>('org-unit-import-row-error-$row');

  /// Opens the form over `OrgUnitsScreen` — the same explicit Bloc hand-off
  /// every dialog in this Module uses.
  static Future<void> open(BuildContext context, {required String siteId}) {
    final bloc = context.read<OrgUnitAdminBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<OrgUnitAdminBloc>.value(
        value: bloc,
        child: OrgUnitImportDialog(siteId: siteId),
      ),
    );
  }

  @override
  State<OrgUnitImportDialog> createState() => _OrgUnitImportDialogState();
}

class _OrgUnitImportDialogState extends State<OrgUnitImportDialog> {
  final TextEditingController _payload = TextEditingController();

  bool _awaiting = false;
  String? _parseFailure;

  @override
  void dispose() {
    _payload.dispose();
    super.dispose();
  }

  /// The pasted text, decoded into the row set `importOrgUnits` wants — null,
  /// with [_parseFailure] set, when it is not a JSON array of objects at all.
  /// This is a local, client-side shape check only: whether each row's own
  /// fields are valid is entirely the server's own job (org-unit-import.js's
  /// `validateRows`), reported back as row errors once submitted.
  List<Map<String, Object?>>? _decode() {
    final text = _payload.text.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return null;
      return [for (final row in decoded) (row as Map<String, dynamic>).cast<String, Object?>()];
    } catch (_) {
      return null;
    }
  }

  void _submit() {
    if (_awaiting) return;
    final rows = _decode();
    if (rows == null || rows.isEmpty) {
      setState(() => _parseFailure = 'Paste a JSON array of rows, each carrying at least code, name '
          'and unitType.');
      return;
    }
    setState(() {
      _awaiting = true;
      _parseFailure = null;
    });
    context.read<OrgUnitAdminBloc>().add(
          OrgUnitAdminImportRequested(siteId: widget.siteId, orgUnits: rows),
        );
  }

  void _onAdminChanged(BuildContext context, OrgUnitAdminState state) {
    if (!_awaiting || state.isImporting) return;
    if (state.importFailure != null) {
      setState(() => _awaiting = false);
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
      child: Builder(
        builder: (context) {
          final state = context.watch<OrgUnitAdminBloc>().state;
          return AlertDialog(
            title: const Text('Import a branch'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'A JSON array of rows. Each row references its own parent by '
                      '"parentCode" — another row in this same array, or an existing '
                      'code at this Site — never by id.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Spacing.md),
                    TextField(
                      key: OrgUnitImportDialog.payloadKey,
                      controller: _payload,
                      enabled: !_awaiting,
                      maxLines: 8,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '[{"code": "A1", "name": "Assembly", "unitType": "area"}]',
                      ),
                    ),
                    if (_parseFailure != null)
                      Padding(
                        key: OrgUnitImportDialog.parseFailureKey,
                        padding: const EdgeInsets.only(top: Spacing.md),
                        child: Text(
                          _parseFailure!,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    if (state.importFailure != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.md),
                        child: Text(
                          // Nothing was applied — ADR-0011's own all-or-nothing rule
                          // — so the banner never implies a partial import landed.
                          state.importFailure!,
                          key: OrgUnitImportDialog.failureKey,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                      // Every row's own reason, not only the first — the ticket's
                      // own acceptance criterion.
                      for (final rowError in state.importErrors)
                        Padding(
                          key: OrgUnitImportDialog.rowErrorKey(rowError.row),
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Text(
                            'Row ${rowError.row + 1}'
                            '${rowError.code == null ? '' : ' (${rowError.code})'}'
                            '${rowError.field == null ? '' : ', ${rowError.field}'}: '
                            '${rowError.message}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                key: OrgUnitImportDialog.cancelKey,
                onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: OrgUnitImportDialog.submitKey,
                onPressed: _awaiting ? null : _submit,
                child: Text(_awaiting ? 'Importing…' : 'Import'),
              ),
            ],
          );
        },
      ),
    );
  }
}
