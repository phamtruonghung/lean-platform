/// One Safety observation, as `GET /api/safety/observations/:id` and the
/// register send it (issue #230, `safety-observations.js`'s own
/// `toSafetyObservation`).
///
/// CONTEXT.md's **Safety observation**: what was seen before anything went
/// wrong — a safe act, an unsafe act, or an unsafe condition, under one
/// category — recorded at the Org Unit it was seen at. **An observation has
/// no status** (#223 decision 9): it is a fact, and the Action raised from it
/// (issue #231) carries the state. There is no event history and no
/// restricted field the way a Safety incident's injury classification is —
/// every field here is readable by anyone who can see the Site.
///
/// The production day and the shift are on the row for the reason
/// `SafetyIncident`'s own header gives: the Platform files every event
/// against them (ADR-0017), and this model carries the database's own answer
/// rather than deriving one.
library;

import 'package:flutter/material.dart';

import '../actions/actions.dart';
import '../status_tone.dart';

/// A safe act, an unsafe act, or an unsafe condition — the baseline's own
/// `safety_observations_observation_type_check`, repeated here so the form
/// offers the set rather than letting a caller invent one (ADR-0023).
abstract final class ObservationType {
  static const String safeAct = 'safe_act';
  static const String unsafeAct = 'unsafe_act';
  static const String unsafeCondition = 'unsafe_condition';

  static const List<String> values = [safeAct, unsafeAct, unsafeCondition];

  static String label(String type) => switch (type) {
        safeAct => 'Safe act',
        unsafeAct => 'Unsafe act',
        unsafeCondition => 'Unsafe condition',
        _ => type,
      };

  static List<DropdownMenuItem<String?>> dropdownItems({
    String placeholder = 'Choose a type',
  }) =>
      [
        DropdownMenuItem<String?>(value: null, child: Text(placeholder)),
        for (final type in values)
          DropdownMenuItem<String?>(value: type, child: Text(label(type))),
      ];
}

/// The ten categories the baseline's own
/// `safety_observations_category_check` names, in the schema's own order.
abstract final class ObservationCategory {
  static const String ppe = 'ppe';
  static const String machineGuarding = 'machine_guarding';
  static const String housekeeping = 'housekeeping';
  static const String ergonomics = 'ergonomics';
  static const String chemical = 'chemical';
  static const String workingAtHeight = 'working_at_height';
  static const String traffic = 'traffic';
  static const String energyIsolation = 'energy_isolation';
  static const String procedure = 'procedure';
  static const String other = 'other';

  static const List<String> values = [
    ppe,
    machineGuarding,
    housekeeping,
    ergonomics,
    chemical,
    workingAtHeight,
    traffic,
    energyIsolation,
    procedure,
    other,
  ];

  static String label(String category) => switch (category) {
        ppe => 'PPE',
        machineGuarding => 'Machine guarding',
        housekeeping => 'Housekeeping',
        ergonomics => 'Ergonomics',
        chemical => 'Chemical',
        workingAtHeight => 'Working at height',
        traffic => 'Traffic',
        energyIsolation => 'Energy isolation',
        procedure => 'Procedure',
        other => 'Other',
        _ => category,
      };

  static List<DropdownMenuItem<String?>> dropdownItems({
    String placeholder = 'Choose a category',
  }) =>
      [
        DropdownMenuItem<String?>(value: null, child: Text(placeholder)),
        for (final category in values)
          DropdownMenuItem<String?>(value: category, child: Text(label(category))),
      ];
}

/// The worst credible outcome of what was observed, not what actually
/// happened (CONTEXT.md's **Severity potential**) — **in worst-first order**,
/// the order the register sorts by default and the order this dropdown
/// renders in, low to fatal, so [values] doubles as both the picker's order
/// and [worstFirstRank]'s own table.
abstract final class SeverityPotential {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';
  static const String fatal = 'fatal';

  /// Ascending order — low to fatal — the baseline's own CHECK set order and
  /// the order the picker renders in.
  static const List<String> values = [low, medium, high, fatal];

  static String label(String potential) => switch (potential) {
        low => 'Low',
        medium => 'Medium',
        high => 'High',
        fatal => 'Fatal',
        _ => potential,
      };

  static List<DropdownMenuItem<String?>> dropdownItems({
    String placeholder = 'Choose the worst credible outcome',
  }) =>
      [
        DropdownMenuItem<String?>(value: null, child: Text(placeholder)),
        for (final potential in values)
          DropdownMenuItem<String?>(value: potential, child: Text(label(potential))),
      ];

  /// The tone the register and the detail paint a potential with (the binding
  /// design comment on #223): `fatal` -> danger, `high` -> warning, `medium`
  /// -> info, `low` -> neutral. Stop-work is never folded into this tone — it
  /// is its own labelled badge, because it is a fact about what somebody did,
  /// not a state the observation is in.
  static StatusTone tone(String potential) => switch (potential) {
        fatal => StatusTone.danger,
        high => StatusTone.warning,
        medium => StatusTone.info,
        low => StatusTone.neutral,
        _ => StatusTone.neutral,
      };

