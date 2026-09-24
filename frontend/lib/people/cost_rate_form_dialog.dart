/// Adding a cost rate, correcting one, and revising one (issue #252) — the
/// shared catalogue's own write surface (`POST`/`PATCH /api/people/cost-rates`
/// and `POST /api/people/cost-rates/:id/revision`, administrator only).
///
/// One dialog for all three, the same choice `InjuryTypeFormDialog` makes for
/// its two: a rate carries a scope, a rate type, an amount, a currency and a
/// period, and three files would be the same form three times. [mode] says
/// which act is being performed, and the three differ in exactly the ways the
/// server does:
///
///   - **Add** opens on an empty form and posts the whole row.
///   - **Correct** is for a row that is wrong: a mistyped amount, a period that
///     started on the wrong day, and — setting "Applies until" — closing it. It
///     sends only the fields that actually changed, the `hasOwnProperty`
///     contract `updateCostRate` (cost-rates.js) keeps at the other end.
///   - **Revise** is for a rate that has *changed*: a new amount from a date,
///     which closes the old row and opens a new one. This is the one that keeps
///     history — the old amount stays readable and a cost view asked for an
///     earlier date still resolves it — so it is deliberately not the same
///     control as Correct, and its own copy says so.
///
/// **A rate's scope and rate type are not correctable.** Together they are the
/// key `resolve_cost_rate` finds a rate by, so rewriting either would move a
/// whole price history somewhere else in the Org Unit tree. They are shown
/// read-only while correcting or revising, and never sent.
///
/// Every value with a known set is chosen here, never typed (ADR-0023): the
/// scope type and the rate type are dropdowns over the schema's own four and
/// five; the scope itself is an `AppSearchField` over the list the Screen
/// already read, so `scopeType` and `scopeId` fall out of one pick rather than
/// two controls that can disagree; and both dates are `AppDateField` pickers.
/// When the scope list could not be read, the form says so and blocks
/// submission rather than falling back to a typed id (ADR-0023 point 6).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_date_field.dart';
import '../widgets/app_search_field.dart';
import 'cost_rate.dart';
import 'cost_rates_bloc.dart';

/// Which of the three acts this dialog is performing — see the class header.
enum CostRateFormMode { add, correct, revise }

class CostRateFormDialog extends StatefulWidget {
  const CostRateFormDialog({
    super.key,
    required this.mode,
    required this.scopes,
    this.scopesFailure,
    this.costRate,
  });

  final CostRateFormMode mode;

  /// Everything a rate may be scoped to, as the Screen read it. Only consulted
  /// in [CostRateFormMode.add] — the other two modes cannot change the scope.
  final List<CostRateScope> scopes;

  /// Why the scope list could not be read, when it could not. Blocks Add.
  final String? scopesFailure;

  /// The row being corrected or revised; null for Add.
  final CostRate? costRate;

  /// The scope picker's own field name — the one string [scopeKey] and
  /// [scopeSuggestionKey] are both derived from, so neither can drift from what
  /// the field is built with (AGENTS.md §7).
  static const String _scopeFieldName = 'cost-rate-form-scope';

  static ValueKey<String> get scopeKey => AppSearchField.fieldKey(_scopeFieldName);
  static ValueKey<String> scopeSuggestionKey(String scopeId) =>
      AppSearchField.suggestionKey(_scopeFieldName, scopeId);

