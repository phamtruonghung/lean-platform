/// A Shift handover as the API answers it (issue #339), and the Section's day
/// it sits in. Each class mirrors one shape from
/// `backend/src/modules/production/handovers.js` — `getHandoverDetail`,
/// `getSectionDay`, `listSectionAssets` and submit's completeness refusal —
/// and reads it as sent: nothing here recomputes a number, a flag or an
/// exception the server already decided.
library;

String? _string(Object? value) => value?.toString();

num? _num(Object? value) => value is num ? value : (value is String ? num.tryParse(value) : null);

/// The numbers the shift closed on, written once at submit and never
/// recomputed (ADR-0054). Every field is null on a draft, and a sealed one
/// may hold a null too — [ShiftHandover.snapshotGaps] says why.
class HandoverSnapshot {
  const HandoverSnapshot(this._json);

  final Map<String, dynamic> _json;

  num? operator [](String field) => _num(_json[field]);

  factory HandoverSnapshot.fromJson(Map<String, dynamic>? json) =>
      HandoverSnapshot(json ?? const <String, dynamic>{});
}

class MachineLine {
  const MachineLine({
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.state,
    this.abnormalityType,
    this.note,
    this.watchNote,
    this.walked = false,
    this.downtimeEventId,
    this.qualityIssueId,
    this.workOrderId,
  });

  final String assetId;
  final String assetCode;
  final String assetName;
  final String state;
  final String? abnormalityType;
  final String? note;
  final String? watchNote;
  final bool walked;

  /// The records that explain a line, linked by id. Kept so a rewrite of the
  /// line sends them back: the PUT replaces the whole line, and a field left
  /// out is cleared.
  final String? downtimeEventId;
  final String? qualityIssueId;
  final String? workOrderId;

  factory MachineLine.fromJson(Map<String, dynamic> json) => MachineLine(
        assetId: json['assetId'].toString(),
        assetCode: json['assetCode'] as String? ?? '',
        assetName: json['assetName'] as String? ?? '',
        state: json['state'] as String,
        abnormalityType: json['abnormalityType'] as String?,
        note: json['note'] as String?,
        watchNote: json['watchNote'] as String?,
        walked: json['walked'] == true,
        downtimeEventId: _string(json['downtimeEventId']),
        qualityIssueId: _string(json['qualityIssueId']),
        workOrderId: _string(json['workOrderId']),
      );
}

class ChangePoint {
  const ChangePoint({
    required this.id,
    required this.dimension,
    required this.description,
    required this.watchNote,
    this.employeeName,
    this.watchResult,
    this.watchResultNote,
  });

  final String id;
  final String dimension;
  final String description;
  final String watchNote;
  final String? employeeName;
  final String? watchResult;
  final String? watchResultNote;

  factory ChangePoint.fromJson(Map<String, dynamic> json) => ChangePoint(
        id: json['id'].toString(),
        dimension: json['dimension'] as String,
        description: json['description'] as String? ?? '',
        watchNote: json['watchNote'] as String? ?? '',
        employeeName: json['employeeName'] as String?,
        watchResult: json['watchResult'] as String?,
        watchResultNote: json['watchResultNote'] as String?,
      );
}

/// One of the Section's Actions as the Action log holds it now.
class HandoverActionSummary {
  const HandoverActionSummary({
    required this.id,
    required this.actionNo,
    required this.title,
    this.status,
    this.ownerName,
    this.dueDate,
  });

  final String id;
  final String actionNo;
  final String title;
  final String? status;
  final String? ownerName;
  final String? dueDate;

  factory HandoverActionSummary.fromJson(Map<String, dynamic> json) => HandoverActionSummary(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: json['status'] as String?,
        ownerName: json['ownerName'] as String?,
        dueDate: json['dueDate'] as String?,
      );
}

/// A Carried action: the handover's word about one Action.
class HandoverActionLink {
  const HandoverActionLink({
    required this.id,
    required this.disposition,
    required this.action,
    this.ownerName,
    this.closureNote,
    this.ageShifts,
  });

  final String id;
  final String disposition;
  final HandoverActionSummary action;
  final String? ownerName;
  final String? closureNote;
  final int? ageShifts;

  factory HandoverActionLink.fromJson(Map<String, dynamic> json) => HandoverActionLink(
        id: json['id'].toString(),
        disposition: json['disposition'] as String,
        action: HandoverActionSummary.fromJson(json['action'] as Map<String, dynamic>),
        ownerName: json['ownerName'] as String?,
        closureNote: json['closureNote'] as String?,
        ageShifts: _num(json['ageShifts'])?.toInt(),
      );
}