  /// Worst-first rank — higher is worse — used only to sort a client-held
  /// page (the server's own register is already worst-first; this is for a
  /// widget test asserting the order it rendered in, the same idiom
  /// `SeverityLevel`'s own `SEVERITY_RANK` mirror on the backend keeps).
  static int worstFirstRank(String potential) => values.indexOf(potential);
}

/// The Action raised from a Safety observation (issue #231), as the
/// observation's own detail read names it — the mirror of
/// `SafetyIncidentConcern`, minus the source-column facts that record has and
/// this one does not: an observation carries no document number of its own to
/// contrast with an Action's, and its Action can be any kind, not always a
/// Concern.
///
/// The vocabulary — `actionStatusLabel`/`actionStatusTone`/`actionTypeLabel`
/// — is imported from the Actions Module's own entry point rather than
/// duplicated here, for the same reason `SafetyIncidentConcern`'s own comment
/// gives: an Action's status and kind are the action log's own words, and a
/// second copy of that map in this Module is exactly the drift the seam
/// exists to prevent.
@immutable
class SafetyObservationAction {
  const SafetyObservationAction({
    required this.id,
    required this.actionNo,
    required this.title,
    required this.actionType,
    required this.status,
    required this.priority,
    required this.isOverdue,
    this.ownerName,
    this.dueDate,
    this.raisedAt,
    this.orgUnitId,
    this.orgUnitName,
  });

  factory SafetyObservationAction.fromJson(Map<String, dynamic> json) => SafetyObservationAction(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String,
        title: json['title'] as String,
        actionType: json['actionType'] as String? ?? 'concern',
        status: json['status'] as String? ?? 'open',
        priority: (json['priority'] as int?) ?? 3,
        isOverdue: json['isOverdue'] == true,
        ownerName: json['ownerName'] as String?,
        dueDate: json['dueDate'] as String?,
        raisedAt: json['raisedAt'] == null ? null : DateTime.tryParse(json['raisedAt'] as String),
        orgUnitId: json['orgUnitId']?.toString(),
        orgUnitName: json['orgUnitName'] as String?,
      );

  final String id;

  /// The number a person quotes: `AC-HCM-2026-00001`.
  final String actionNo;

  final String title;
  final String actionType;
  final String status;
  final int priority;

  /// Whether the Action is past its due date, as the server judges it — the
  /// register's own rule, not a client's comparison against its own clock.
  final bool isOverdue;

  final String? ownerName;
  final String? dueDate;
  final DateTime? raisedAt;
  final String? orgUnitId;
  final String? orgUnitName;

  String get statusLabel => actionStatusLabel(status);
  StatusTone get statusTone => actionStatusTone(status);
  String get typeLabel => actionTypeLabel(actionType);
}

@immutable
class SafetyObservation {
  const SafetyObservation({
    required this.id,
    required this.observedAt,
    required this.observationType,
    required this.category,
    required this.severityPotential,
    required this.description,
    required this.actionTaken,
    required this.isStopWork,
    required this.recordedByAccountId,
    required this.recordedByAccountName,
    required this.observerEmployeeId,
    required this.observerEmployeeName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.siteCode,
    required this.siteName,
    required this.shiftInstanceId,
    required this.productionDate,
    required this.shiftCode,
    required this.shiftName,
    this.actions = const [],
  });

