/// How a Shift handover's times and numbers read on screen (issue #339).
/// Formatting only: every value is the server's, shown as it was sent.
library;

/// A wall-clock time, `HH:mm`, in the reader's own zone.
String formatClock(String? iso) {
  if (iso == null) return '—';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// A span of minutes as hours and minutes: `95` → `1 h 35 min`.
String formatMinutes(num minutes) {
  final whole = minutes.round();
  if (whole < 60) return '$whole min';
  final hours = whole ~/ 60;
  final rest = whole % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// A ratio the server stores as a fraction, as a percentage to one place.
String formatPercent(num ratio) => '${(ratio * 100).toStringAsFixed(1)}%';
