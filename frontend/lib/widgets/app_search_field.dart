import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'empty_state.dart';
import 'failure_state.dart';

/// The shared as-you-type suggestion box ADR-0023 introduces (issue #125):
/// a search box that offers the records it has found while a person types,
/// rather than making them commit to a term and press Enter to find out
/// whether anything matches. This is the second of ADR-0023's two shared
/// widgets — the first, `AppDateField` (issue #124), already exists
/// alongside this file. The three real call sites — the Directory (#128),
/// the Org Units admin screen (#130), the Employee link picker (#129) — are
/// deliberately out of scope here, exactly as retrofitting the four date
/// fields onto `AppDateField` was out of scope for #124: this file's own job
/// is to exist and be correct on its own, so behaviour cannot diverge across
/// three call sites that each wire it up separately.
///
/// **Generic over the suggestion record, [T].** The three eventual callers
/// render different shapes — an Employee row, an Org Unit row, a timezone
/// row — so this widget carries no assumption about what a suggestion looks
/// like. A caller supplies [fetchSuggestions] (a dumb async fetch: given a
/// term, return matching records — no timing logic of its own),
/// [suggestionBuilder] (how one record renders), [idOf] (how a record's
/// [ValueKey] is derived, for [suggestionKey]) and [displayStringFor] (how a
/// record renders as the field's own text, for seeding [value]'s initial
/// display).
///
/// **This widget owns ALL timing.** [fetchSuggestions] is never called
/// directly off a keystroke: typing debounces ~300ms, and nothing is fetched
/// below a 2-character minimum at all (ADR-0023 point 5) — not even after
/// the debounce elapses, since a 1-character term against an unindexed
/// `ILIKE` scan (ADR-0023's own "What this costs") is the single most
/// expensive query this widget could possibly issue. At most 10 suggestions
/// are ever rendered, even when [fetchSuggestions] returns more — bounding
/// happens here, not by trusting every caller's backend `limit` to agree.
///
/// **Out-of-order responses are discarded by issue order, not completion
/// order.** Every call to [fetchSuggestions] is tagged with a sequence
/// number at the moment it is *issued* — after the debounce fires and the
/// length check passes, never before. A response is applied to the screen
/// only if its own sequence is still the most recently issued one; an older
/// request's response arriving after a newer one has already resolved (or
/// is still pending) is silently dropped. This is a strict "last typed wins"
/// rule, not "last to arrive wins" — the two differ exactly when a network
/// reorders two in-flight requests, which is the one case worth a test
/// (`app_search_field_test.dart`'s out-of-order test).
///
/// **`onSelected` and the controlled `value`/`onChanged` pair are two
/// different things.** Tapping a suggestion calls [onSelected] with that
/// record and does nothing else — no text is written into the field, no
/// navigation happens, nothing beyond that one call. This widget carries no
/// `go_router` import and issues no navigation call anywhere, because the
/// three call sites each do something different with a pick (the Directory
/// navigates to the Employee, the link picker selects them into the form it
/// sits inside, the Org Units search reveals and selects the unit in its
/// tree) — deciding that here would bake one call site's job into a widget
/// meant to serve all three. [value]/[onChanged] instead exist for a
/// narrower job: displaying an already-chosen record when a caller is
/// editing an existing one, and reporting when that value has stopped being
/// usable. Two things inside this widget stop a value being usable — a
/// failed fetch, and typing over the chosen record's own text (both below) —
/// and both call [onChanged] with `null`, mirroring `AppDateField`'s own
/// "`null` means genuinely unset" contract, so a caller gating submission on
/// a selection can see the gate close without polling anything. Typed text
/// is never itself a value: this widget calls [onChanged] with a non-null
/// [T] nowhere in its own code — only a caller's own [onSelected] handler,
/// choosing to feed a pick back in as the new [value], can make it non-null
/// again.
///
/// **A failed fetch never falls back to free text** (ADR-0023 point 6):
/// [PlatformFailureState] replaces the suggestion list, its retry re-issues
/// [fetchSuggestions] for the same term, and the widget's reported [value]
/// stays `null` until a fresh selection is made. The message shown is a
/// fixed, already-written-for-a-person sentence rather than
/// `error.toString()` — [fetchSuggestions] is generic over [T] and this
/// widget cannot know the shape of whatever it throws, so, per
/// [PlatformFailureState]'s own doc comment on never showing raw exception
/// text, any thrown error is treated alike and shown as one sentence rather
/// than guessed at.
///
/// **Typing over a confirmed selection retires it.** While [value] is
/// non-null the text on screen is that record's own [displayStringFor]. A
/// keystroke that leaves the trimmed text no longer equal to it means the
/// person is searching again, not looking at their choice — so [onChanged]
/// is called with `null` at that keystroke, and the text itself is left
/// alone for them to carry on typing. Without this, a caller whose field is
/// the only place a choice is displayed would submit a value the field has
/// stopped showing: the Site timezone (#127) is exactly that shape —
/// `Europe/London` picked, `zzzz` typed over it, `Europe/London` posted —
/// which is the valid-but-wrong value ADR-0023 exists to remove, silently
/// moving that Site's production-day boundary (ADR-0017). This fires at most
/// once per confirmed selection: the report leaves [value] `null`, and a
/// `null` [value] has nothing to diverge from. Typing the same text back
/// does **not** restore the selection — picking a suggestion is the only
/// thing that ever sets one. Nor is this conditional on the caller: the
/// Directory (#128), the Employee link picker (#129) and the Org Units
/// search (#130) each pass [value] as `null` always, so no divergence is even
/// expressible there, and a per-caller flag would only make the hazard above
/// a supported configuration. What is *not* affected is a value seeded from
/// outside (ADR-0023 point 4's stored zone absent from the fetched list):
/// seeding, and re-seeding when [value] changes from outside, are untouched,
/// and no empty or failed suggestion list clears anything on its own.
///
/// A term of 2+ characters that resolves to zero records shows
/// [PlatformEmptyState.noneMatched] — records exist elsewhere, this term
/// simply matched none of them, which is exactly `noneMatched`'s own story
/// (never `noneExist`: this widget has no idea whether the backing
/// collection is itself empty).
///
/// [name] seeds [fieldKey]/[suggestionListKey]/[suggestionKey], the same
/// parameterised-key shape `AppDateField.fieldKey(name)` already uses
/// (AGENTS.md §7) — needed because the Org Units search and the Employee
/// link picker could each show more than one `AppSearchField` on screen at
/// once.
class AppSearchField<T> extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.name,
    required this.label,
    this.helperText,
    required this.value,
    required this.onChanged,
    required this.onSelected,
    required this.fetchSuggestions,
    required this.suggestionBuilder,
    required this.idOf,
    required this.displayStringFor,
    this.onSubmitted,
    this.enabled = true,
  });

  /// Identifies this field among any others on the same Screen (see this
  /// class's own doc comment).
  final String name;

  final String label;
  final String? helperText;

  /// The currently confirmed selection, or `null` — controlled the same way
  /// `AppDateField.value` is: this widget only ever asks to change it,
  /// through [onChanged]. Seeds the field's displayed text on first build
  /// via [displayStringFor], for a caller editing an existing record.
  /// Cleared by this widget when typing diverges from its own display
  /// string — see [onChanged].
  final T? value;

  /// Called with `null` when a fetch fails and [PlatformFailureState] is
  /// shown, and when typing diverges from the confirmed [value]'s own
  /// display string (see this class's own doc comment) — never called with a
  /// non-null [T] by this widget itself. A caller that wants [value] to
  /// track a pick does so from its own [onSelected] handler.
  final ValueChanged<T?> onChanged;

  /// Called with the tapped record when a suggestion is selected, and
  /// nothing else happens — see this class's own doc comment.
  final ValueChanged<T> onSelected;

  /// A dumb fetch: given a term, return the matching records. This widget
  /// owns every bit of timing (debounce, minimum length, discarding stale
  /// responses) — [fetchSuggestions] is never asked to do any of that
  /// itself. Throwing signals failure; see this class's own doc comment on
  /// how that renders.
  final Future<List<T>> Function(String term) fetchSuggestions;

  /// Renders one suggestion row's content. Wrapped by this widget in the
  /// tappable target that calls [onSelected] and carries [suggestionKey].
  final Widget Function(BuildContext context, T record) suggestionBuilder;

  /// A record's own identity, used to key its suggestion row
  /// ([suggestionKey]) — an Employee's `id`, an Org Unit's `id`, whatever
  /// [T] itself calls its identity.
  final Object Function(T record) idOf;

  /// How a record renders as plain text — seeds the field's displayed text
  /// from [value] on first build (and whenever [value] changes from outside
  /// this widget), and is what typed text is compared against to tell
  /// whether a confirmed selection is being typed over (this class's own doc
  /// comment). It is never *written* into the field during typing or while a
  /// suggestion list is showing.
  final String Function(T record) displayStringFor;

  /// Fired when the field's own submit action (Enter, or a keyboard's
  /// "search"/"done" action) is pressed — carrying whatever text is on
  /// screen at that moment, trimmed. This is the Directory's own "commit to
  /// this term and filter the list" action (issue #128), which survives
  /// alongside suggestions rather than being replaced by them (ADR-0023
  /// point 5's own "an addition, not a replacement"). Left null for a caller
  /// with nothing to do on submit, e.g. the timezone field (#127), which is
  /// something to *pick*, never something to *filter with*.
  ///
  /// Not a bare pass-through of `TextField.onSubmitted`: a pending debounce
  /// is cancelled and any suggestions already on screen are collapsed back
  /// to idle immediately beforehand (`_AppSearchFieldState._handleSubmitted`)
  /// — a caller wiring this up is, by definition, about to change what
  /// renders beneath this field on its own terms, so a suggestion for the
  /// same term hanging around (or a debounced fetch still in flight landing
  /// a moment later) would otherwise show the same match twice over.
  final ValueChanged<String>? onSubmitted;

  final bool enabled;

  /// The field's own `Key` (AGENTS.md §7) — a test finds and enters text
  /// through this, never an ad hoc `Key`.
  static ValueKey<String> fieldKey(String name) => ValueKey<String>('app-search-field-$name');

  /// The suggestion list's own `Key`, present only while suggestions are
  /// actually showing.
  static ValueKey<String> suggestionListKey(String name) =>
      ValueKey<String>('app-search-field-$name-list');

  /// One suggestion row's own `Key`, keyed by [idOf]'s own return value —
  /// the same shape as `AssetsScreen.rowKey(id)` (AGENTS.md §7).
  static ValueKey<String> suggestionKey(String name, Object id) =>
      ValueKey<String>('app-search-field-$name-suggestion-$id');

  /// The retry button's own `Key`, present only while
  /// [PlatformFailureState] is showing.
  static ValueKey<String> retryKey(String name) => ValueKey<String>('app-search-field-$name-retry');

  @override
  State<AppSearchField<T>> createState() => _AppSearchFieldState<T>();
}

