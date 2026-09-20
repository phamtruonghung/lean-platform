/// One Safety incident, as `GET /api/safety/incidents/:id` and the register
/// send it (issue #226, `safety-incidents.js`'s own `toSafetyIncident`).
///
/// CONTEXT.md's **Safety incident**: something that went wrong, recorded
/// where it happened — the kind of event, its place on the Severity level
/// ladder, who was hurt if anyone, and what was done about it right away.
/// Every Safety incident names its reporter; there is no anonymous path
/// (ADR-0036, #223 decision 1).
///
/// The production day and the shift are on the row for the reason
/// `Nonconformance`'s own header gives: the Platform files every event
/// against them (ADR-0017), and this model carries the database's own answer
/// rather than deriving one.
library;

import 'package:flutter/foundation.dart';

import '../status_tone.dart';

/// What kind of event a Safety incident was — the baseline's own
/// `safety_incidents_incident_type_check`, repeated here so the form offers
/// the set rather than letting a caller invent one (ADR-0023).
///
/// Answers a different question from [SeverityLevel]: this says what
/// happened, the ladder says what it cost a person — #223 decision 3
/// deliberately keeps the two independent, so a fire that hurt nobody is type
/// [fire] sitting on the ladder's no-injury rung, exactly where a genuine near
/// miss also sits.
abstract final class IncidentType {
  static const String injury = 'injury';
  static const String nearMiss = 'near_miss';
  static const String propertyDamage = 'property_damage';
  static const String environmental = 'environmental';
  static const String fire = 'fire';
  static const String ergonomic = 'ergonomic';
  static const String security = 'security';

  static const List<String> values = [
    injury,
    nearMiss,
    propertyDamage,
    environmental,
    fire,
    ergonomic,
    security,
  ];

  static String label(String type) => switch (type) {
        injury => 'Injury',
        nearMiss => 'Near miss',
        propertyDamage => 'Property damage',
        environmental => 'Environmental',
        fire => 'Fire',
        ergonomic => 'Ergonomic',
        security => 'Security',
        _ => type,
      };
}

/// The severity ladder, **in ladder order** — no injury through fatality,
/// never alphabetical (the binding design comment on #223). Its bottom rung
/// is spelled `near_miss` in the schema and cannot be respelled, but it means
/// **no injury** — which is also where a damage-only fire honestly sits.
///
/// [isRecordable] mirrors the baseline's own GENERATED expression exactly
/// (`medical_treatment`, `restricted_work`, `lost_time`, `fatality`), for the
/// dropdown's own "recordable line" marker; the record's own `isRecordable`
/// field, always the database's derived answer, is what a Screen actually
/// renders once an incident exists.
abstract final class SeverityLevel {
  static const String nearMiss = 'near_miss';
  static const String firstAid = 'first_aid';
  static const String medicalTreatment = 'medical_treatment';
  static const String restrictedWork = 'restricted_work';
  static const String lostTime = 'lost_time';
  static const String fatality = 'fatality';

  /// Ladder order — the order the severity dropdown renders in, and the order
  /// the recordable line is drawn against.
  static const List<String> values = [
    nearMiss,
    firstAid,
    medicalTreatment,
    restrictedWork,
    lostTime,
    fatality,
  ];

  static const List<String> recordableLevels = [
    medicalTreatment,
    restrictedWork,
    lostTime,
    fatality,
  ];

  static bool isRecordable(String level) => recordableLevels.contains(level);

  static String label(String level) => switch (level) {
        nearMiss => 'No injury',
        firstAid => 'First aid',
        medicalTreatment => 'Medical treatment',
        restrictedWork => 'Restricted work',
        lostTime => 'Lost time',
        fatality => 'Fatality',
        _ => level,
      };

  /// The tone painted by recordability, not as a gradient (the binding design
  /// comment on #223): three tones, and the one place the colour changes is
  /// exactly where `is_recordable` flips.
  ///
  /// [nearMiss] is deliberately [StatusTone.info], **not** `neutral` — a
  /// near-miss report is the single most valuable record this Module holds,
  /// and painting it quietest would say the opposite. [firstAid] is
  /// [StatusTone.warning]: someone was hurt, below the recordable line. Every
  /// rung at or above the recordable line is [StatusTone.danger] — "reserved
  /// for faults rather than for outcomes" (`status_tone.dart`'s own doc
  /// comment), and a recordable injury is precisely a fault nobody chose. A
  /// fatality is not given a tone of its own; the gravity of that rung lives
  /// in the word on the chip, not in a sixth colour nobody would recognise.
  static StatusTone tone(String level) {
    if (level == nearMiss) return StatusTone.info;
    if (level == firstAid) return StatusTone.warning;
    return StatusTone.danger;
  }
}