  factory SafetyObservation.fromJson(Map<String, dynamic> json) => SafetyObservation(
        id: json['id'].toString(),
        observedAt: json['observedAt'] as String?,
        observationType: json['observationType'] as String? ?? ObservationType.unsafeCondition,
        category: json['category'] as String? ?? ObservationCategory.other,
        severityPotential: json['severityPotential'] as String? ?? SeverityPotential.low,
        description: json['description'] as String?,
        actionTaken: json['actionTaken'] as String?,
        isStopWork: json['isStopWork'] == true,
        recordedByAccountId: json['recordedByAccountId']?.toString(),
        recordedByAccountName: json['recordedByAccountName'] as String?,
        observerEmployeeId: json['observerEmployeeId']?.toString(),
        observerEmployeeName: json['observerEmployeeName'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String? ?? '',
        siteId: json['siteId'].toString(),
        siteCode: json['siteCode'] as String? ?? '',
        siteName: json['siteName'] as String? ?? '',
        shiftInstanceId: json['shiftInstanceId']?.toString(),
        productionDate: json['productionDate'] as String?,
        shiftCode: json['shiftCode'] as String?,
        shiftName: json['shiftName'] as String?,
        actions: [
          for (final row in json['actions'] as List<dynamic>? ?? const [])
            SafetyObservationAction.fromJson(row as Map<String, dynamic>),
        ],
      );

  final String id;
  final String? observedAt;
  final String observationType;
  final String category;
  final String severityPotential;
  final String? description;
  final String? actionTaken;

  /// Somebody exercised stop-work authority (CONTEXT.md's **Stop-work**). Its
  /// own flag, never folded into a category or a potential.
  final bool isStopWork;

  /// The Account that recorded it. Every observation this slice records has
  /// exactly one of this or [observerEmployeeId] — never neither, never both
  /// (issue #230's own "no unattributed record" criterion).
  final String? recordedByAccountId;
  final String? recordedByAccountName;

  /// The Employee who recorded it at the shared floor device — null on every
  /// observation the Account door records.
  final String? observerEmployeeId;
  final String? observerEmployeeName;

  final String orgUnitId;
  final String orgUnitName;
  final String siteId;
  final String siteCode;
  final String siteName;

  /// The shift instance the moment was filed against, and the production day
  /// it belongs to (ADR-0017). Null when the Site's calendar does not cover
  /// the moment.
  final String? shiftInstanceId;
  final String? productionDate;
  final String? shiftCode;
  final String? shiftName;

  /// The Actions raised from this observation, with their own status (issue
  /// #231) — empty on a list row and on a plain find, filled in only by the
  /// detail read. Empty is a real state — nothing has been done about it yet
  /// — not a missing field, the same shape `SafetyIncident.concerns` keeps.
  final List<SafetyObservationAction> actions;

  /// Whether any Action has been raised from this observation (issue #231).
  bool get hasActions => actions.isNotEmpty;

  String get observationTypeLabel => ObservationType.label(observationType);
  String get categoryLabel => ObservationCategory.label(category);
  String get severityPotentialLabel => SeverityPotential.label(severityPotential);
  StatusTone get severityPotentialTone => SeverityPotential.tone(severityPotential);

  /// Who recorded it, in the words a reader wants. An Account wins where one
  /// is present, the only door for a record this app itself writes — a floor
  /// report is the fallback.
  String get recordedByLabel {
    final account = recordedByAccountName;
    if (account != null && account.isNotEmpty) return account;
    final employee = observerEmployeeName;
    if (employee != null && employee.isNotEmpty) return employee;
    return 'Unknown';
  }

  /// The production day in the words a reader wants, falling back to the
  /// observed moment's own reading when the Site's calendar did not cover it
  /// — the same fallback `SafetyIncident.filedAgainst` gives.
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
class SafetyObservationFilters {
  const SafetyObservationFilters({
    this.orgUnitId,
    this.orgUnitName,
    this.observationType,
    this.category,
    this.severityPotential,
    this.isStopWork,
    this.hasAction,
    this.from,
    this.to,
  });

  final String? orgUnitId;

  /// The chosen Org Unit's own name, for the button that says which area is
  /// on screen. Never sent — the id is what the address takes.
  final String? orgUnitName;

  final String? observationType;
  final String? category;
  final String? severityPotential;
  final bool? isStopWork;

  /// Whether an Action has been raised from the observation (issue #231).
  /// `false` is the filter a walk's own worklist is read through: an
  /// observation with none stays findable rather than disappearing into the
  /// list, since it carries no status of its own to say so (#223 decision 9).
  final bool? hasAction;

  /// The first and last production day the register covers, as `YYYY-MM-DD`.
  final String? from;
  final String? to;

  bool get isSet =>
      orgUnitId != null ||
      observationType != null ||
      category != null ||
      severityPotential != null ||
      isStopWork != null ||
      hasAction != null ||
      from != null ||
      to != null;

  SafetyObservationFilters copyWith({
    String? orgUnitId,
    String? orgUnitName,
    String? observationType,
    String? category,
    String? severityPotential,
    bool? isStopWork,
    bool? hasAction,
    String? from,
    String? to,
    bool clearOrgUnit = false,
    bool clearObservationType = false,
    bool clearCategory = false,
    bool clearSeverityPotential = false,
    bool clearIsStopWork = false,
    bool clearHasAction = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return SafetyObservationFilters(
      orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
      orgUnitName: clearOrgUnit ? null : (orgUnitName ?? this.orgUnitName),
      observationType: clearObservationType ? null : (observationType ?? this.observationType),
      category: clearCategory ? null : (category ?? this.category),
      severityPotential:
          clearSeverityPotential ? null : (severityPotential ?? this.severityPotential),
      isStopWork: clearIsStopWork ? null : (isStopWork ?? this.isStopWork),
      hasAction: clearHasAction ? null : (hasAction ?? this.hasAction),
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
    final type = observationType;
    if (type != null) params['observationType'] = type;
    final cat = category;
    if (cat != null) params['category'] = cat;
    final potential = severityPotential;
    if (potential != null) params['severityPotential'] = potential;
    final stopWork = isStopWork;
    if (stopWork != null) params['isStopWork'] = stopWork.toString();
    final action = hasAction;
    if (action != null) params['hasAction'] = action.toString();
    final fromValue = from;
    if (fromValue != null) params['from'] = fromValue;
    final toValue = to;
    if (toValue != null) params['to'] = toValue;
    return params;
  }
}

/// One read of the register: the rows, and whether the server capped them —
/// the same shape `SafetyIncidentRegister` keeps, and for the same reason
/// (ADR-0026): a capped list must not read as a whole Site.
@immutable
class SafetyObservationRegister {
  const SafetyObservationRegister({required this.observations, required this.truncated});

  final List<SafetyObservation> observations;
  final bool truncated;
}