  static const ValueKey<String> scopeTypeKey = ValueKey<String>('cost-rate-form-scope-type');
  static const ValueKey<String> rateTypeKey = ValueKey<String>('cost-rate-form-rate-type');
  static const ValueKey<String> amountKey = ValueKey<String>('cost-rate-form-amount');
  static const ValueKey<String> currencyKey = ValueKey<String>('cost-rate-form-currency');
  static const ValueKey<String> noteKey = ValueKey<String>('cost-rate-form-note');
  static const ValueKey<String> submitKey = ValueKey<String>('cost-rate-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('cost-rate-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('cost-rate-form-failure');
  static const ValueKey<String> scopesFailureKey =
      ValueKey<String>('cost-rate-form-scopes-failed');

  /// The two date pickers' own field names — the one string each field is
  /// built with and each `Key` below is derived from, so neither can drift
  /// (AGENTS.md §7). The `AppDateField`s themselves carry no `key:` of their
  /// own: `AppDateField` already keys its `TextField` off `name`, and giving
  /// the widget the same `ValueKey` as its own child would make `find.byKey`
  /// match twice.
  static const String _effectiveFromFieldName = 'cost-rate-effective-from';
  static const String _effectiveToFieldName = 'cost-rate-effective-to';

  static ValueKey<String> get effectiveFromKey =>
      AppDateField.fieldKey(_effectiveFromFieldName);
  static ValueKey<String> get effectiveToKey => AppDateField.fieldKey(_effectiveToFieldName);
  static ValueKey<String> get effectiveToClearKey =>
      AppDateField.clearKey(_effectiveToFieldName);

  /// Opens the form over the catalogue. `showDialog` builds its route under the
  /// Navigator, which is not a descendant of the route-scoped
  /// `BlocProvider<CostRatesBloc>` the Screen lives in — so that Bloc is handed
  /// across explicitly, the device every other dialog here uses.
  static Future<void> open(
    BuildContext context, {
    required CostRateFormMode mode,
    required List<CostRateScope> scopes,
    String? scopesFailure,
    CostRate? costRate,
  }) {
    final bloc = context.read<CostRatesBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<CostRatesBloc>.value(
        value: bloc,
        child: CostRateFormDialog(
          mode: mode,
          scopes: scopes,
          scopesFailure: scopesFailure,
          costRate: costRate,
        ),
      ),
    );
  }

  @override
  State<CostRateFormDialog> createState() => _CostRateFormDialogState();
}

class _CostRateFormDialogState extends State<CostRateFormDialog> {
  late String _scopeType = widget.costRate?.scopeType ?? costRateScopeTypes.first;
  /// The chosen scope, in Add only. Correcting and revising cannot change a
  /// rate's scope — it is read off the row itself and shown read-only, which is
  /// also why this is not seeded from [widget.scopes]: the list may not contain
  /// the scope at all if the record has since been retired, and a rate on a
  /// retired Asset is still a rate.
  CostRateScope? _scope;

  late String _rateType = widget.costRate?.rateType ?? costRateTypes.first;

  late final TextEditingController _amount = TextEditingController(
    // Revise opens blank: the whole point is a *new* amount, and pre-filling
    // the old one invites confirming it by accident.
    text: widget.mode == CostRateFormMode.correct ? '${widget.costRate!.amount}' : '',
  );
  late final TextEditingController _currency =
      TextEditingController(text: widget.costRate?.currency ?? 'USD');
  late final TextEditingController _note = TextEditingController(
    text: widget.mode == CostRateFormMode.correct ? (widget.costRate?.note ?? '') : '',
  );

  late String? _effectiveFrom =
      widget.mode == CostRateFormMode.correct ? widget.costRate!.effectiveFrom : null;
  late String? _effectiveTo =
      widget.mode == CostRateFormMode.correct ? widget.costRate!.effectiveTo : null;

  bool _awaiting = false;
  String? _failure;

