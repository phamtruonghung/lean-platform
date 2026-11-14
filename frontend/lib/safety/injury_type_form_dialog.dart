/// Adding an Injury type, and correcting one (issue #224): the shared
/// catalogue's own write surface (`POST`/`PATCH /api/safety/injury-types`,
/// injury-type-routes.js, administrator only).
///
/// One dialog for both, the same choice `ProductFormDialog` makes: an Injury
/// type carries a code, a name and the Active switch, nowhere near enough
/// surface to earn two files. [injuryType] null means Add; non-null means
/// Correct, and Correct sends only the fields that actually changed — the
/// `hasOwnProperty` contract `updateInjuryType` (injury-types.js) keeps at the
/// other end.
///
/// A code is **not correctable**: it is what an incident's own report and an
/// export quote, so rewriting it would rewrite history. It is shown read-only
/// while correcting and never sent.
///
/// An Injury type is deactivated, never deleted — the "Active" switch, offered
/// only while correcting an existing row, is the one way this dialog ever
/// reaches `isActive`, and there is no delete anywhere on this Screen. A
/// deactivated entry stops being offered as a choice while classifying and
/// stays readable on every incident that already names it.
///
/// **Its shell is `AppDialog`** (issue #398, `docs/design-language.md` §11):
/// three fields at most is the `form` width, the shell owns the title row, the
/// one scroller and the action row, and on a narrow box or at twice the text it
/// becomes a bottom sheet with the fields still in one column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import 'injury_type.dart';
import 'injury_types_bloc.dart';

class InjuryTypeFormDialog extends StatefulWidget {
  const InjuryTypeFormDialog({super.key, this.injuryType});

  /// Null for Add; the row being corrected otherwise.
  final InjuryType? injuryType;

  static const ValueKey<String> codeKey = ValueKey<String>('injury-type-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('injury-type-form-name');
  static const ValueKey<String> activeKey = ValueKey<String>('injury-type-form-active');
  static const ValueKey<String> failureKey = ValueKey<String>('injury-type-form-failure');

  /// The two actions' ids, and the keys `AppDialog` gives them
  /// (`docs/design-language.md` §11).
  static const String _submitId = 'injury-type-form-submit';
  static const String _dismissId = 'injury-type-form-cancel';
  static ValueKey<String> get submitKey => AppDialog.actionKey(_submitId);
  static ValueKey<String> get cancelKey => AppDialog.actionKey(_dismissId);

  /// Opens the form over the catalogue. `showDialog` builds its route under
  /// the Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<InjuryTypesBloc>` the Screen lives in — so that Bloc is
  /// handed across explicitly, the device every other dialog here uses.
  static Future<void> open(BuildContext context, {InjuryType? injuryType}) {
    final bloc = context.read<InjuryTypesBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<InjuryTypesBloc>.value(
        value: bloc,
        child: InjuryTypeFormDialog(injuryType: injuryType),
      ),
    );
  }

  @override
  State<InjuryTypeFormDialog> createState() => _InjuryTypeFormDialogState();
}

class _InjuryTypeFormDialogState extends State<InjuryTypeFormDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.injuryType?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.injuryType?.name ?? '');
  late bool _isActive = widget.injuryType?.isActive ?? true;

  bool _awaiting = false;
  String? _failure;

  bool get _isCorrection => widget.injuryType != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty && (_isCorrection || _code.text.trim().isNotEmpty);

  /// Only the keys whose value actually changed from what this dialog opened
  /// with. The code is absent by construction: it is not correctable, so it is
  /// never sent.
  Map<String, Object?> get _changes {
    final original = widget.injuryType!;
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    if (name != original.name) changes['name'] = name;
    if (_isActive != original.isActive) changes['isActive'] = _isActive;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    if (_isCorrection) {
      final changes = _changes;
      if (changes.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context
          .read<InjuryTypesBloc>()
          .add(InjuryTypesCorrectionConfirmed(id: widget.injuryType!.id, changes: changes));
    } else {
      setState(() {
        _awaiting = true;
        _failure = null;
      });
      context.read<InjuryTypesBloc>().add(
            InjuryTypesAddConfirmed(code: _code.text.trim(), name: _name.text.trim()),
          );
    }
  }

  void _onCatalogueChanged(BuildContext context, InjuryTypesState state) {
    if (!_awaiting || state is! InjuryTypesLoaded || state.isMutating) return;
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocListener<InjuryTypesBloc, InjuryTypesState>(
      listener: _onCatalogueChanged,
      child: AppDialog(
        title: _isCorrection ? l10n.injuryTypeFormCorrectInjuryType : l10n.commonAddInjuryType,
        // A short form (520): three fields at most (§11).
        size: AppDialogSize.form,
        actions: [
          AppDialogAction(
            id: InjuryTypeFormDialog._dismissId,
            label: l10n.commonCancel,
            kind: AppDialogActionKind.dismiss,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            id: InjuryTypeFormDialog._submitId,
            label: _awaiting ? l10n.commonSaving : (_isCorrection ? l10n.commonSave : l10n.commonAddInjuryType),
            onPressed: _complete && !_awaiting ? _submit : null,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: InjuryTypeFormDialog.codeKey,
              controller: _code,
              enabled: !_isCorrection && !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonCode,
                border: const OutlineInputBorder(),
                helperText: _isCorrection ? l10n.injuryTypeFormAnInjuryTypeSCodeCannotBe : null,
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: InjuryTypeFormDialog.nameKey,
              controller: _name,
              enabled: !_awaiting,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l10n.commonName, border: OutlineInputBorder()),
            ),
            if (_isCorrection) ...[
              const SizedBox(height: Spacing.md),
              SwitchListTile(
                key: InjuryTypeFormDialog.activeKey,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.commonActive),
                subtitle: Text(
                  l10n.injuryTypeFormARetiredInjuryTypeIsNoLonger,
                ),
                value: _isActive,
                onChanged: _awaiting ? null : (value) => setState(() => _isActive = value),
              ),
            ],
            if (_failure != null)
              Padding(
                key: InjuryTypeFormDialog.failureKey,
                padding: const EdgeInsets.only(top: Spacing.md),
                child: Text(
                  _failure!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