/// What the box below the field is currently showing. Never `idle` and
/// something else at once — [_AppSearchFieldState.build] switches on exactly
/// one of these.
enum _SuggestStatus { idle, loading, results, empty, failure }

class _AppSearchFieldState<T> extends State<AppSearchField<T>> {
  static const int _minLength = 2;
  static const int _maxSuggestions = 10;
  static const Duration _debounceDuration = Duration(milliseconds: 300);
  static const String _failureMessage =
      "Couldn't load suggestions. Check your connection and try again.";

  late final TextEditingController _controller = TextEditingController(
    text: widget.value == null ? '' : widget.displayStringFor(widget.value as T),
  );

  Timer? _debounceTimer;

  /// Bumped every time a fetch is *issued* (after the debounce fires and the
  /// minimum length check passes) — the sequence number a response is
  /// compared against before being applied, per this class's own doc comment
  /// on out-of-order responses. Also bumped when typing drops back below
  /// [_minLength], so an already in-flight fetch from a longer term can
  /// never land after the fact.
  int _requestSeq = 0;

  _SuggestStatus _status = _SuggestStatus.idle;
  List<T> _suggestions = const [];
  String _lastQueriedTerm = '';

  /// Set immediately before this widget calls [AppSearchField.onChanged]
  /// itself (see this class's own doc comment on [_reportNoUsableValue]), so
  /// [didUpdateWidget] can tell its own report apart from a caller changing
  /// [AppSearchField.value] for some other reason and skip re-seeding
  /// [_controller]'s text — re-seeding on our own report would wipe out
  /// whatever a person is mid-typing at the moment their earlier search
  /// failed.
  bool _selfReportedChange = false;

