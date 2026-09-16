/// The second of this client's two search controls (issue #187): a box that
/// narrows rows its caller is already showing.
///
/// **The two controls, and why there are two.** `AppSearchField` (ADR-0023,
/// issue #125) *suggests records it fetches against the server as you type* and
/// reports a pick to its caller — it exists so that a value the system knows
/// the set of is chosen rather than typed. This widget does the opposite job:
/// it narrows rows the caller already has on screen and reports only the term,
/// learning nothing about what those rows are. The distinction is what keeps
/// each one honest about what it can promise — a suggestion box fetches, so it
/// can offer rows a caller does not hold and cannot count what it did not fetch;
/// a filter fetches nothing, so it can say "showing 3 of 340" and cannot report
/// a pick into a form. `AGENTS.md` §7 names both, so the next agent reaches for
/// the right one.
///
/// **It is deliberately not a `TextField` wrapper that filters for you.** This
/// widget never sees the rows: matching is the caller's, because what identifies
/// a record is the record's own business (an Asset's name and code, an
/// Employee's display name and number, a Work order's summary and its Asset).
/// A widget that took a `List<T>` and a matcher would be a `List.where` with a
/// text field attached, and would have to decide what "matches" means for every
/// caller.
///
/// **The count line appears only while a term is set.** "Showing 340 of 340" is
/// noise that reads as a bound nobody hit; the line exists to tell a reader that
/// the list they are looking at is *narrowed*, which is only true once it is.
/// Its spacing is reserved by nothing — the line arrives and leaves with the
/// term, the same way `AppSearchField`'s own suggestion box does.
///
/// **It is controlled, the same shape `AppDateField`/`AppSearchField` are.** The
/// term lives in the caller's state and is passed down as [term]; this widget
/// seeds its own controller from it, re-seeds only when the caller's term has
/// genuinely changed from what is on screen (so echoing the term back at us on
/// every keystroke never moves the caret), and asks the caller to change it
/// through [onChanged] — including with `''` from the clear affordance.
///
/// **The clear (✕) affordance is shown only while a term is set**, and is an
/// `IconButton` rather than a tap target on the field's own trailing area, so it
/// is reachable by keyboard and announced as a button ("Clear") rather than as
/// an unlabelled glyph.
///
/// **Every call site shares one wording for the count** — [countLabel] — so two
/// Screens cannot phrase the same fact differently, the same reason
/// `DirectoryScreen`'s subtitle helper is shared between its list and its
/// suggestions.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class AppFilterField extends StatefulWidget {
  const AppFilterField({
    super.key,
    required this.name,
    required this.label,
    required this.term,
    required this.onChanged,
    this.helperText,
    this.shown,
    this.total,
    this.enabled = true,
  });

  /// Identifies this field among any others on the same Screen — the
  /// `AppDateField`/`AppSearchField` parameterised-key shape (AGENTS.md §7), so
  /// a Screen with two filters can tell them apart in a test.
  final String name;

  /// What the box narrows, in the reader's words — "Find a person", "Filter
  /// Assets". It is the field's own label, not a placeholder: a placeholder
  /// disappears the moment it is needed.
  final String label;

  final String? helperText;

  /// The term currently narrowing the caller's rows, `''` when nothing is
  /// narrowing them. Controlled: this widget only ever asks to change it.
  final String term;

  final ValueChanged<String> onChanged;

  /// How many rows the caller is showing, and how many it holds. Both must be
  /// given for the count line to render, and it renders only while [term] is
  /// non-empty — see this class's own doc comment. A caller that cannot count
  /// its rows (because only some of them are on screen) passes neither and gets
  /// a plain filter box.
  final int? shown;
  final int? total;

  final bool enabled;

  /// The field's own `Key`.
  static ValueKey<String> fieldKey(String name) => ValueKey<String>('app-filter-field-$name');

  /// The clear affordance's `Key`, present only while a term is set.
  static ValueKey<String> clearKey(String name) => ValueKey<String>('app-filter-field-$name-clear');

  /// The count line's `Key`, present only while a term is set and both counts
  /// were given.
  static ValueKey<String> countKey(String name) => ValueKey<String>('app-filter-field-$name-count');

  /// The count line's text, in one place so every call site says it the same
  /// way — and so a test can assert it without hard-coding the wording.
  static String countLabel(int shown, int total) => 'Showing $shown of $total';

  @override
  State<AppFilterField> createState() => _AppFilterFieldState();
}

class _AppFilterFieldState extends State<AppFilterField> {
  late final TextEditingController _controller = TextEditingController(text: widget.term);

  @override
  void didUpdateWidget(covariant AppFilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the caller's term differs from what is on screen: a caller
    // echoing our own report back at us every keystroke must not have its caret
    // moved, and a caller clearing the term (the ✕) must.
    if (widget.term != _controller.text) {
      _controller.text = widget.term;
      _controller.selection = TextSelection.collapsed(offset: widget.term.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTerm = widget.term.isNotEmpty;
    final counts = widget.shown != null && widget.total != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: AppFilterField.fieldKey(widget.name),
          controller: _controller,
          enabled: widget.enabled,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            prefixIcon: const Icon(Icons.search),
            // The same pill as `AppSearchField`, so the platform's two search
            // controls read as the same kind of thing.
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
            ),
            suffixIcon: hasTerm
                ? IconButton(
                    key: AppFilterField.clearKey(widget.name),
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: widget.enabled ? () => widget.onChanged('') : null,
                  )
                : null,
          ),
        ),
        if (hasTerm && counts)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              AppFilterField.countLabel(widget.shown!, widget.total!),
              key: AppFilterField.countKey(widget.name),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
