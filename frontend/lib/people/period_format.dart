/// A wire date, and a period made of two, worded the way a person says them.
///
/// `docs/design-language.md` section 13 rules that a date is **`31 Oct 2026`,
/// never `2026-10-31`**, and that "where a rule below has no helper, the
/// adopting slice owes one, in the module that needs it, written the same way
/// and tested the same way". The four formatters the document names format a
/// timestamp (`formatEnteredAt`, `formatRequestDate`), a clock, a duration and a
/// percentage — none of them takes the bare calendar date an
/// `effective_from`/`effective_to` pair is. This is that missing one, and the
/// two cost catalogues (issues #252, #392) are the slice that owes it: a rate's
/// period is the first date range a reader compares down a column.
///
/// It formats; it never parses into a domain value. `employee.dart` and the
/// backend's own `toDateString` both keep a DATE column as the string the wire
/// sent, for the reason `directory.js`'s own header gives, and this function
/// keeps that discipline: it reads the three parts out of a `YYYY-MM-DD`
/// string, and hands anything else back unchanged rather than inventing a date
/// out of a value that is not one. A `null` to-date is "still in force" and is
/// the caller's business — [formatPeriod] is what words it.
library;

/// The months as the Platform spells them: three letters, then nothing —
/// narrow enough to sit in a register cell at twice the text, and unambiguous
/// in the twelve the plant reads.
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2026-01-31` as `31 Jan 2026`; anything that is not a `YYYY-MM-DD` calendar
/// date back unchanged.
///
/// "Back unchanged" is the rule for an unreadable value, the same one
/// `maintenance/request.dart`'s `formatRequestDate` follows: a value this
/// client cannot read is shown as the API sent it rather than as a date this
/// client made up. A date that does not exist (`2026-02-31`) is treated the
/// same way — it is not a calendar date, so it is not re-worded.
String formatWireDate(String? wire) {
  final text = wire?.trim();
  if (text == null || text.isEmpty) return '—';
  final parts = text.split('-');
  if (parts.length != 3) return text;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return text;
  if (month < 1 || month > 12) return text;
  if (day < 1 || day > _daysIn(year, month)) return text;
  return '$day ${_months[month - 1]} $year';
}

/// How many days [month] of [year] has, so a date that does not exist is
/// recognised as one instead of being worded into `31 Feb 2026`.
int _daysIn(int year, int month) {
  const thirty = [4, 6, 9, 11];
  if (month == 2) {
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return leap ? 29 : 28;
  }
  return thirty.contains(month) ? 30 : 31;
}

/// A rate's or a cost's period: `From 31 Jan 2026` while it still applies, and
/// `31 Jan 2026 – 31 Dec 2026` once it is closed.
///
/// The open case is worded `From …` rather than `… – —` because "still in
/// force" is a fact about the record, not a missing value: the register's own
/// State column is what says a closed period is closed, and a dash in the
/// second half would read as an unknown (section 13's "nothing versus zero").
String formatPeriod({required String from, String? to}) =>
    to == null ? 'From ${formatWireDate(from)}' : '${formatWireDate(from)} – ${formatWireDate(to)}';
