import 'package:flutter/material.dart';

/// The shared date-and-time control for a Postgres `timestamptz` (issue #73):
/// the same "a value with a known set is chosen, never typed" rule ADR-0023
/// applies to `DATE`, widened by the one thing a `DATE` field does not have —
/// a time of day. The Downtime report's optional start and close's optional
/// end are the first two call sites.
///
/// **Controlled, not stateful about its own value.** [value] and [onChanged]
/// mirror [AppDateField]'s own shape: the caller owns the instant, this widget
/// only ever asks to change it. [onChanged] is called with a `DateTime` in the
/// device's local time when a date and a time are both picked, and with `null`
/// when the clear affordance is used — never a defaulted instant.
///
/// **Read-only.** The text field never accepts keyboard input; tapping it
/// anywhere opens [showDatePicker] and then [showTimePicker]. Cancelling either
/// picker leaves [value] untouched, so a half-made change is never recorded.
///
/// **No `intl` dependency.** The `YYYY-MM-DD HH:mm` display is formatted by
/// hand, the same choice [AppDateField] makes for its own `YYYY-MM-DD`.
class AppDateTimeField extends StatefulWidget {
  const AppDateTimeField({
    super.key,
    required this.name,
    required this.label,
    this.helperText,
    required this.value,
    required this.onChanged,
    this.optional = false,
    this.enabled = true,
  });

  /// Identifies this field among any others on the same form (see this
  /// class's own doc comment).
  final String name;

  final String label;
  final String? helperText;

  /// The current value in local time — null means genuinely unset, never a
  /// defaulted instant.
  final DateTime? value;

  /// Called with the newly chosen local [DateTime], or with `null` when the
  /// clear affordance is used.
  final ValueChanged<DateTime?> onChanged;

  /// Optional mode shows a trailing clear (✕) once [value] is set.
  final bool optional;

  final bool enabled;

  /// The field's own `Key` (AGENTS.md §7) — a test finds and taps the field
  /// through this, never an ad hoc `Key`.
  static ValueKey<String> fieldKey(String name) => ValueKey<String>('app-date-time-field-$name');

  /// The clear button's own `Key`, shown only in optional mode once a value
  /// is set.
  static ValueKey<String> clearKey(String name) =>
      ValueKey<String>('app-date-time-field-$name-clear');

  /// The calendar icon's own `Key` — shown whenever the clear button's own
  /// slot is free, so a test targets whichever of the two is on screen.
  static ValueKey<String> calendarIconKey(String name) =>
      ValueKey<String>('app-date-time-field-$name-calendar');

  @override
  State<AppDateTimeField> createState() => _AppDateTimeFieldState();
}

class _AppDateTimeFieldState extends State<AppDateTimeField> {
  late final TextEditingController _controller = TextEditingController(text: _display(widget.value));

  @override
  void didUpdateWidget(covariant AppDateTimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = _display(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _display(DateTime? value) {
    if (value == null) return '';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}';
  }

  Future<void> _openPicker() async {
    if (!widget.enabled) return;
    final now = DateTime.now();
    final initial = widget.value ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    widget.onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null;
    final showClear = widget.optional && hasValue && widget.enabled;

    return TextField(
      key: AppDateTimeField.fieldKey(widget.name),
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
                key: AppDateTimeField.clearKey(widget.name),
                icon: const Icon(Icons.close),
                tooltip: 'Clear',
                onPressed: () => widget.onChanged(null),
              )
            : IconButton(
                key: AppDateTimeField.calendarIconKey(widget.name),
                icon: const Icon(Icons.event_outlined),
                tooltip: 'Choose a date and time',
                onPressed: widget.enabled ? _openPicker : null,
              ),
      ),
    );
  }
}