class SnapshotGap {
  const SnapshotGap({required this.field, required this.reason});

  final String field;
  final String reason;
}

class ShiftHandover {
  const ShiftHandover({
    required this.id,
    required this.status,
    required this.orgUnitId,
    required this.shiftInstanceId,
    this.handoverNo,
    this.productionDate,
    this.version = 1,
    this.sectionName,
    this.shiftStartsAt,
    this.shiftEndsAt,
    this.late,
    this.authorDisplayName,
    this.submittedAt,
    this.acknowledgedAt,
    this.acknowledgementNote,
    this.jointWalkDone = false,
    this.criticalItems,
    this.deviationReason,
    this.changePointsNone = false,
    this.snapshot = const HandoverSnapshot(<String, dynamic>{}),
    this.snapshotGaps = const [],
    this.machineLines = const [],
    this.changePoints = const {},
    this.actions = const [],
    this.openActions = const [],
  });

  final String id;
  final String status;
  final String orgUnitId;
  final String shiftInstanceId;
  final String? handoverNo;
  final String? productionDate;
  final int version;
  final String? sectionName;
  final String? shiftStartsAt;
  final String? shiftEndsAt;
  final bool? late;
  final String? authorDisplayName;
  final String? submittedAt;
  final String? acknowledgedAt;
  final String? acknowledgementNote;
  final bool jointWalkDone;
  final String? criticalItems;
  final String? deviationReason;
  final bool changePointsNone;
  final HandoverSnapshot snapshot;
  final List<SnapshotGap> snapshotGaps;
  final List<MachineLine> machineLines;

  /// Keyed by dimension, every dimension present in the server's own order.
  final Map<String, List<ChangePoint>> changePoints;
  final List<HandoverActionLink> actions;

  /// On a draft, the Section's open Actions not yet linked: the candidates
  /// the form offers a disposition for. Empty on a sealed handover.
  final List<HandoverActionSummary> openActions;

  bool get isDraft => status == 'draft';

  List<ChangePoint> get allChangePoints => [for (final group in changePoints.values) ...group];

  MachineLine? lineFor(String assetId) {
    for (final line in machineLines) {
      if (line.assetId == assetId) return line;
    }
    return null;
  }

  factory ShiftHandover.fromJson(Map<String, dynamic> json) {
    final section = json['section'] as Map<String, dynamic>?;
    final shift = json['shiftInstance'] as Map<String, dynamic>?;
    final grouped = json['changePoints'];
    return ShiftHandover(
      id: json['id'].toString(),
      status: json['status'] as String,
      orgUnitId: json['orgUnitId'].toString(),
      shiftInstanceId: json['shiftInstanceId'].toString(),
      handoverNo: _string(json['handoverNo']),
      productionDate: json['productionDate'] as String?,
      version: _num(json['version'])?.toInt() ?? 1,
      sectionName: section?['name'] as String?,
      shiftStartsAt: shift?['startsAt'] as String?,
      shiftEndsAt: shift?['endsAt'] as String?,
      late: json['late'] as bool?,
      authorDisplayName: json['authorDisplayName'] as String?,
      submittedAt: json['submittedAt'] as String?,
      acknowledgedAt: json['acknowledgedAt'] as String?,
      acknowledgementNote: json['acknowledgementNote'] as String?,
      jointWalkDone: json['jointWalkDone'] == true,
      criticalItems: json['criticalItems'] as String?,
      deviationReason: json['deviationReason'] as String?,
      changePointsNone: json['changePointsNone'] == true,
      snapshot: HandoverSnapshot.fromJson(json['snapshot'] as Map<String, dynamic>?),
      snapshotGaps: [
        for (final gap in json['snapshotGaps'] as List<dynamic>? ?? const [])
          SnapshotGap(
            field: (gap as Map<String, dynamic>)['field'] as String,
            reason: gap['reason'] as String,
          ),
      ],
      machineLines: [
        for (final line in json['machineLines'] as List<dynamic>? ?? const [])
          MachineLine.fromJson(line as Map<String, dynamic>),
      ],
      changePoints: {
        if (grouped is Map<String, dynamic>)
          for (final entry in grouped.entries)
            entry.key: [
              for (final point in entry.value as List<dynamic>)
                ChangePoint.fromJson(point as Map<String, dynamic>),
            ],
      },
      actions: [
        for (final link in json['actions'] as List<dynamic>? ?? const [])
          HandoverActionLink.fromJson(link as Map<String, dynamic>),
      ],
      openActions: [
        for (final action in json['openActions'] as List<dynamic>? ?? const [])
          HandoverActionSummary.fromJson(action as Map<String, dynamic>),
      ],
    );
  }
}