/// The states a Safety incident can be in. Only `open` is reachable from this
/// slice (issue #226) — investigating, actions pending and closed arrive with
/// issue #228's own writes; they are named here so a row carrying one renders
/// with its own word and tone rather than as an unknown string.
abstract final class SafetyIncidentStatus {
  static const String open = 'open';
  static const String investigating = 'investigating';
  static const String actionsPending = 'actions_pending';
  static const String closed = 'closed';

  static const List<String> values = [open, investigating, actionsPending, closed];

  static String label(String status) => switch (status) {
        open => 'Open',
        investigating => 'Investigating',
        actionsPending => 'Actions pending',
        closed => 'Closed',
        _ => status,
      };

  /// Mirrors the Non-conformance register's own status mapping exactly (the
  /// binding design comment on #223): `open` is the one state wanting a
  /// decision, `investigating` and `actions_pending` are live and in hand,
  /// `closed` is finished.
  static StatusTone tone(String status) => switch (status) {
        open => StatusTone.warning,
        investigating => StatusTone.info,
        actionsPending => StatusTone.info,
        closed => StatusTone.success,
        _ => StatusTone.neutral,
      };
}

@immutable
class SafetyIncident {
  const SafetyIncident({
    required this.id,
    required this.incidentNo,
    required this.status,
    required this.incidentType,
    required this.severityLevel,
    required this.isRecordable,
    required this.occurredAt,
    required this.reportedAt,
    required this.description,
    required this.immediateAction,
    required this.lostTimeDays,
    required this.restrictedDays,
    required this.recordedByAccountId,
    required this.recordedByAccountName,
    required this.reportedBy,
    required this.reportedByName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.siteCode,
    required this.siteName,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.employeeId,
    required this.employeeName,
    required this.shiftInstanceId,
    required this.productionDate,
    required this.shiftCode,
    required this.shiftName,
    required this.closedAt,
  });

  factory SafetyIncident.fromJson(Map<String, dynamic> json) => SafetyIncident(
        id: json['id'].toString(),
        incidentNo: json['incidentNo'] as String,
        status: json['status'] as String? ?? SafetyIncidentStatus.open,
        incidentType: json['incidentType'] as String? ?? IncidentType.nearMiss,
        severityLevel: json['severityLevel'] as String? ?? SeverityLevel.nearMiss,
        isRecordable: json['isRecordable'] == true,
        occurredAt: json['occurredAt'] as String?,
        reportedAt: json['reportedAt'] as String?,
        description: json['description'] as String?,
        immediateAction: json['immediateAction'] as String?,
        lostTimeDays: (json['lostTimeDays'] as num?)?.toInt() ?? 0,
        restrictedDays: (json['restrictedDays'] as num?)?.toInt() ?? 0,
        recordedByAccountId: json['recordedByAccountId']?.toString(),
        recordedByAccountName: json['recordedByAccountName'] as String?,
        reportedBy: json['reportedBy']?.toString(),
        reportedByName: json['reportedByName'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String? ?? '',
        siteId: json['siteId'].toString(),
        siteCode: json['siteCode'] as String? ?? '',
        siteName: json['siteName'] as String? ?? '',
        assetId: json['assetId']?.toString(),
        assetCode: json['assetCode'] as String?,
        assetName: json['assetName'] as String?,
        employeeId: json['employeeId']?.toString(),
        employeeName: json['employeeName'] as String?,
        shiftInstanceId: json['shiftInstanceId']?.toString(),
        productionDate: json['productionDate'] as String?,
        shiftCode: json['shiftCode'] as String?,
        shiftName: json['shiftName'] as String?,
        closedAt: json['closedAt'] as String?,
      );

  final String id;

  /// The number a person quotes: `SI-HCM-2026-00001`.
  final String incidentNo;

  final String status;
  final String incidentType;
  final String severityLevel;

  /// Derived by the database from the severity level, never accepted from a
  /// caller (issue #226's own criterion) — always the GENERATED column's own
  /// answer.
  final bool isRecordable;

  final String? occurredAt;
  final String? reportedAt;
  final String? description;
  final String? immediateAction;
  final int lostTimeDays;
  final int restrictedDays;

  /// The Account that recorded it. Every incident this slice records has
  /// one — there is no anonymous path (ADR-0036).
  final String? recordedByAccountId;
  final String? recordedByAccountName;

  /// The Employee who reported it at the shared floor device (issue #227,
  /// ADR-0016) — null on every incident this slice's Account door records.
  final String? reportedBy;
  final String? reportedByName;

  final String orgUnitId;
  final String orgUnitName;
  final String siteId;
  final String siteCode;
  final String siteName;

  final String? assetId;
  final String? assetCode;
  final String? assetName;

  /// The Employee involved — who was hurt, if anyone. Optional: a near miss
  /// or a damage-only event names nobody.
  final String? employeeId;
  final String? employeeName;

  /// The shift instance the moment was filed against, and the production day
  /// it belongs to (ADR-0017). Null when the Site's calendar does not cover
  /// the moment.
  final String? shiftInstanceId;
  final String? productionDate;
  final String? shiftCode;
  final String? shiftName;

  /// When the record was closed (issue #228). Null while it is still open.
  final String? closedAt;

  String get statusLabel => SafetyIncidentStatus.label(status);
  StatusTone get statusTone => SafetyIncidentStatus.tone(status);
  String get incidentTypeLabel => IncidentType.label(incidentType);
  String get severityLabel => SeverityLevel.label(severityLevel);
  StatusTone get severityTone => SeverityLevel.tone(severityLevel);

  /// Who reported it, in the words a reader wants. An Account wins where one
  /// is present — the only door this slice has — and an Employee identified
  /// at the floor device (issue #227) is the fallback once that door exists.
  String get reportedByLabel {
    final account = recordedByAccountName;
    if (account != null && account.isNotEmpty) return account;
    final employee = reportedByName;
    if (employee != null && employee.isNotEmpty) return employee;
    return 'Unknown';
  }

  /// The production day in the words a reader wants, falling back to the
  /// occurred moment's own reading when the Site's calendar did not cover it
  /// — the same fallback `Nonconformance.filedAgainst` gives.
  String get filedAgainst {
    final day = productionDate;
    if (day != null && day.isNotEmpty) {
      final shift = shiftName;
      return shift == null || shift.isEmpty ? day : '$day · $shift';
    }
    return 'Not within a shift of this Site';
  }
}

/// Every filter the register offers, as one value — so a Screen's state and
/// the request it sends cannot drift apart. A filter is a *read* filter over
/// an already-visible register, never an entitlement: the Site is the only
/// scope question the address asks, and picking an Org Unit narrows the list
/// by area rather than by what the caller is granted.
@immutable
class SafetyIncidentFilters {
  const SafetyIncidentFilters({
    this.orgUnitId,
    this.orgUnitName,
    this.status,
    this.incidentType,
    this.severityLevel,
    this.isRecordable,
    this.from,
    this.to,
  });

