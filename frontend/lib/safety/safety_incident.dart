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

import 'package:flutter/material.dart';

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

  /// The dropdown's own item list — a leading "choose one" placeholder
  /// followed by [values] in their declared order — shared by every form that
  /// picks an incident type (`SafetyIncidentFormDialog` and
  /// `FloorSafetyIncidentDialog`, issue #227), so the set is built once rather
  /// than duplicated per form.
  static List<DropdownMenuItem<String?>> dropdownItems({
    String placeholder = 'Choose a type',
  }) =>
      [
        DropdownMenuItem<String?>(value: null, child: Text(placeholder)),
        for (final type in values)
          DropdownMenuItem<String?>(value: type, child: Text(label(type))),
      ];
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

  /// The dropdown's own item list — a leading "choose one" placeholder
  /// followed by [values] in **ladder order**, each marked "· recordable"
  /// where [isRecordable] is true (the binding design comment on #223) —
  /// shared by every form that picks a severity level
  /// (`SafetyIncidentFormDialog` and `FloorSafetyIncidentDialog`, issue #227),
  /// so the ladder-ordering and recordable-marking logic is built once rather
  /// than duplicated per form.
  static List<DropdownMenuItem<String?>> dropdownItems({
    String placeholder = 'Choose a rung',
  }) =>
      [
        DropdownMenuItem<String?>(value: null, child: Text(placeholder)),
        for (final level in values)
          DropdownMenuItem<String?>(
            value: level,
            child: Text(
              isRecordable(level) ? '${label(level)} · recordable' : label(level),
            ),
          ),
      ];

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

  /// The one legal next step for the ordinary ladder move (issue #228) —
  /// `open -> investigating -> actions_pending`, mirroring `NEXT_STATUS`
  /// (safety-incidents.js). Null once an incident is at `actions_pending` (only
  /// closing reaches `closed`, its own address) or already `closed`.
  static String? nextStatus(String status) => switch (status) {
        open => investigating,
        investigating => actionsPending,
        _ => null,
      };
}

/// One row of a Safety incident's event history (issue #228) — a severity
/// change, a status move, a days change or a closure, with the previous and
/// new value, who made it and when. Mirrors `toSafetyIncidentEvent`
/// (safety-incidents.js) key for key.
@immutable
class SafetyIncidentEvent {
  const SafetyIncidentEvent({
    required this.id,
    required this.kind,
    required this.previousValue,
    required this.newValue,
    required this.note,
    required this.changedByAccountId,
    required this.changedByAccountName,
    required this.changedByEmployeeId,
    required this.changedByEmployeeName,
    required this.changedAt,
  });

  factory SafetyIncidentEvent.fromJson(Map<String, dynamic> json) => SafetyIncidentEvent(
        id: json['id'].toString(),
        kind: json['kind'] as String,
        previousValue: json['previousValue'] as String,
        newValue: json['newValue'] as String,
        note: json['note'] as String?,
        changedByAccountId: json['changedByAccountId']?.toString(),
        changedByAccountName: json['changedByAccountName'] as String?,
        changedByEmployeeId: json['changedByEmployeeId']?.toString(),
        changedByEmployeeName: json['changedByEmployeeName'] as String?,
        changedAt: json['changedAt'] as String?,
      );

  final String id;

  /// One of `severity`, `status`, `days`, `closure` (migration 1800900000000).
  final String kind;
  final String previousValue;
  final String newValue;
  final String? note;
  final String? changedByAccountId;
  final String? changedByAccountName;
  final String? changedByEmployeeId;
  final String? changedByEmployeeName;
  final String? changedAt;

  /// Who made the change, in the words a reader wants — an Account wins where
  /// one is present, the only door issue #228's own writes have.
  String get changedBy {
    final account = changedByAccountName;
    if (account != null && account.isNotEmpty) return account;
    final employee = changedByEmployeeName;
    if (employee != null && employee.isNotEmpty) return employee;
    return 'Unknown';
  }

