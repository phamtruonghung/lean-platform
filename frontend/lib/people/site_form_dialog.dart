/// Creating a Site (issue #90, ADR-0008's own baseline of what a Site is) or
/// correcting one (issue #137, ADR-0025): `POST /api/people/sites` and
/// `PATCH /api/people/sites/:siteId`, both administrator only. [site] decides
/// which — null creates, a Site corrects, seeding every field from its stored
/// values.
///
/// The timezone field is `AppSearchField` over the timezone list `GET
/// /api/people/timezones` answers (issue #123/#127, ADR-0023), not a typed
/// `TextField` any more: `sites_validate_timezone()` was the only thing that
/// ever caught a typo, and a value that was merely valid-but-wrong moved a
/// Site's production-day boundary in silence (ADR-0017). `OrgUnitAdminBloc`
/// (already this dialog's own shared Bloc) fetches the ~1,200-row list once
/// when this dialog opens; typing filters that list in memory, never
/// refetching per keystroke. The field starts unset when creating, and seeded
/// from the Site when correcting — a stored zone is displayed even when the
/// fetched list does not contain it (ADR-0023 point 4), the criterion #127
/// could not meet until this correction surface existed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/failure_state.dart';
import 'org_unit.dart';
import 'org_unit_admin_bloc.dart';

class SiteFormDialog extends StatefulWidget {
  const SiteFormDialog({super.key, this.site});

  /// The Site being corrected, or null when creating one (issue #137). Its
  /// stored values seed the fields, including the timezone.
  final Site? site;

  /// The `name` this dialog's own `AppSearchField` is seeded with — kept in
  /// one place so [timezoneKey] and [timezoneSuggestionKey] can never drift
  /// from what `build` actually renders.
  static const String _timezoneFieldName = 'site-timezone';

  static const ValueKey<String> codeKey = ValueKey<String>('site-form-code');
  static const ValueKey<String> nameKey = ValueKey<String>('site-form-name');

  /// Kept as the accessor's existing name (issue #127) even though the
  /// control behind it changed from a `TextField` to `AppSearchField` — this
  /// now resolves to that field's own key rather than a bespoke one.
  static ValueKey<String> get timezoneKey => AppSearchField.fieldKey(_timezoneFieldName);

  /// One timezone suggestion row's own `Key`, keyed by the zone name itself
  /// (`AppSearchField`'s `idOf` for this field is the identity function).
  static ValueKey<String> timezoneSuggestionKey(String zone) =>
      AppSearchField.suggestionKey(_timezoneFieldName, zone);

  /// Shown in place of the timezone field when the list itself could not be
  /// fetched (issue #127) — distinct from `AppSearchField.retryKey`, since
  /// that failure state is never reached here: the full list is fetched once
  /// by `OrgUnitAdminBloc`, not per keystroke by `AppSearchField` itself.
  static const ValueKey<String> timezoneRetryKey = ValueKey<String>('site-form-timezone-retry');

  static const ValueKey<String> countryCodeKey = ValueKey<String>('site-form-country-code');
  static const ValueKey<String> submitKey = ValueKey<String>('site-form-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('site-form-cancel');
  static const ValueKey<String> failureKey = ValueKey<String>('site-form-failure');

  /// Opens the form over `OrgUnitsScreen` — the same explicit Bloc hand-off
  /// every dialog in this Module uses, `showDialog`'s route sitting outside
  /// the route-scoped `BlocProvider`.
  static Future<void> open(BuildContext context, {Site? site}) {
    final bloc = context.read<OrgUnitAdminBloc>();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider<OrgUnitAdminBloc>.value(
        value: bloc,
        child: SiteFormDialog(site: site),
      ),
    );
  }

  @override
  State<SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<SiteFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _countryCode = TextEditingController();

  /// The confirmed timezone selection — controlled by `AppSearchField`'s own
  /// `value`/`onChanged`/`onSelected` contract, never typed free text. Unset
  /// when creating; seeded from the Site's stored zone when correcting (issue
  /// #137). Typing over a chosen zone clears it back to null
  /// (`AppSearchField`'s own contract), closing the submit gate in
  /// `_complete` — this field is the dialog's only display of the chosen
  /// zone, so a `_timezone` the field is no longer showing would post a zone
  /// nobody chose (ADR-0017).
  String? _timezone;

