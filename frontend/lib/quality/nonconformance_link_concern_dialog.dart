/// Linking a Non-conformance to a Concern that already exists (issue #208).
///
/// Addressed rather than popped — `/non-conformances/:id/link-concern`
/// (ADR-0021), for the same reasons the raise dialog beside it is.
///
/// **The picker is a search box, and the rule says so.** "One problem that
/// shows up several times is one Concern" is the sentence this dialog exists
/// for, so what it offers is the Site's open Concerns — a set a person cannot
/// scan and the server bounds (`ACTION_LIST_LIMIT`). `docs/frontend-layout.md`
/// §3 settles the control on the size of the set rather than on taste, so it is
/// an `AppSearchField` whose `fetchSuggestions` filters the list this dialog
/// already read, in memory: typing issues no request at all, and no endpoint
/// gains a `search` parameter for it (ADR-0023, issue #190's own rule).
///
/// **A Concern is chosen, never typed.** What the field reports is a record —
/// the Concern's own id — and the submit button stays closed until one is
/// picked, so the body this dialog sends always names a real Action. The write
/// itself is the Actions Module's: the link is an act on the *Concern* (one
/// problem answering several occurrences), so it is addressed at the Concern
/// and carries this record's id in the body. The answer is the Concern, and the
/// Screen re-reads this record on the Bloc's own `notice`.
///
/// The list is read once, when the dialog opens; a failure to read it is
/// `PlatformFailureState` with a retry rather than a fallback to free text,
/// because a Concern typed by hand is not a record anybody can link to.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../actions/actions.dart';
import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import 'nonconformance.dart';
import 'nonconformance_detail_bloc.dart';

class NonconformanceLinkConcernDialog extends StatefulWidget {
  const NonconformanceLinkConcernDialog({super.key, required this.nonconformance});

  final Nonconformance nonconformance;

  /// The one `AppSearchField` this dialog renders, named for its keys
  /// (AGENTS.md §7).
  static const String fieldName = 'link-concern';

  static const ValueKey<String> loadingKey =
      ValueKey<String>('nonconformance-link-concern-loading');
  static const ValueKey<String> submitKey = ValueKey<String>('nonconformance-link-concern-submit');
  static const ValueKey<String> cancelKey = ValueKey<String>('nonconformance-link-concern-cancel');
  static const ValueKey<String> failureKey =
      ValueKey<String>('nonconformance-link-concern-failure');
  static const ValueKey<String> loadFailedKey =
      ValueKey<String>('nonconformance-link-concern-load-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('nonconformance-link-concern-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('nonconformance-link-concern-empty');

  /// The search field's own `TextField`, and one suggestion row.
  static ValueKey<String> get concernFieldKey => AppSearchField.fieldKey(fieldName);

  static ValueKey<String> concernSuggestionKey(String id) =>
      AppSearchField.suggestionKey(fieldName, id);

  @override
  State<NonconformanceLinkConcernDialog> createState() =>
      _NonconformanceLinkConcernDialogState();
}

class _NonconformanceLinkConcernDialogState extends State<NonconformanceLinkConcernDialog> {
  /// The Site's open Concerns, as the action log sends them — read once, then
  /// filtered in memory.
  List<Action>? _concerns;
  String? _loadFailure;

  Action? _picked;
  bool _awaiting = false;
  bool _done = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthGateway>().currentAccessToken;
    if (token == null) {
      setState(() => _loadFailure = 'This session has ended. Sign in again to continue.');
      return;
    }
    setState(() {
      _loadFailure = null;
      _concerns = null;
    });
    try {
      final register = await context.read<ActionsApi>().fetchActions(
            token,
            siteId: widget.nonconformance.siteId,
          );
      if (!mounted) return;
      setState(() {
        // Only a Concern may be linked, and only one still being worked: a
        // Concern that is `done` or `cancelled` is not a problem anybody is
        // solving, so offering it would be offering a link the server would
        // take and no reader could act on.
        _concerns = [
          for (final action in register.actions)
            if (action.actionType == ActionType.concern.wire &&
                !const {'done', 'cancelled'}.contains(action.status))
              action,
        ];
      });
    } on ActionsApiException catch (error) {
      if (!mounted) return;
      setState(() => _loadFailure = error.message);
    }
  }

