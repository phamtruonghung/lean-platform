/// An Account waiting in the Approval queue, as the queue itself needs it.
library;

import 'package:flutter/foundation.dart';

import 'employee_ref.dart';

@immutable
class PendingAccount {
  const PendingAccount({
    required this.id,
    required this.email,
    required this.waitingSince,
    this.suggestedEmployee,
  });

  final String id;
  final String email;
  final DateTime waitingSince;

  /// The Employee this Account's email matched, when exactly one did and an
  /// administrator can actually act on it (issue #116, ADR-0022) — null both
  /// when nothing matched and when the match has Departed or is already
  /// linked, since a suggestion nobody can confirm is suppressed server-side
  /// rather than offered (`GET /accounts/pending`'s own `suggestedEmployee`).
  final EmployeeRef? suggestedEmployee;
}

String _plural(int count, String unit) => '$count $unit${count == 1 ? '' : 's'}';

/// "how long it has been waiting", in the coarsest unit that is still true.
String waitingFor(DateTime since, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(since);
  if (elapsed.inMinutes < 1) return 'Waiting less than a minute';
  if (elapsed.inHours < 1) return 'Waiting ${_plural(elapsed.inMinutes, 'minute')}';
  if (elapsed.inDays < 1) return 'Waiting ${_plural(elapsed.inHours, 'hour')}';
  return 'Waiting ${_plural(elapsed.inDays, 'day')}';
}