/// One of the Section's active Assets — a machine the handover owes a line for.
class SectionAsset {
  const SectionAsset({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  factory SectionAsset.fromJson(Map<String, dynamic> json) => SectionAsset(
        id: json['id'].toString(),
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

/// One shift instance of the Section's day, beside its live handover or none.
class SectionShift {
  const SectionShift({
    required this.shiftInstanceId,
    required this.startsAt,
    required this.endsAt,
    this.handover,
    this.late,
    this.acknowledgementLatencyMinutes,
    this.exceptions = const [],
  });

  final String shiftInstanceId;
  final String? startsAt;
  final String? endsAt;
  final ShiftHandover? handover;
  final bool? late;
  final num? acknowledgementLatencyMinutes;
  final List<String> exceptions;

  factory SectionShift.fromJson(Map<String, dynamic> json) => SectionShift(
        shiftInstanceId: json['shiftInstanceId'].toString(),
        startsAt: json['startsAt'] as String?,
        endsAt: json['endsAt'] as String?,
        handover: json['handover'] == null
            ? null
            : ShiftHandover.fromJson(json['handover'] as Map<String, dynamic>),
        late: json['late'] as bool?,
        acknowledgementLatencyMinutes: _num(json['acknowledgementLatencyMinutes']),
        exceptions: [for (final exception in json['exceptions'] as List<dynamic>? ?? const []) '$exception'],
      );
}

class SectionDay {
  const SectionDay({
    required this.sectionId,
    required this.sectionName,
    required this.productionDate,
    required this.shifts,
  });

  final String sectionId;
  final String sectionName;
  final String productionDate;
  final List<SectionShift> shifts;

  SectionShift? shiftFor(String shiftInstanceId) {
    for (final shift in shifts) {
      if (shift.shiftInstanceId == shiftInstanceId) return shift;
    }
    return null;
  }

  factory SectionDay.fromJson(Map<String, dynamic> json) {
    final section = json['section'] as Map<String, dynamic>;
    return SectionDay(
      sectionId: section['id'].toString(),
      sectionName: section['name'] as String? ?? '',
      productionDate: json['productionDate'] as String,
      shifts: [
        for (final shift in json['shifts'] as List<dynamic>)
          SectionShift.fromJson(shift as Map<String, dynamic>),
      ],
    );
  }
}

/// A gap named by the record it is about: an Asset with no line, a line that
/// is short of something, or an open Action left undispositioned.
class HandoverGapRecord {
  const HandoverGapRecord({required this.code, required this.name, this.missing = const []});

  final String code;
  final String name;
  final List<String> missing;
}

/// Submit's completeness refusal (409, `INCOMPLETE_HANDOVER`): everything
/// missing at once, so one round trip names the whole of what is left.
class HandoverRefusal {
  const HandoverRefusal({
    required this.message,
    this.missingAssets = const [],
    this.incompleteLines = const [],
    this.unansweredBlocks = const [],
    this.undispositionedActions = const [],
  });

  final String message;
  final List<HandoverGapRecord> missingAssets;
  final List<HandoverGapRecord> incompleteLines;
  final List<String> unansweredBlocks;
  final List<HandoverGapRecord> undispositionedActions;

  factory HandoverRefusal.fromJson(Map<String, dynamic> json) => HandoverRefusal(
        message: json['message'] as String? ?? 'This handover cannot be submitted yet.',
        missingAssets: [
          for (final asset in json['missingAssets'] as List<dynamic>? ?? const [])
            HandoverGapRecord(
              code: (asset as Map<String, dynamic>)['code'] as String? ?? '',
              name: asset['name'] as String? ?? '',
            ),
        ],
        incompleteLines: [
          for (final line in json['incompleteLines'] as List<dynamic>? ?? const [])
            HandoverGapRecord(
              code: (line as Map<String, dynamic>)['code'] as String? ?? '',
              name: line['name'] as String? ?? '',
              missing: [for (final what in line['missing'] as List<dynamic>? ?? const []) '$what'],
            ),
        ],
        unansweredBlocks: [
          for (final block in json['unansweredBlocks'] as List<dynamic>? ?? const []) '$block',
        ],
        undispositionedActions: [
          for (final action in json['undispositionedActions'] as List<dynamic>? ?? const [])
            HandoverGapRecord(
              code: (action as Map<String, dynamic>)['actionNo'] as String? ?? '',
              name: action['title'] as String? ?? '',
            ),
        ],
      );
}