  bool get _isAdd => widget.mode == CostRateFormMode.add;
  bool get _isCorrection => widget.mode == CostRateFormMode.correct;
  bool get _isRevision => widget.mode == CostRateFormMode.revise;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _note.dispose();
    super.dispose();
  }

  List<CostRateScope> get _scopesOfType =>
      [for (final scope in widget.scopes) if (scope.scopeType == _scopeType) scope];

  double? get _parsedAmount {
    final text = _amount.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return value;
  }

  bool get _currencyComplete =>
      costRateIsMultiplier(_rateType) || _currency.text.trim().length == 3;

  bool get _complete {
    if (_isAdd) {
      return widget.scopesFailure == null &&
          _scope != null &&
          _parsedAmount != null &&
          _currencyComplete &&
          _effectiveFrom != null;
    }
    if (_isRevision) return _parsedAmount != null && _currencyComplete && _effectiveFrom != null;
    // Correcting: any single field may have changed, and nothing is required
    // to change at all — the amount, however, must stay readable as a number.
    return _amount.text.trim().isEmpty || _parsedAmount != null;
  }

  /// Only the keys whose value actually changed from what this dialog opened
  /// with. The scope and the rate type are absent by construction: they are not
  /// correctable, so they are never sent.
  Map<String, Object?> get _changes {
    final original = widget.costRate!;
    final changes = <String, Object?>{};
    final amount = _parsedAmount;
    if (amount != null && amount != original.amount) changes['amount'] = amount;
    final currency = _currency.text.trim().toUpperCase();
    if (currency.length == 3 && currency != original.currency) changes['currency'] = currency;
    if (_effectiveFrom != null && _effectiveFrom != original.effectiveFrom) {
      changes['effectiveFrom'] = _effectiveFrom;
    }
    if (_effectiveTo != original.effectiveTo) changes['effectiveTo'] = _effectiveTo;
    final note = _note.text.trim();
    if (note != (original.note ?? '')) changes['note'] = note.isEmpty ? null : note;
    return changes;
  }

  void _submit() {
    if (!_complete || _awaiting) return;
    final bloc = context.read<CostRatesBloc>();

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
      bloc.add(CostRatesCorrectionConfirmed(id: widget.costRate!.id, changes: changes));
      return;
    }

    setState(() {
      _awaiting = true;
      _failure = null;
    });

    final note = _note.text.trim();
    final currency = _currency.text.trim().toUpperCase();

    if (_isRevision) {
      bloc.add(CostRatesRevisionConfirmed(
        id: widget.costRate!.id,
        body: {
          'amount': _parsedAmount,
          'currency': currency,
          'effectiveFrom': _effectiveFrom,
          if (note.isNotEmpty) 'note': note,
        },
      ));
      return;
    }

    bloc.add(CostRatesAddConfirmed(
      body: {
        'scopeType': _scope!.scopeType,
        'scopeId': _scope!.id,
        'rateType': _rateType,
        'amount': _parsedAmount,
        'currency': currency,
        'effectiveFrom': _effectiveFrom,
        if (_effectiveTo != null) 'effectiveTo': _effectiveTo,
        if (note.isNotEmpty) 'note': note,
      },
    ));
  }

  void _onCatalogueChanged(BuildContext context, CostRatesState state) {
    if (!_awaiting || state is! CostRatesLoaded || state.isMutating) return;
    if (state.mutationFailure != null) {
      setState(() {
        _awaiting = false;
        _failure = state.mutationFailure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  String get _title => switch (widget.mode) {
        CostRateFormMode.add => 'Add cost rate',
        CostRateFormMode.correct => 'Correct cost rate',
        CostRateFormMode.revise => 'Revise cost rate',
      };

  String get _submitLabel => switch (widget.mode) {
        CostRateFormMode.add => 'Add cost rate',
        CostRateFormMode.correct => 'Save',
        CostRateFormMode.revise => 'Revise from this date',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.costRate;

    return BlocListener<CostRatesBloc, CostRatesState>(
      listener: _onCatalogueChanged,
      child: AlertDialog(
        title: Text(_title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRevision)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(
                      'The rate below is closed on the day the new one takes effect. It stays '
                      'readable, and a cost asked for an earlier date still resolves it.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (_isAdd && widget.scopesFailure != null)
                  Padding(
                    key: CostRateFormDialog.scopesFailureKey,
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Text(
                      'The list of Sites, Org Units, Assets and cost centres could not be read, '
                      'so a scope cannot be chosen: ${widget.scopesFailure}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                if (_isAdd) ...[
                  DropdownButtonFormField<String>(
                    key: CostRateFormDialog.scopeTypeKey,
                    initialValue: _scopeType,
                    // `isExpanded` on both dropdowns here, with each item's own
                    // text ellipsised: a `DropdownButton` sizes itself to its
                    // widest item and overflows its field rather than
                    // shortening it, and "Overtime premium, a multiplier" is
                    // wider than this dialog at the one-box-per-glyph metrics
                    // `flutter_test` renders with. Ellipsising is the right
                    // answer at any width — a rate type's own words are worth
                    // more than a label trimmed to fit the narrowest case.
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Scope',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final scopeType in costRateScopeTypes)
                        DropdownMenuItem<String>(
                          value: scopeType,
                          child: Text(
                            costRateScopeTypeLabel(scopeType),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _awaiting
                        ? null
                        : (value) {
                            if (value == null) return;
                            // The chosen scope belongs to the old type, so it
                            // is cleared rather than left pointing somewhere
                            // the form no longer offers.
                            setState(() {
                              _scopeType = value;
                              _scope = null;
                            });
                          },
                  ),
                  const SizedBox(height: Spacing.md),
                  AppSearchField<CostRateScope>(
                    name: CostRateFormDialog._scopeFieldName,
                    label: 'Which ${costRateScopeTypeLabel(_scopeType)}',
                    value: _scope,
                    enabled: !_awaiting && widget.scopesFailure == null,
                    onChanged: (scope) => setState(() => _scope = scope),
                    onSelected: (scope) => setState(() => _scope = scope),
                    // A dumb in-memory filter over the list the Screen already
                    // read — no HTTP request of its own, so the field's
                    // per-term debounce never reaches the wire (ADR-0023).
                    fetchSuggestions: (term) async {
                      final lower = term.toLowerCase();
                      return [
                        for (final scope in _scopesOfType)
                          if (scope.name.toLowerCase().contains(lower) ||
                              scope.code.toLowerCase().contains(lower))
                            scope,
                      ];
                    },
                    suggestionBuilder: (context, scope) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      child: Text(scope.label),
                    ),
                    idOf: (scope) => scope.id,
                    displayStringFor: (scope) => scope.label,
                  ),
                  const SizedBox(height: Spacing.md),
                  DropdownButtonFormField<String>(
                    key: CostRateFormDialog.rateTypeKey,
                    initialValue: _rateType,
                    // See the scope-type dropdown above for why.
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Rate type',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final rateType in costRateTypes)
                        DropdownMenuItem<String>(
                          value: rateType,
                          child: Text(
                            costRateTypeLabel(rateType),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _awaiting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _rateType = value);
                          },
                  ),
                ] else
                  // Correcting or revising: the two fields that are not
                  // correctable, shown so the person knows which row they are
                  // on, and never sent.
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Scope and rate type',
                      border: OutlineInputBorder(),
                      helperText: "A rate's scope and rate type cannot be corrected — "
                          'add a rate for the new scope instead',
                    ),
                    child: Text(
                      '${existing!.scopeLabel} · ${costRateTypeLabel(existing.rateType)}',
                    ),
                  ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: CostRateFormDialog.amountKey,
                  controller: _amount,
                  enabled: !_awaiting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: costRateIsMultiplier(_rateType)
                        ? 'Multiplier (1.5 for time-and-a-half)'
                        : 'Amount per hour',
                    border: const OutlineInputBorder(),
                    helperText: _isRevision ? 'The new amount, from the date below' : null,
                  ),
                ),
                if (!costRateIsMultiplier(_rateType)) ...[
                  const SizedBox(height: Spacing.md),
                  TextField(
                    key: CostRateFormDialog.currencyKey,
                    controller: _currency,
                    enabled: !_awaiting,
                    maxLength: 3,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                      counterText: '',
                      helperText: 'A three-letter code, such as USD',
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                AppDateField(
                  name: CostRateFormDialog._effectiveFromFieldName,
                  label: _isRevision ? 'New rate takes effect on' : 'Takes effect on',
                  helperText: _isRevision
                      ? 'The old rate is closed on this day, and the new one starts'
                      : null,
                  value: _effectiveFrom,
                  onChanged: (value) => setState(() => _effectiveFrom = value),
                  enabled: !_awaiting,
                ),
                if (!_isRevision) ...[
                  const SizedBox(height: Spacing.md),
                  AppDateField(
                    name: CostRateFormDialog._effectiveToFieldName,
                    label: 'Applies until (optional)',
                    helperText: 'Left blank, this rate is the current one. Setting it closes '
                        'the rate on that day, which is the exclusive end of the period.',
                    value: _effectiveTo,
                    onChanged: (value) => setState(() => _effectiveTo = value),
                    optional: true,
                    enabled: !_awaiting,
                  ),
                ],
                const SizedBox(height: Spacing.md),
                TextField(
                  key: CostRateFormDialog.noteKey,
                  controller: _note,
                  enabled: !_awaiting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_failure != null)
                  Padding(
                    key: CostRateFormDialog.failureKey,
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
            key: CostRateFormDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: CostRateFormDialog.submitKey,
            onPressed: _complete && !_awaiting ? _submit : null,
            child: Text(_awaiting ? 'Saving…' : _submitLabel),
          ),
        ],
      ),
    );
  }
}
