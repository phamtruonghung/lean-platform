import 'package:flutter/material.dart';

/// The shared date control ADR-0023 introduces (issue #124): a field backed
/// by a Postgres `DATE` is chosen from a picker, never typed. This is the
/// first `showDatePicker` call anywhere under `frontend/lib/` — the four
/// existing date fields (`employee_assignment_dialog.dart`,
/// `employee_departure_dialog.dart`, `employee_skill_form_dialog.dart`'s
/// assessed-on and expires-on) each still hand-roll a raw `TextField` today;
/// retrofitting them onto this widget is #126, deliberately out of scope
/// here so that change stays small and cannot diverge across the four call
/// sites.
///
/// **Controlled, not stateful about its own value.** [value] and [onChanged]
/// mirror the shape every Bloc-driven form in this app already uses
/// (`EmployeeAssignmentDialog`'s own `TextEditingController` fields, just
/// promoted to a widget): the caller owns the date, this widget only ever
/// asks to change it. [onChanged] is called with a `YYYY-MM-DD` string when
/// a date is picked, and with `null` when the clear affordance is used —
/// never a defaulted date. A `null`/empty [value] and a freshly cleared one
/// are the same state on the wire (blank), which is exactly the point of the
/// clear affordance: three of this ticket's four eventual call sites let the
/// server record today, or re-derive the value, when the field is blank
/// (ADR-0023).
///
/// **Read-only.** The text field never accepts keyboard input; tapping it
/// anywhere opens [showDatePicker]. This is what makes "must show a picker"
/// enforceable as a test at all (ADR-0023's own "Why not the alternatives").
///
/// **No `intl` dependency.** `YYYY-MM-DD` is formatted by hand in [_format]
/// — the same format the wire already carries, so a caller keeps sending
/// exactly what it sends today.
///
/// **A calendar icon marks the field as tappable whenever the clear button
/// is not already occupying that slot** — required mode always, and optional
/// mode while [value] is unset. Without it, a read-only `TextField` reads as
/// a plain or disabled text field: nothing tells a person the label is a
/// button, and because it refuses keyboard input, someone who tries to type
/// into it anyway is simply stuck with no cue toward what to do instead —
/// worse than the mistyped date this widget exists to remove. The two
/// affordances never stack: once a value is set in optional mode the ✕ is
/// the action that matters, and the field itself stays tappable to re-pick,
/// so showing both would just be noise in the same slot.
///
/// [name] seeds [fieldKey]/[clearKey]/[calendarIconKey] so two
/// `AppDateField`s living in the same form (`EmployeeSkillFormDialog`'s
/// assessed-on and expires-on, once #126 lands) get distinct, stable keys
/// without each call site inventing its own — the same reason
/// `AssetsScreen.rowKey(id)` takes a parameter rather than being a bare
/// constant (AGENTS.md §7).
class AppDateField extends StatefulWidget {
  const AppDateField({
    super.key,
    required this.name,
    required this.label,
    this.helperText,
    required this.value,
    required this.onChanged,
    this.optional = false,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  /// Identifies this field among any others on the same form (see this
  /// class's own doc comment).
  final String name;

  final String label;
  final String? helperText;

  /// The current value, as `YYYY-MM-DD` — null or empty means genuinely
  /// unset, never a defaulted date.
  final String? value;

  /// Called with the newly chosen `YYYY-MM-DD` string, or with `null` when
  /// the clear affordance is used.
  final ValueChanged<String?> onChanged;

  /// Optional mode shows a trailing clear (✕) once [value] is set; required
  /// mode never shows one (ADR-0023 point 2) — there is nothing to clear
  /// back to, since a required field has no meaningful blank state.
  final bool optional;

  /// Bounds passed straight to [showDatePicker]. Left unset, they default to
  /// a century either side of today — wide enough for a birth date or a
  /// far-future expiry without a caller having to think about it.
  final DateTime? firstDate;
  final DateTime? lastDate;

  final bool enabled;

  /// The field's own `Key` (AGENTS.md §7) — a test finds and taps the field
  /// through this, never an ad hoc `Key`.
  static ValueKey<String> fieldKey(String name) => ValueKey<String>('app-date-field-$name');

  /// The clear button's own `Key`, shown only in optional mode once a value
  /// is set — see [optional].
  static ValueKey<String> clearKey(String name) => ValueKey<String>('app-date-field-$name-clear');

  /// The calendar icon's own `Key` — shown whenever [clearKey]'s button is
  /// not (see this class's own doc comment), so a test targets whichever of
  /// the two is actually on screen rather than guessing.
  static ValueKey<String> calendarIconKey(String name) =>
      ValueKey<String>('app-date-field-$name-calendar');

  @override
  State<AppDateField> createState() => _AppDateFieldState();
}

class _AppDateFieldState extends State<AppDateField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant AppDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime? get _parsedValue {
    final value = widget.value;
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _format(DateTime date) {
    String pad(int n, int width) => n.toString().padLeft(width, '0');
    return '${pad(date.year, 4)}-${pad(date.month, 2)}-${pad(date.day, 2)}';
  }

  Future<void> _openPicker() async {
    if (!widget.enabled) return;
    final today = DateTime.now();
    final firstDate = widget.firstDate ?? DateTime(today.year - 100);
    final lastDate = widget.lastDate ?? DateTime(today.year + 100);
    final initialDate = _parsedValue ?? DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    widget.onChanged(_format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null && widget.value!.isNotEmpty;
    final showClear = widget.optional && hasValue && widget.enabled;

    return TextField(
      key: AppDateField.fieldKey(widget.name),
      controller: _controller,
      readOnly: true,
      enabled: widget.enabled,
      onTap: _openPicker,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        border: const OutlineInputBorder(),
        suffixIcon: showClear
            ? IconButton(
                key: AppDateField.clearKey(widget.name),
                icon: const Icon(Icons.close),
                tooltip: 'Clear',
                // Reports genuine empty, not today and not a default — the
                // whole reason ADR-0023 asks for an explicit clear affordance
                // rather than letting a picker-only field get stuck on
                // whatever it last held.
                onPressed: () => widget.onChanged(null),
              )
            // The calendar icon: the same trailing slot the ✕ would
            // otherwise occupy, shown whenever the ✕ is not — see this
            // class's own doc comment on why a read-only field needs a
            // visible cue that it is tappable at all.
            : IconButton(
                key: AppDateField.calendarIconKey(widget.name),
                icon: const Icon(Icons.calendar_today_outlined),
                tooltip: 'Choose a date',
                onPressed: widget.enabled ? _openPicker : null,
              ),
      ),
    );
  }
}