  /// What changed, in a sentence — the same "what happened" summary
  /// `Correction.summary` gives a Non-conformance's own history row.
  String get summary => switch (kind) {
        'severity' =>
          'Severity changed from ${SeverityLevel.label(previousValue)} to ${SeverityLevel.label(newValue)}',
        'status' =>
          'Status moved from ${SafetyIncidentStatus.label(previousValue)} to ${SafetyIncidentStatus.label(newValue)}',
        'days' => 'Days recorded: $newValue',
        'closure' => 'Closed',
        _ => '$previousValue -> $newValue',
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
    required this.injuryTypeId,
    required this.injuryTypeCode,
    required this.injuryTypeName,
    required this.bodyPartId,
    required this.bodyPartCode,
    required this.bodyPartName,
    required this.bodyPartRegion,
    required this.injuryDetailsVisible,
    required this.shiftInstanceId,
    required this.productionDate,
    required this.shiftCode,
    required this.shiftName,
    required this.investigationDueAt,
    required this.closedAt,
    this.events = const [],
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
        injuryTypeId: json['injuryTypeId']?.toString(),
        injuryTypeCode: json['injuryTypeCode'] as String?,
        injuryTypeName: json['injuryTypeName'] as String?,
        bodyPartId: json['bodyPartId']?.toString(),
        bodyPartCode: json['bodyPartCode'] as String?,
        bodyPartName: json['bodyPartName'] as String?,
        bodyPartRegion: json['bodyPartRegion'] as String?,
        // **Whether the key is there at all**, not whether it holds a value.
        // ADR-0037's rule is absence: the API deletes the restricted keys for
        // a caller who may not read them, and returns them present and null
        // for an authorised caller looking at an incident nobody has
        // classified yet. `containsKey` is the only test that tells those two
        // apart, which is the difference between "not classified yet" and
        // "not mine to see" — two genuinely different facts this Screen has
        // to be able to say.
        injuryDetailsVisible: json.containsKey('employeeId'),
        shiftInstanceId: json['shiftInstanceId']?.toString(),
        productionDate: json['productionDate'] as String?,
        shiftCode: json['shiftCode'] as String?,
        shiftName: json['shiftName'] as String?,
        investigationDueAt: json['investigationDueAt'] as String?,
        closedAt: json['closedAt'] as String?,
        events: [
          for (final row in json['events'] as List<dynamic>? ?? const [])
            SafetyIncidentEvent.fromJson(row as Map<String, dynamic>),
        ],
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

  /// The injury classification (issue #224) — the identified Employee, the
  /// Injury type and the Body part, plus the catalogue rows' own names so a
  /// Screen renders them without a second read.
  ///
  /// **These are the three facts ADR-0037 restricts**, and every one of them
  /// is null on a record whose keys the API withheld — [injuryDetailsVisible]
  /// is what says which of the two is true. Null with [injuryDetailsVisible]
  /// true means nobody has classified this incident yet; null with it false
  /// means this caller is not allowed to know.
  final String? employeeId;
  final String? employeeName;
  final String? injuryTypeId;

  /// The catalogue row's own code, carried so the classify dialog can show
  /// what the record already holds **without** finding it in the catalogue —
  /// which matters exactly when the entry has since been deactivated and is no
  /// longer in the list of choices.
  final String? injuryTypeCode;
  final String? injuryTypeName;
  final String? bodyPartId;
  final String? bodyPartCode;
  final String? bodyPartName;
  final String? bodyPartRegion;

  /// Whether this caller may read the three restricted fields at all
  /// (ADR-0037): true for a holder of Safety authority reaching the
  /// incident's Org Unit and for the Account whose own Employee is the injured
  /// person, false for everyone else — an administrator without that Grant
  /// included.
  ///
  /// Derived from the answer's own shape rather than from a flag the API
  /// sends, because the API deliberately sends no flag: a hint saying "there
  /// is something here you cannot see" is the thing ADR-0037 refuses. What
  /// arrives is simply a record with those keys missing.
  final bool injuryDetailsVisible;

  /// The shift instance the moment was filed against, and the production day
  /// it belongs to (ADR-0017). Null when the Site's calendar does not cover
  /// the moment.
  final String? shiftInstanceId;
  final String? productionDate;
  final String? shiftCode;
  final String? shiftName;

  /// The investigation's deadline (issue #228). Settable and changeable by
  /// anyone with an edit Grant reaching the Org Unit, while the incident is
  /// not yet closed. Null when nobody has set one.
  final String? investigationDueAt;

  /// When the record was closed (issue #228). Null while it is still open.
  final String? closedAt;

  /// The event history: every severity change, status move, days change and
  /// closure, oldest first — what `getSafetyIncidentDetail` reads back with
  /// the record (issue #228).
  final List<SafetyIncidentEvent> events;

  bool get isClosed => status == SafetyIncidentStatus.closed;

  /// The one legal next step for the ordinary status move, or null when there
  /// is none — either already `actions_pending` (only closing moves it
  /// further) or already `closed`.
  String? get nextStatus => SafetyIncidentStatus.nextStatus(status);

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

  /// Whether an injury section belongs on this record at all (the binding
  /// design comment on #223).
  ///
  /// The no-injury rung carries no classification for **anybody**: the
  /// baseline's own `safety_incidents_near_miss_no_injury` CHECK forbids an
  /// injury type and a body part there, so there is nothing to classify and a
  /// section saying so would be noise on every near miss the plant records.
  /// Every rung above it renders the section — with the values for a reader
  /// who may see them, and with one line saying the details are restricted for
  /// a reader who may not.
  ///
  /// Hiding the section from an unauthorised reader instead would protect
  /// nothing — the severity rung is public, and that CHECK makes "does this
  /// incident have injury details" derivable from it — and would cost the
  /// reader the difference between "not classified yet" and "not mine to see".
  bool get hasInjurySection => severityLevel != SeverityLevel.nearMiss;

  /// Whether anyone has actually classified this incident. Only meaningful
  /// when [injuryDetailsVisible] is true; a caller who may not read the
  /// fields cannot tell, and must not be shown a guess.
  bool get isClassified => employeeId != null || injuryTypeId != null || bodyPartId != null;
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