  final String? orgUnitId;

  /// The chosen Org Unit's own name, for the button that says which area is
  /// on screen. Never sent — the id is what the address takes.
  final String? orgUnitName;

  final String? status;
  final String? incidentType;
  final String? severityLevel;
  final bool? isRecordable;

  /// The first and last production day the register covers, as `YYYY-MM-DD`.
  final String? from;
  final String? to;

  bool get isSet =>
      orgUnitId != null ||
      status != null ||
      incidentType != null ||
      severityLevel != null ||
      isRecordable != null ||
      from != null ||
      to != null;

  SafetyIncidentFilters copyWith({
    String? orgUnitId,
    String? orgUnitName,
    String? status,
    String? incidentType,
    String? severityLevel,
    bool? isRecordable,
    String? from,
    String? to,
    bool clearOrgUnit = false,
    bool clearStatus = false,
    bool clearIncidentType = false,
    bool clearSeverityLevel = false,
    bool clearIsRecordable = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return SafetyIncidentFilters(
      orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
      orgUnitName: clearOrgUnit ? null : (orgUnitName ?? this.orgUnitName),
      status: clearStatus ? null : (status ?? this.status),
      incidentType: clearIncidentType ? null : (incidentType ?? this.incidentType),
      severityLevel: clearSeverityLevel ? null : (severityLevel ?? this.severityLevel),
      isRecordable: clearIsRecordable ? null : (isRecordable ?? this.isRecordable),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
    );
  }

  /// The query parameters this filter set becomes — only the keys that are
  /// set, so an unset filter never reaches the server as a blank.
  Map<String, String> get queryParameters {
    final params = <String, String>{};
    final orgUnit = orgUnitId;
    if (orgUnit != null) params['orgUnitId'] = orgUnit;
    final state = status;
    if (state != null) params['status'] = state;
    final type = incidentType;
    if (type != null) params['incidentType'] = type;
    final severity = severityLevel;
    if (severity != null) params['severityLevel'] = severity;
    final recordable = isRecordable;
    if (recordable != null) params['isRecordable'] = recordable.toString();
    final fromValue = from;
    if (fromValue != null) params['from'] = fromValue;
    final toValue = to;
    if (toValue != null) params['to'] = toValue;
    return params;
  }
}

/// One read of the register: the rows, and whether the server capped them —
/// the same shape `NonconformanceRegister` keeps, and for the same reason
/// (ADR-0026): a capped list must not read as a whole Site.
@immutable
class SafetyIncidentRegister {
  const SafetyIncidentRegister({required this.incidents, required this.truncated});

  final List<SafetyIncident> incidents;
  final bool truncated;
}
