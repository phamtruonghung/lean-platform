/// `people/period_format.dart` — a wire date and a period, worded the way a
/// person says them (`docs/design-language.md` §13).
///
/// These are unit tests rather than widget tests on purpose: what is asserted is
/// a string this client renders, not a behaviour a caller observes through the
/// UI. The two cost registers that spend the formatter assert the *rendered*
/// result, which is the seam AGENTS.md §5 asks for; this pins the twelve month
/// names, the leap day and the three ways a value can fail to be a date.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lean_platform/people/period_format.dart';

void main() {
  test('a wire date is worded the way a person says it', () {
    expect(formatWireDate('2026-01-31'), '31 Jan 2026');
    expect(formatWireDate('2026-10-05'), '5 Oct 2026');
    expect(formatWireDate('2024-02-29'), '29 Feb 2024');
    for (var month = 1; month <= 12; month++) {
      final wire = '2026-${month.toString().padLeft(2, '0')}-01';
      expect(formatWireDate(wire), startsWith('1 '));
      expect(formatWireDate(wire), isNot(contains('-')));
    }
  });

  test('a value that is not a calendar date comes back unchanged', () {
    // Not a date at all: shown as the API sent it, never re-worded into one.
    expect(formatWireDate('31/01/2026'), '31/01/2026');
    expect(formatWireDate('not a date'), 'not a date');
    // A date that does not exist is not a date.
    expect(formatWireDate('2026-02-30'), '2026-02-30');
    expect(formatWireDate('2025-02-29'), '2025-02-29');
    expect(formatWireDate('2026-13-01'), '2026-13-01');
    expect(formatWireDate('2026-00-10'), '2026-00-10');
  });

  test('nothing versus zero: a missing date is a dash, never blank', () {
    expect(formatWireDate(null), '—');
    expect(formatWireDate(''), '—');
    expect(formatWireDate('   '), '—');
  });

  test('an open period says From, a closed one names both ends', () {
    expect(formatPeriod(from: '2026-01-01'), 'From 1 Jan 2026');
    expect(formatPeriod(from: '2026-01-01', to: '2026-12-31'), '1 Jan 2026 – 31 Dec 2026');
    // A to-date the client cannot read is shown as sent, not invented.
    expect(formatPeriod(from: '2026-01-01', to: 'someday'), '1 Jan 2026 – someday');
  });
}
