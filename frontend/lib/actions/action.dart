/// One Action as `/api/actions` sends it (issue #176) — a Concern, a
/// Containment, a Countermeasure, a Preventive action, an Improvement or a
/// Routine action, and the PDCA cycle it runs.
///
/// CONTEXT.md's own terms are the field names: what a person reads here is a
/// Concern and its measures, never a "task" (that is a step inside a Work
/// order) and never an "issue".
///
/// **The name collides with Flutter's own `Action`** (`package:flutter/
/// widgets/actions.dart`, the intent-mapping widget). The domain word is not
/// negotiable — CONTEXT.md settles it — so the two files that render one hide
/// Flutter's instead: `import 'package:flutter/material.dart' hide Action;`.
/// Nothing in this Module builds a Flutter `Action`, so the hide costs nothing
/// and keeps the vocabulary the glossary's.
library;

import 'package:flutter/foundation.dart';

import '../status_tone.dart';
import 'capa.dart';

/// What an Action is to a problem, mirroring the CHECK constraint on
/// `action_items.action_type` (migration 1799500000000) and the backend's own
/// `ACTION_TYPES`.
///
/// The labels are the glossary's words, and two of them are deliberately not
/// the wire value: `countermeasure` is what a person used to read as
/// "corrective", and `routine` is what used to be called a "task" — both
/// renames ADR-0032 records, so that the word on screen and the word in the
/// database are the same word.
enum ActionType {
  concern('concern', 'Concern'),
  containment('containment', 'Containment'),
  countermeasure('countermeasure', 'Countermeasure'),
  preventive('preventive', 'Preventive action'),
  improvement('improvement', 'Improvement'),
  routine('routine', 'Routine action');

  const ActionType(this.wire, this.label);

  final String wire;
  final String label;
}

/// One of the five SQDCP Pillars an Action can be filed under
/// (`GET /api/actions/pillars`), as the catalogue itself holds it.
@immutable
class Pillar {
  const Pillar({required this.code, required this.name, required this.description});

  final String code;
  final String name;
  final String? description;
}

/// The five priorities, mirroring `action_items_priority_check` — 1 is worst.
/// Chosen, never typed (ADR-0023): the raise form offers all five.
const Map<int, String> actionPriorityLabels = {
  1: 'P1 — worst',
  2: 'P2',
  3: 'P3 — normal',
  4: 'P4',
  5: 'P5 — least',
};

/// The five states an Action can be in, mirroring the CHECK constraint on
/// `action_items.status` and the backend's own `ACTION_STATUSES`.
///
/// One map carrying the label and the tone TOGETHER (issue #168's rule): a
/// status cannot arrive with one and not the other, which two parallel maps
/// could only promise. The tones follow the same scanning question every other
/// state set in this client answers — "what wants me?":
///
/// - `open` and `in_progress` are `info`: both are live and neither is asking
///   the reader for anything.
/// - `blocked` is the one `warning`. It is the only state where work has
///   stopped and a person has to decide something.
/// - `done` is `success`.
/// - `cancelled` is `neutral`, never `danger`: a cancellation is a decision
///   somebody made, not a fault, and red is reserved for faults.
const Map<String, (String, StatusTone)> actionStatuses = {
  'open': ('Open', StatusTone.info),
  'in_progress': ('In progress', StatusTone.info),
  'blocked': ('Blocked', StatusTone.warning),
  'done': ('Done', StatusTone.success),
  'cancelled': ('Cancelled', StatusTone.neutral),
};

/// The four phases of one turn of the cycle (ADR-0033), in the order they are
/// worked — the labels a person reads on the rail.
const List<String> actionPhaseOrder = ['plan', 'do', 'check', 'act'];

const Map<String, String> actionPhaseLabels = {
  'plan': 'Plan',
  'do': 'Do',
  'check': 'Check',
  'act': 'Act',
};

/// What a Check recorded: whether the countermeasure held. `not_effective` is
/// the verdict that sends the Action round another cycle, so it is a word a
/// person reads rather than a boolean.
/// The three kinds of Action that answer a Concern (issue #178), in the order
/// they are read: the containment first, because it is what stops the bleeding.
const List<String> actionMeasureTypeOrder = ['containment', 'countermeasure', 'preventive'];

const Map<String, String> actionCheckOutcomeLabels = {
  'effective': 'It held',
  'not_effective': 'It did not hold',
};

String actionPhaseLabel(String wire) => actionPhaseLabels[wire] ?? wire;

String? actionCheckOutcomeLabel(String? wire) =>
    wire == null ? null : (actionCheckOutcomeLabels[wire] ?? wire);

