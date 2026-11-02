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

/// How far through a shift the reader is, as the fraction the position bar
/// fills: 0 before it starts, 1 after it ends, and the elapsed share between.
///
/// Null when either end of the shift is missing or unparsable — a bar with no
/// span to divide is not a bar half full, it is nothing to draw, and the reader
/// is given the words instead.
///
/// This is the one place the client reads its own clock to describe the day, so
/// it is the one place that says what "now" means: the reader's own instant, the
/// same instant [formatClock] prints a shift boundary in. It decides nothing
/// about the shift — the server's flags, latency and exceptions are untouched.
double? shiftProgressFraction(DateTime now, String? startsAt, String? endsAt) {
  final start = _instant(startsAt);
  final end = _instant(endsAt);
  if (start == null || end == null || !end.isAfter(start)) return null;
  if (now.isBefore(start)) return 0;
  if (!now.isBefore(end)) return 1;
  return now.difference(start).inSeconds / end.difference(start).inSeconds;
}

/// Where in a shift the reader is, in words: `2 h 10 min in · 5 h 50 min to go`,
/// `Starts in 3 h`, `Ended 1 h 35 min ago`, or `—` when the shift has no span.
String formatShiftProgress(DateTime now, String? startsAt, String? endsAt) {
  final start = _instant(startsAt);
  final end = _instant(endsAt);
  if (start == null || end == null || !end.isAfter(start)) return '—';
  if (now.isBefore(start)) return 'Starts in ${formatMinutes(start.difference(now).inMinutes)}';
  if (!now.isBefore(end)) return 'Ended ${formatMinutes(now.difference(end).inMinutes)} ago';
  return '${formatMinutes(now.difference(start).inMinutes)} in · '
      '${formatMinutes(end.difference(now).inMinutes)} to go';
}

DateTime? _instant(String? iso) => iso == null ? null : DateTime.tryParse(iso)?.toLocal();