  bool _awaiting = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    if (site != null) {
      _code.text = site.code;
      _name.text = site.name;
      _countryCode.text = site.countryCode ?? '';
      _timezone = site.timezone.isEmpty ? null : site.timezone;
    }
    // Fetched once, here, when this dialog opens — never per keystroke.
    // `AppSearchField`'s own `fetchSuggestions` below only ever filters
    // whatever this fetch already landed.
    context.read<OrgUnitAdminBloc>().add(const OrgUnitAdminTimezonesRequested());
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _countryCode.dispose();
    super.dispose();
  }

  bool _complete(OrgUnitAdminState state) =>
      _code.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty &&
      _timezone != null &&
      _timezone!.trim().isNotEmpty &&
      // A failed timezone-list fetch blocks submission outright (issue
      // #127) — never falls back to accepting whatever `_timezone` already
      // held before the failure.
      state.timezoneStatus != OrgUnitAdminTimezoneStatus.failed;

  void _submit(OrgUnitAdminState state) {
    if (!_complete(state) || _awaiting) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    final countryCode = _countryCode.text.trim();
    final site = widget.site;
    final bloc = context.read<OrgUnitAdminBloc>();
    if (site == null) {
      bloc.add(
        OrgUnitAdminSiteCreated(
          code: _code.text.trim(),
          name: _name.text.trim(),
          timezone: _timezone!.trim(),
          countryCode: countryCode.isEmpty ? null : countryCode,
        ),
      );
    } else {
      bloc.add(
        OrgUnitAdminSiteUpdated(
          siteId: site.id,
          code: _code.text.trim(),
          name: _name.text.trim(),
          timezone: _timezone!.trim(),
          countryCode: countryCode.isEmpty ? null : countryCode,
        ),
      );
    }
  }

  Widget _buildTimezoneField(OrgUnitAdminState state) {
    switch (state.timezoneStatus) {
      case OrgUnitAdminTimezoneStatus.idle:
      case OrgUnitAdminTimezoneStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.md),
          child: LinearProgressIndicator(),
        );
      case OrgUnitAdminTimezoneStatus.failed:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          child: PlatformFailureState(
            title: 'Timezones unavailable',
            message: state.timezoneFailure ?? 'The timezone list could not be loaded.',
            retryKey: SiteFormDialog.timezoneRetryKey,
            onRetry: () =>
                context.read<OrgUnitAdminBloc>().add(const OrgUnitAdminTimezonesRequested()),
          ),
        );
      case OrgUnitAdminTimezoneStatus.ready:
        final zones = state.timezones;
        return AppSearchField<String>(
          name: SiteFormDialog._timezoneFieldName,
          label: 'Timezone',
          value: _timezone,
          enabled: !_awaiting,
          onChanged: (value) => setState(() => _timezone = value),
          onSelected: (zone) => setState(() => _timezone = zone),
          // A dumb in-memory filter over the list `initState` already
          // fetched — no HTTP request of its own, so `AppSearchField`'s
          // per-term debounce never reaches the wire (ADR-0023).
          fetchSuggestions: (term) async {
            final lower = term.toLowerCase();
            return [for (final zone in zones) if (zone.toLowerCase().contains(lower)) zone];
          },
          suggestionBuilder: (context, zone) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: Text(zone),
          ),
          idOf: (zone) => zone,
          displayStringFor: (zone) => zone,
        );
    }
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
      child: BlocBuilder<OrgUnitAdminBloc, OrgUnitAdminState>(
        builder: (context, state) => AlertDialog(
          title: Text(widget.site == null ? 'Add Site' : 'Edit Site'),
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
                  _buildTimezoneField(state),
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
              onPressed: _complete(state) && !_awaiting ? () => _submit(state) : null,
              child: Text(_awaiting ? 'Saving…' : (widget.site == null ? 'Add Site' : 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}
