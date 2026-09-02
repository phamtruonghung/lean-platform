/// An Account waiting in the Approval queue, as the queue itself needs it.
library;

import 'package:flutter/foundation.dart';

@immutable
class PendingAccount {
  const PendingAccount({
    required this.id,
    required this.email,
    required this.waitingSince,
  });

  final String id;
  final String email;
  final DateTime waitingSince;
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
