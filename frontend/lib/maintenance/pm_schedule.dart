/// One PM schedule as `GET /api/maintenance/sites/:siteId/pm-schedules`
/// sends it (issue #74).
///
/// CONTEXT.md's own line is the point of this model: a PM schedule is what
/// raises a Work order before something breaks, rather than in response to
/// one. Both mechanisms its entry names are carried: elapsed time in days, and
/// accumulated use through a meter — and a schedule may run on either. The
/// server computes the meter's current accumulated use and whether it has
/// reached the target, so the client never re-derives the rollover offset
/// (ADR-0029).
///
/// A schedule is scoped from its Asset, exactly like a Work order: it carries
/// no Org Unit of its own, and the server resolves one by joining through the
/// Asset, so both the flattening and the placement arrive on the row already.
library;

import 'package:flutter/foundation.dart';

/// What a PM schedule's interval rolls from, mirroring the CHECK constraint
/// on `pm_schedules.anchor` and `pm-schedules.js`'s own `resolveAnchor`. The
/// two differ exactly when work runs late:
///
/// - [due]: the obligation is fixed, so the following one rolls from the
///   original due date — doing a statutory inspection three weeks late does
///   not push next year's date back.
/// - [completed]: the clock starts when the work was actually done, so a
///   service done late simply slides.
enum PmScheduleAnchor {
  due(
    'due',
    'Due date',
    'The next date is fixed to the calendar: doing the work late does not '
        'push the following one back.',
  ),
  completed(
    'completed',
    'Completion',
    'The clock starts when the work was actually done, so a service done late '
        'simply slides.',
  );

  const PmScheduleAnchor(this.wire, this.label, this.explanation);

  final String wire;
  final String label;

  /// The short explanation of how this choice behaves when work runs late —
  /// the reason the two options exist at all.
  final String explanation;
}

@immutable
class PmSchedule {
  const PmSchedule({
    required this.id,
    required this.code,
    required this.name,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.jobPlanId,
    required this.jobPlanName,
    required this.intervalDays,
    required this.anchor,
    required this.leadTimeDays,
    required this.priority,
    required this.lastCompletedOn,
    required this.nextDueOn,
    required this.isActive,
    required this.daysUntilDue,
    this.assetMeterId,
    this.meterCode,
    this.meterName,
    this.meterType,
    this.intervalMeter,
    this.lastCompletedMeter,
    this.nextDueMeter,
    this.currentMeter,
    this.meterDue = false,
  });

  final String id;

  /// Issued by the Site's own sequence from the plan and Asset names — the
  /// client never sends one.
  final String code;
  final String name;

  /// The Asset this schedule is against, flattened onto the row exactly as
  /// `toPmSchedule` (pm-schedules.js) sends it — no nested `asset` map.
  final String assetId;
  final String assetCode;
  final String assetName;

  /// The Org Unit the Asset sits at, joined server-side — never sent by the
  /// client.
  final String orgUnitId;
  final String orgUnitName;

  /// The Job plan whose tasks a raised Work order copies.
  final String jobPlanId;
  final String jobPlanName;

  /// How often the schedule comes round, in days — null for a meter-only
  /// schedule, which comes round on accumulated use instead.
  final int? intervalDays;

  /// The meter a meter-driven schedule comes due on (issue #79), and the
  /// interval in that meter's own unit. All null for a calendar schedule.
  final String? assetMeterId;
  final String? meterCode;
  final String? meterName;

  /// The wire meter type, `cumulative` for a schedule (only cumulative meters
  /// can drive one), kept as a string like [anchor].
  final String? meterType;
  final num? intervalMeter;

  /// The accumulated use when the last occurrence was completed, and the
  /// target the next one comes due at.
  final num? lastCompletedMeter;
  final num? nextDueMeter;

  /// The meter's accumulated use as the server last computed it, and whether
  /// it has reached [nextDueMeter].
  final num? currentMeter;
  final bool meterDue;

  /// Whether this schedule comes round on accumulated use rather than the
  /// calendar — the two mechanisms CONTEXT.md's PM schedule entry names.
  bool get isMeterDriven => assetMeterId != null;

  /// The wire string, not the enum: an anchor this build does not know about
  /// still renders rather than throwing.
  final String anchor;

  /// How many days before the due date a Work order is raised.
  final int leadTimeDays;

  /// 1 (most urgent) to 5 (least urgent), the CHECK constraint's own range.
  final int priority;

  /// `YYYY-MM-DD` of the last completed occurrence, or null when none has
  /// been recorded yet — never parsed into a `DateTime`, the same wire shape
  /// every other calendar date on this client keeps.
  final String? lastCompletedOn;

  /// `YYYY-MM-DD` of the next due occurrence, or null when the server could
  /// not compute one.
  final String? nextDueOn;

  /// False once deactivated. A schedule switched off stops raising Work
  /// orders but stays readable (pm-schedules.js's own header).
  final bool isActive;

  /// `nextDueOn - today`, computed by Postgres — negative once overdue.
  final int? daysUntilDue;

  /// The human label for [anchor] — falls back to the wire string itself for
  /// an anchor this build does not know about, the same fallback
  /// `JobPlan.workTypeLabel` follows.
  String get anchorLabel {
    for (final candidate in PmScheduleAnchor.values) {
      if (candidate.wire == anchor) return candidate.label;
    }
    return anchor;
  }
}