  @override
  void didUpdateWidget(covariant AppSearchField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selfReportedChange) {
      _selfReportedChange = false;
      return;
    }
    if (widget.value != oldWidget.value) {
      final value = widget.value;
      _controller.text = value == null ? '' : widget.displayStringFor(value);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _reportNoUsableValue() {
    // Nothing to unset, and nothing for `didUpdateWidget` to skip re-seeding
    // for — setting `_selfReportedChange` here would leave it stuck true for
    // a caller whose `value` is always null (three of the four call sites),
    // swallowing a later genuine outside change.
    if (widget.value == null) return;
    _selfReportedChange = true;
    widget.onChanged(null);
  }

  /// Retires a confirmed [AppSearchField.value] the moment the text stops
  /// being that record's own display string — see this class's own doc
  /// comment. Fires at most once per confirmed value: the report leaves
  /// [AppSearchField.value] `null`, and a `null` value has nothing left to
  /// diverge from, so every later keystroke falls out on the first line via
  /// [_reportNoUsableValue]'s own guard.
  void _clearValueIfTextDiverged(String text) {
    final value = widget.value;
    if (value == null) return;
    if (text.trim() == widget.displayStringFor(value).trim()) return;
    _reportNoUsableValue();
  }

  void _handleTextChanged(String text) {
    _clearValueIfTextDiverged(text);
    _debounceTimer?.cancel();
    final term = text.trim();
    if (term.length < _minLength) {
      // Invalidate any fetch already in flight from a longer term — see
      // `_requestSeq`'s own doc comment.
      _requestSeq++;
      setState(() {
        _status = _SuggestStatus.idle;
        _suggestions = const [];
      });
      return;
    }
    _debounceTimer = Timer(_debounceDuration, () => _issueFetch(term));
  }

  Future<void> _issueFetch(String term) async {
    final mySeq = ++_requestSeq;
    _lastQueriedTerm = term;
    setState(() => _status = _SuggestStatus.loading);
    List<T> results;
    try {
      results = await widget.fetchSuggestions(term);
    } catch (_) {
      if (!mounted || mySeq != _requestSeq) return;
      setState(() => _status = _SuggestStatus.failure);
      _reportNoUsableValue();
      return;
    }
    if (!mounted || mySeq != _requestSeq) return;
    final bounded = results.take(_maxSuggestions).toList(growable: false);
    setState(() {
      _suggestions = bounded;
      _status = bounded.isEmpty ? _SuggestStatus.empty : _SuggestStatus.results;
    });
  }

  void _retry() {
    _debounceTimer?.cancel();
    _issueFetch(_lastQueriedTerm);
  }

  void _select(T record) {
    widget.onSelected(record);
  }

  /// Handles the field's own submit action (Enter, or a keyboard's "search"
  /// action) when a caller supplies [AppSearchField.onSubmitted] — the
  /// Directory (#128) is the first, and so far only, caller that does.
  ///
  /// A pending debounce is cancelled and any suggestions already on screen
  /// are collapsed back to idle before [AppSearchField.onSubmitted] itself
  /// runs: committing to a term is this field's caller taking over — the
  /// Directory re-reads its whole listing narrowed to this term — so a
  /// suggestion box for the same term hanging around (or a debounced fetch
  /// still in flight landing a moment later) would show the same match twice
  /// over, once as a suggestion and once as the row the narrowed listing now
  /// renders. Bumping `_requestSeq` here, the same device `_handleTextChanged`
  /// uses when typing drops back below the minimum length, is what stops an
  /// already in-flight fetch from landing after this and reopening the box.
  void _handleSubmitted(String text) {
    _debounceTimer?.cancel();
    _requestSeq++;
    setState(() {
      _status = _SuggestStatus.idle;
      _suggestions = const [];
    });
    widget.onSubmitted!(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: AppSearchField.fieldKey(widget.name),
          controller: _controller,
          enabled: widget.enabled,
          onChanged: _handleTextChanged,
          onSubmitted: widget.onSubmitted == null ? null : _handleSubmitted,
          textInputAction: widget.onSubmitted == null ? TextInputAction.done : TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
            ),
          ),
        ),
        switch (_status) {
          _SuggestStatus.idle => const SizedBox.shrink(),
          _SuggestStatus.loading => const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.sm),
              child: LinearProgressIndicator(),
            ),
          _SuggestStatus.results => _buildResults(),
          _SuggestStatus.empty => Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              child: PlatformEmptyState.noneMatched(
                title: 'No matches',
                message: 'Nothing matched "$_lastQueriedTerm" — try a different term.',
              ),
            ),
          _SuggestStatus.failure => Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              child: PlatformFailureState(
                title: 'Search failed',
                message: _failureMessage,
                retryKey: AppSearchField.retryKey(widget.name),
                onRetry: _retry,
              ),
            ),
        },
      ],
    );
  }

  Widget _buildResults() {
    return ConstrainedBox(
      key: AppSearchField.suggestionListKey(widget.name),
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final record = _suggestions[index];
          return InkWell(
            key: AppSearchField.suggestionKey(widget.name, widget.idOf(record)),
            onTap: widget.enabled ? () => _select(record) : null,
            child: widget.suggestionBuilder(context, record),
          );
        },
      ),
    );
  }
}
