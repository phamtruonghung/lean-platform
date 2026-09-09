/// Creating a Site (issue #90, ADR-0008's own baseline of what a Site is):
/// `POST /api/people/sites`, administrator only. There is no correction or
/// deactivation surface here — the ticket's own routes carry only a create,
/// unlike `JobRoleFormDialog`/`SkillFormDialog` beside it, so this dialog is
/// Add-only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import 'org_unit_admin_bloc.dart';

class SiteFormDialog extends StatefulWidget {
  const SiteFormDialog({super.key});

  static const ValueKey<String> codeKey = ValueKey<String>('site-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('site-form-name');
  static const ValueKey<String> timezoneKey = ValueKey<String>('site-form-timezone');
  static const ValueKey<String> countryCodeKey = ValueKey<String>('site-form-country-code');
  static const ValueKey<String> submitKey = ValueKey<String>('site-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('site-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('site-form-failure');

  /// Opens the form over `OrgUnitsScreen` — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider`.
  static Future<void> open(BuildContext context) {
    final bloc = context.read<OrgUnitAdminBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<OrgUnitAdminBloc>.value(
        value: bloc,
        child: const SiteFormDialog(),
      ),
    );
  }

  @override
  State<SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<SiteFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _timezone = TextEditingController();
  final TextEditingController _countryCode = TextEditingController();

  bool _awaiting = false;
  String? _failure;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _timezone.dispose();
    _countryCode.dispose();
    super.dispose();
  }

  bool get _complete =>
      _code.text.trim().isNotEmpty && _name.text.trim().isNotEmpty && _timezone.text.trim().isNotEmpty;

  void _submit() {
    if (!_complete || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final countryCode = _countryCode.text.trim();
    context.read<OrgUnitAdminBloc>().add(
          OrgUnitAdminSiteCreated(
            code: _code.text.trim(),
            name: _name.text.trim(),
            timezone: _timezone.text.trim(),
            countryCode: countryCode.isEmpty ? null : countryCode,
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
    // Cleared before popping, not after: `OrgUnitsScreen`'s own listener
    // reacts to this same success by dispatching `OrgUnitAdminEffectConsumed`,
    // which lands as a second, still-quiescent state (`isMutating: false`,
    // `mutationFailure: null`) while this dialog may still be mounted. Without
    // this, that second emission would satisfy the same guard above and pop a
    // second time, against whatever route now sits on top.
    _awaiting = false;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<OrgUnitAdminBloc, OrgUnitAdminState>(
      listener: _onAdminChanged,
      child: AlertDialog(
        title: const Text('Add Site'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: SiteFormDialog.codeKey,
                  controller: _code,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SiteFormDialog.nameKey,
                  controller: _name,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SiteFormDialog.timezoneKey,
                  controller: _timezone,
                  enabled: !_awaiting,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    helperText: 'An IANA zone, e.g. Europe/London',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: SiteFormDialog.countryCodeKey,
                  controller: _countryCode,
                  enabled: !_awaiting,
                  decoration: const InputDecoration(
                    labelText: 'Country code (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: SiteFormDialog.failureKey,
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
            key: SiteFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: SiteFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : 'Add Site'),
          ),
        ],
      ),
    );
  }
}