/// The label for a status this build does not know about is the wire value
/// itself: a server that gains a state renders it rather than throwing.
String actionStatusLabel(String wire) => actionStatuses[wire]?.$1 ?? wire;

StatusTone actionStatusTone(String wire) => actionStatuses[wire]?.$2 ?? StatusTone.neutral;

String actionTypeLabel(String wire) {
  for (final type in ActionType.values) {
    if (type.wire == wire) return type.label;
  }
  return wire;
}

/// One phase of one Action's cycle (issue #177): its own owner, its own due
/// date, its own note, and — on a Check — the verdict.
@immutable
class ActionPhase {
  const ActionPhase({
    required this.cycle,
    required this.phase,
    this.id,
    this.ownerEmployeeId,
    this.ownerName,
    this.dueDate,
    this.completedAt,
    this.outcome,
    this.note,
  });

  /// Which turn of the circle this belongs to. 1 for the first.
  final int cycle;

  /// The wire value: `plan`, `do`, `check` or `act`.
  final String phase;

  final String? id;
  final String? ownerEmployeeId;
  final String? ownerName;
  final String? dueDate;
  final DateTime? completedAt;

  /// `effective` or `not_effective`, on a Check only.
  final String? outcome;
  final String? note;

  String get phaseLabel => actionPhaseLabel(phase);
  String? get outcomeLabel => actionCheckOutcomeLabel(outcome);

  /// Whether this is the phase the Action is waiting on. The server sends one
  /// open phase at most, so this is that row.
  bool get isOpen => completedAt == null;
}

/// The Concern a measure answers, as the detail read names it (issue #178):
/// enough to read what the measure is about and to go there, and deliberately
/// not that Concern's own measures and phases folded into the same payload.
@immutable
class ActionParent {
  const ActionParent({
    required this.id,
    required this.actionNo,
    required this.title,
    required this.actionType,
    required this.status,
  });

  final String id;
  final String actionNo;
  final String title;
  final String actionType;
  final String status;

  String get typeLabel => actionTypeLabel(actionType);
  String get statusLabel => actionStatusLabel(status);
  StatusTone get statusTone => actionStatusTone(status);
}