  /// The list this dialog already holds, narrowed by the term — never a
  /// request (ADR-0023's reading half).
  Future<List<Action>> _suggestions(String term) async {
    final concerns = _concerns ?? const <Action>[];
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return concerns;
    return [
      for (final concern in concerns)
        if (concern.actionNo.toLowerCase().contains(needle) ||
            concern.title.toLowerCase().contains(needle))
          concern,
    ];
  }

  bool get _complete => _picked != null && !_awaiting;

  void _submit() {
    final picked = _picked;
    if (!_complete || picked == null) return;
    setState(() {
      _awaiting = true;
      _failure = null;
    });
    context.read<NonconformanceDetailBloc>().add(
          NonconformanceConcernLinked(concernId: picked.id),
        );
  }

  void _onDetailChanged(BuildContext context, NonconformanceDetailState state) {
    if (_done || !_awaiting) return;
    if (state is! NonconformanceDetailLoaded) return;
    if (state.isLinkingConcern) return;
    final failure = state.concernLinkFailure;
    if (failure != null) {
      setState(() {
        _awaiting = false;
        _failure = failure;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.nonconformance;

    return BlocListener<NonconformanceDetailBloc, NonconformanceDetailState>(
      listener: _onDetailChanged,
      child: AlertDialog(
        title: const Text('Link it to a Concern'),
        content: SizedBox(
          width: 520,
          child: _loadFailure != null
              ? PlatformFailureState(
                  key: NonconformanceLinkConcernDialog.loadFailedKey,
                  title: 'The action log could not be read',
                  message: _loadFailure!,
                  retryKey: NonconformanceLinkConcernDialog.retryKey,
                  onRetry: _load,
                )
              : _concerns == null
                  ? const SizedBox(
                      height: 120,
                      child: SkeletonList(rows: 3, maxWidth: 520),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${record.issueNo} becomes one of the occurrences this Concern answers. '
                            'The Concern keeps the Non-conformance it was raised from.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: Spacing.md),
                          if (_concerns!.isEmpty)
                            Text(
                              key: NonconformanceLinkConcernDialog.emptyKey,
                              'This Site has no open Concern to link it to. Raise one instead.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            )
                          else
                            AppSearchField<Action>(
                              name: NonconformanceLinkConcernDialog.fieldName,
                              label: 'Concern',
                              helperText: 'By its number or its title.',
                              value: _picked,
                              enabled: !_awaiting,
                              fetchSuggestions: _suggestions,
                              idOf: (concern) => concern.id,
                              displayStringFor: (concern) =>
                                  '${concern.actionNo} · ${concern.title}',
                              suggestionBuilder: (context, concern) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(concern.title, style: theme.textTheme.bodyMedium),
                                  Text(
                                    '${concern.actionNo} · ${concern.statusLabel} · '
                                    '${concern.orgUnitName}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              onChanged: (concern) => setState(() => _picked = concern),
                              onSelected: (concern) => setState(() => _picked = concern),
                            ),
                          if (_failure != null)
                            Padding(
                              key: NonconformanceLinkConcernDialog.failureKey,
                              padding: const EdgeInsets.only(top: Spacing.md),
                              child: Text(
                                _failure!,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: theme.colorScheme.error),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
        actions: [
          TextButton(
            key: NonconformanceLinkConcernDialog.cancelKey,
            onPressed: _awaiting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: NonconformanceLinkConcernDialog.submitKey,
            onPressed: _complete ? _submit : null,
            child: const Text('Link it'),
          ),
        ],
      ),
    );
  }
}
