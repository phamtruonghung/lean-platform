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