/// One Org Unit an Action may be handed up to (issue #180) — an ancestor of
/// the Org Unit it sits at, as the server's own tree walk returns it.
@immutable
class EscalationTarget {
  const EscalationTarget({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;
}

/// One Disposition on a Non-conformance a Concern answers (issue #212) — how
/// the product was dealt with, how much of it, who decided it and when, as
/// `actions.js`'s `toLinkedDisposition` sends it.
///
/// Deliberately not Quality's `Disposition`: that is the model of the record's
/// own Screen, in a Module this one does not import (the dependency runs one
/// way — see `actions.dart` and [LinkedNonconformance]'s own argument), and the
/// two rows are the same fact in two sizes. What is missing here is the status
/// vocabulary a *record* needs; what a report prints are the words for a kind
/// and the quantity, which are the fields below.
@immutable
class LinkedDisposition {
  const LinkedDisposition({
    required this.id,
    required this.dispositionType,
    required this.isConcession,
    required this.quantity,
    required this.uomCode,
    this.reworkMinutes,
    this.decidedAt,
    this.reference,
    this.note,
    this.decidedByAccountId,
    this.decidedByAccountName,
    this.decidedByEmployeeId,
    this.decidedByEmployeeName,
  });

  factory LinkedDisposition.fromJson(Map<String, dynamic> json) => LinkedDisposition(
        id: json['id'].toString(),
        dispositionType: json['dispositionType'] as String? ?? '',
        isConcession: json['isConcession'] == true,
        quantity: _number(json['quantity']),
        uomCode: json['uomCode'] as String? ?? '',
        reworkMinutes: json['reworkMinutes'] == null ? null : _number(json['reworkMinutes']),
        decidedAt:
            json['decidedAt'] == null ? null : DateTime.tryParse(json['decidedAt'] as String),
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        decidedByAccountId: json['decidedByAccountId']?.toString(),
        decidedByAccountName: json['decidedByAccountName'] as String?,
        decidedByEmployeeId: json['decidedByEmployeeId']?.toString(),
        decidedByEmployeeName: json['decidedByEmployeeName'] as String?,
      );

  final String id;

  /// The wire value: `scrap`, `rework`, `return_to_supplier` or `use_as_is`.
  final String dispositionType;

  /// Whether this Disposition is the Concession — product accepted as it is,
  /// which only a holder of Quality authority may grant.
  final bool isConcession;

  final double quantity;
  final String uomCode;

  /// How long a rework took, in minutes. Null for anything that is not one.
  final double? reworkMinutes;

  final DateTime? decidedAt;

  /// The deviation or approval number a Concession was granted under.
  final String? reference;

  final String? note;

  final String? decidedByAccountId;
  final String? decidedByAccountName;
  final String? decidedByEmployeeId;
  final String? decidedByEmployeeName;

  /// The day it was decided, as `YYYY-MM-DD` — what a report prints. Null when
  /// the row has no timestamp, which every route in Quality refuses to write.
  String? get decidedOn => decidedAt?.toLocal().toIso8601String().substring(0, 10);

  /// Who decided it: the Employee named at a floor device first, then the
  /// Account, and `Unknown` for a row with neither (which no route writes).
  String get decidedBy {
    final employee = decidedByEmployeeName;
    if (employee != null && employee.isNotEmpty) return employee;
    final account = decidedByAccountName;
    if (account != null && account.isNotEmpty) return account;
    return 'Unknown';
  }

  /// How much of the product this covers, without a trailing `.0`.
  String get quantityLabel =>
      '${quantity == quantity.roundToDouble() ? quantity.toStringAsFixed(0) : quantity} $uomCode';
}

/// One Non-conformance a Concern answers (issue #208), as the Concern's own
/// detail read names it — the shape `actions.js`'s `toLinkedNonconformance`
/// sends.
///
/// It is deliberately not Quality's `Nonconformance` model: that is a whole
/// record with its histories, and this is the four facts a reader of a Concern
/// needs to recognise the occurrence — the number it is quoted by, the Product
/// that was made wrong, the Defect code it failed and how much of it there is —
/// plus [isSource], which says whether this is the Non-conformance the Concern
/// was *raised from* rather than one gathered to it later, and, since issue
/// #212, the [dispositions] an auditor reading an 8D has to see.
///
/// No status label or tone here, unlike every other state in this client: that
/// vocabulary belongs to the Quality Module, whose entry point this Module does
/// not import (the dependency runs one way — see `actions.dart`), and inventing
/// a second copy of it here is exactly the duplication the Module seam exists
/// to prevent. The row names the record and links to its own address, which is
/// where the status is read — and the CAPA report, which cannot link to
/// anything a reader holds on paper, prints the Dispositions' own kind and
/// quantity rather than the record's status.
@immutable
class LinkedNonconformance {
  const LinkedNonconformance({
    required this.id,
    required this.issueNo,
    required this.status,
    required this.severity,
    required this.quantityAffected,
    required this.uomCode,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.defectCodeId,
    required this.defectCodeCode,
    required this.defectCodeName,
    required this.isSource,
    this.detectionPoint,
    this.lotRef,
    this.detectedAt,
    this.orgUnitId,
    this.orgUnitName,
    this.linkedAt,
    this.dispositions = const [],
  });

  factory LinkedNonconformance.fromJson(Map<String, dynamic> json) => LinkedNonconformance(
        id: json['id'].toString(),
        issueNo: json['issueNo'] as String,
        status: json['status'] as String? ?? 'open',
        severity: json['severity'] as String? ?? 'minor',
        quantityAffected: _number(json['quantityAffected']),
        uomCode: json['uomCode'] as String? ?? '',
        productId: json['productId'].toString(),
        productCode: json['productCode'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        defectCodeId: json['defectCodeId'].toString(),
        defectCodeCode: json['defectCodeCode'] as String? ?? '',
        defectCodeName: json['defectCodeName'] as String? ?? '',
        isSource: json['isSource'] == true,
        detectionPoint: json['detectionPoint'] as String?,
        lotRef: json['lotRef'] as String?,
        detectedAt: json['detectedAt'] as String?,
        orgUnitId: json['orgUnitId']?.toString(),
        orgUnitName: json['orgUnitName'] as String?,
        linkedAt: json['linkedAt'] == null ? null : DateTime.tryParse(json['linkedAt'] as String),
        dispositions: [
          for (final disposition in json['dispositions'] as List<dynamic>? ?? const <dynamic>[])
            LinkedDisposition.fromJson(disposition as Map<String, dynamic>),
        ],
      );

  final String id;

  /// The number a person quotes on a tag and in conversation:
  /// `NC-HCM-2026-00001`.
  final String issueNo;

  final String status;
  final String severity;

  /// How much product the occurrence covers, in the Product's own unit.
  final double quantityAffected;
  final String uomCode;

  final String productId;
  final String productCode;
  final String productName;

  final String defectCodeId;
  final String defectCodeCode;
  final String defectCodeName;

  /// Whether this is the Non-conformance the Concern was raised from, rather
  /// than a further occurrence linked to it. The service refuses to unlink
  /// this one, and the Screen says which it is.
  final bool isSource;

  final String? detectionPoint;
  final String? lotRef;
  final String? detectedAt;
  final String? orgUnitId;
  final String? orgUnitName;
  final DateTime? linkedAt;

  /// Every Disposition recorded against this occurrence (issue #212), oldest
  /// first — how the product was dealt with, how much of it and by whom. An
  /// empty list is a real state ("nothing has been decided about this product
  /// yet") rather than a missing field, and the CAPA report says so in words.
  final List<LinkedDisposition> dispositions;

  /// What was made wrong, in one line: the Product's name and code.
  String get productLabel =>
      productName.isEmpty ? productCode : '$productName · $productCode';

  /// Why it failed, in one line: the Defect code's name and code.
  String get defectCodeLabel =>
      defectCodeName.isEmpty ? defectCodeCode : '$defectCodeName · $defectCodeCode';

  /// How much of it there is, without a trailing `.0`.
  String get quantityLabel =>
      '${quantityAffected == quantityAffected.roundToDouble() ? quantityAffected.toStringAsFixed(0) : quantityAffected} $uomCode';
}

/// The Safety incident a Concern was raised from (issue #229), as the
/// backend's own nested `safetyIncident` field on an Action names it: enough
/// to recognise the incident and go to it — its number and its severity —
/// and deliberately nothing else.
///
/// **Never the injury details.** ADR-0037 restricts who was hurt, the Injury
/// type and the Body part to a holder of Safety authority and to the injured
/// person's own Account; this Module's own read never selects those columns
/// in the first place (`actions.js`'s header explains why), so there is no
/// key here that could leak them even by accident. What this carries — the
/// severity level — is one of the fields ADR-0037 names as public: the
/// numbers a plant acts on, not a diagnosis.
///
/// Deliberately not Safety's own `SafetyIncident`: that is a whole record
/// with its event history, and the dependency between the two client Modules
/// runs one way, the same argument [LinkedNonconformance]'s own doc comment
/// makes about Quality. No status or tone lives here for the same reason —
/// an incident's own status vocabulary belongs to the Safety Module, whose
/// entry point this one does not import.
@immutable
class LinkedSafetyIncident {
  const LinkedSafetyIncident({
    required this.id,
    required this.incidentNo,
    required this.severityLevel,
  });

  final String id;

  /// The number a person quotes: `SI-HCM-2026-00001`.
  final String incidentNo;

  /// The wire value from Safety's own severity ladder — not translated to a
  /// label here, because the ladder's words belong to the Safety Module and a
  /// second copy of them in this one is exactly the drift the seam exists to
  /// prevent. A caller that wants the label imports it from there.
  final String severityLevel;
}

@immutable
class Action {
  const Action({
    required this.id,
    required this.actionNo,
    required this.title,
    required this.actionType,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.status,
    required this.priority,
    required this.isOverdue,
    this.description,
    this.pillarCode,
    this.ownerEmployeeId,
    this.ownerName,
    this.raisedByEmployeeId,
    this.raisedByName,
    this.raisedAt,
    this.dueDate,
    this.daysOverdue,
    this.completedAt,
    this.closureNote,
    this.escalatedToOrgUnitId,
    this.escalatedToOrgUnitName,
    this.escalatedAt,
    this.sourceType,
    this.parentId,
    this.measureCount = 0,
    this.countermeasureCount = 0,
    this.openPhase,
    this.parent,
    this.measures = const [],
    this.phases = const [],
    this.nonconformances = const [],
    this.sourceNonconformanceId,
    this.sourceSafetyIncidentId,
    this.safetyIncident,
    this.capa,
  });

  final String id;
  final String actionNo;
  final String title;
  final String? description;

  /// The wire strings, not the enum: an Action the server describes with a
  /// value this build does not know about still renders rather than throwing.
  final String actionType;
  final String? pillarCode;

  final String orgUnitId;
  final String orgUnitName;

  /// The Site the Org Unit above sits in — the server derives it, the client
  /// never sends it.
  final String siteId;

  final String? ownerEmployeeId;
  final String? ownerName;
  final String? raisedByEmployeeId;
  final String? raisedByName;

  /// When it was raised, as the server's own timestamp.
  final DateTime? raisedAt;

  /// The due date as `YYYY-MM-DD`, or null for an Action with none — which is
  /// a real state and not a missing one.
  final String? dueDate;

  /// The register's own judgement about today, computed server-side. A run of
  /// overdue Actions is the list's first concern, so the client renders what
  /// the server decided rather than re-deriving it from a clock it may have
  /// set differently.
  final bool isOverdue;
  final int? daysOverdue;

  /// 1 is worst (`action_items_priority_check`).
  final int priority;
  final String status;

  final DateTime? completedAt;
  final String? closureNote;

  final String? escalatedToOrgUnitId;
  final String? escalatedToOrgUnitName;
  final DateTime? escalatedAt;

  /// The Action this one answers, if it answers one — set only on a measure,
  /// and only ever pointing at a Concern (issue #178).
  final String? parentId;

  /// Which record of another kind raised this, if any
  /// (`action_items.source_type`): `standalone` for everything this Module
  /// raises today, since nothing else writes the log yet.
  final String? sourceType;

  /// The phase this Action is waiting on (issue #177), or null once its cycle
  /// is complete. Carried on every row the register sends, because "what is
  /// next" is the column a daily-management list is read for.
  final ActionPhase? openPhase;

  /// The Concern this Action answers, or null when it answers nothing — a
  /// measure raised on the spot is complete without one.
  final ActionParent? parent;

  /// How many Actions name this one as the Concern they answer, and how many of
  /// those are countermeasures (issue #178). The register carries both so that
  /// a concern with nothing that fixes it is visible without opening it.
  final int measureCount;
  final int countermeasureCount;

  /// The measures answering this Action, on a detail read — empty until issue
  /// #178 fills it. An empty collection, not a missing field: no client read
  /// changes shape when the measures arrive.
  final List<Action> measures;

  /// Every phase of every cycle this Action has been round, oldest first
  /// (issue #177, on a detail read). A Check that did not hold sent it round
  /// again, and the round that failed is kept here.
  final List<ActionPhase> phases;

  /// The highest cycle the Action has reached — what the rail works in.
  int get currentCycle =>
      phases.isEmpty ? 1 : phases.map((phase) => phase.cycle).reduce((a, b) => a > b ? a : b);

  /// Just the current cycle's phases, in the order a person works them.
  List<ActionPhase> get currentCyclePhases =>
      [for (final phase in phases) if (phase.cycle == currentCycle) phase];

  String get typeLabel => actionTypeLabel(actionType);
  String get statusLabel => actionStatusLabel(status);
  StatusTone get statusTone => actionStatusTone(status);
  String get priorityLabel => actionPriorityLabels[priority] ?? 'P$priority';

  /// Whether this Action answers nothing of its own — a measure stands alone
  /// when it was raised without a Concern behind it.
  bool get isMeasure => const {'containment', 'countermeasure', 'preventive'}.contains(actionType);

  /// The Non-conformances this Concern answers (issue #208), on a detail read
  /// — the one it was raised from first. Empty for every Action that answers
  /// no Non-conformance, which is every Action but a Concern raised from one
  /// and one linked to occurrences later.
  final List<LinkedNonconformance> nonconformances;

  /// The Non-conformance this Action was raised from, if any (issue #208) —
  /// provenance rather than the link list, which is [nonconformances].
  final String? sourceNonconformanceId;

  /// The Safety incident this Action was raised from, if any (issue #229) —
  /// provenance the same way [sourceNonconformanceId] is, and mutually
  /// exclusive with it: the baseline's own `action_items_single_source` CHECK
  /// permits at most one source column set at once.
  final String? sourceSafetyIncidentId;

  /// The Safety incident's own number and severity, named rather than
  /// nested-in-full — the evidence a reader needs to recognise it and go
  /// there, never its injury details (see [LinkedSafetyIncident]'s own doc
  /// comment).
  final LinkedSafetyIncident? safetyIncident;

  /// The CAPA somebody has opened on this Action, if anybody has (issue #209).
  /// Set only on a Concern, and only once: a Concern has at most one
  /// investigation, which is the server's own rule and the reason its Screen
  /// offers opening one *or* a link to the one it has.
  final CapaLink? capa;
}

/// A quantity as a number, whether the server sent `12` or `"12.0000"`.
double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// One page of the register: the Actions, and whether there are more than the
/// server was willing to send (ADR-0026's honesty rule, applied to a register
/// rather than to a suggestion list — the Screen says so rather than letting a
/// capped list read as a whole Site).
@immutable
class ActionRegister {
  const ActionRegister({required this.actions, required this.truncated});

  final List<Action> actions;
  final bool truncated;
}
