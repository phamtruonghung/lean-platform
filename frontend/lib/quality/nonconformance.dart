/// One Non-conformance, as `GET /api/quality/nonconformances/:id` and the
/// register send it (nonconformances.js's own `toNonconformance`).
///
/// CONTEXT.md's **Non-conformance**: product found not to conform, recorded
/// where it was found, by whoever found it. It names the Product, the Defect
/// code, the detection point, a quantity and where in the plant it is, gets a
/// number of its own, and carries the history of the one number that changes
/// as sorting finds more of it.
///
/// The production day and the shift are on the row because the Platform files
/// every event against them (ADR-0017, CONTEXT.md's own "Production day"
/// entry): a 05:30 find at a Site whose first shift starts at 06:00 belongs to
/// the previous production day, and this model carries the database's answer
/// rather than deriving one. They are null for a Site with no shift calendar
/// covering the moment — the schema's documented case, which a Screen must
/// render rather than guess at.
library;

import 'package:flutter/foundation.dart';

import '../actions/actions.dart';
import '../status_tone.dart';
import 'defect_code.dart';

/// The points at which a nonconformity can be detected — the baseline's own
/// `quality_issues_detection_point_check`, repeated here so the form offers
/// the set rather than letting a caller invent one (ADR-0023: a value with a
/// known set is chosen, never typed).
///
/// The distinction is the whole point of the column: the same defect found
/// in-process, at final inspection and by the customer are three very
/// different failures of the control plan.
abstract final class DetectionPoint {
  static const String incoming = 'incoming';
  static const String inProcess = 'in_process';
  static const String finalInspection = 'final_inspection';
  static const String audit = 'audit';
  static const String customer = 'customer';

  static const List<String> values = [incoming, inProcess, finalInspection, audit, customer];

  /// The point in the words a person reads.
  static String label(String point) => switch (point) {
        incoming => 'Incoming',
        inProcess => 'In process',
        finalInspection => 'Final inspection',
        audit => 'Audit',
        customer => 'Customer',
        _ => point,
      };
}

/// The states a Non-conformance can be in — the baseline's own
/// `quality_issues_status_check`. Only the first two are reachable in this
/// slice: a record is `open` when it is written down and `contained` once
/// immediate containment is recorded. The rest arrive with dispositions,
/// closure and cancellation, which are later tickets' work; they are named
/// here so a row carrying one renders with its own word and tone rather than
/// as an unknown string.
abstract final class NonconformanceStatus {
  static const String open = 'open';
  static const String contained = 'contained';
  static const String dispositioned = 'dispositioned';
  static const String closed = 'closed';
  static const String cancelled = 'cancelled';

  static const List<String> values = [open, contained, dispositioned, closed, cancelled];

  static String label(String status) => switch (status) {
        open => 'Open',
        contained => 'Contained',
        dispositioned => 'Dispositioned',
        closed => 'Closed',
        cancelled => 'Cancelled',
        _ => status,
      };

  /// What the state means, in the shared status vocabulary (issue #168): an
  /// open Non-conformance is the one that wants a decision, a contained one is
  /// in hand, and a finished or cancelled one is quiet.
  static StatusTone tone(String status) => switch (status) {
        open => StatusTone.warning,
        contained => StatusTone.info,
        closed => StatusTone.success,
        dispositioned => StatusTone.success,
        _ => StatusTone.neutral,
      };
}

/// One change to the affected quantity: what it was, what it is now, who made
/// the change and why (issue #205).
///
/// The "who" is deliberately either shape: an Account for a change made by
/// someone signed in, an Employee for one made at a floor device. This slice
/// only writes the first, and the model carries both so a later slice's rows
/// render without a client change.
@immutable
class QuantityChange {
  const QuantityChange({
    required this.id,
    required this.previousQuantity,
    required this.newQuantity,
    required this.changedAt,
    required this.note,
    required this.changedByAccountId,
    required this.changedByAccountName,
    required this.changedByEmployeeId,
    required this.changedByEmployeeName,
  });

  factory QuantityChange.fromJson(Map<String, dynamic> json) => QuantityChange(
        id: json['id'].toString(),
        previousQuantity: _quantity(json['previousQuantity']),
        newQuantity: _quantity(json['newQuantity']),
        changedAt: json['changedAt'] as String?,
        note: json['note'] as String?,
        changedByAccountId: json['changedByAccountId']?.toString(),
        changedByAccountName: json['changedByAccountName'] as String?,
        changedByEmployeeId: json['changedByEmployeeId']?.toString(),
        changedByEmployeeName: json['changedByEmployeeName'] as String?,
      );

  final String id;
  final double previousQuantity;
  final double newQuantity;
  final String? changedAt;
  final String? note;
  final String? changedByAccountId;
  final String? changedByAccountName;
  final String? changedByEmployeeId;
  final String? changedByEmployeeName;

  /// Who made the change, in the words a reader wants. An Employee named at a
  /// floor device wins where both are somehow present, since that is the more
  /// specific attribution; an unattributed row (which the table's own CHECK
  /// refuses) reads as unknown rather than as a blank.
  String get changedBy {
    final employee = changedByEmployeeName;
    if (employee != null && employee.isNotEmpty) return employee;
    final account = changedByAccountName;
    if (account != null && account.isNotEmpty) return account;
    return 'Unknown';
  }
}

/// The kinds of Disposition issue #206 records — the baseline's own
/// `quality_dispositions_type_check` value set, narrowed to the three a
/// recorder writes down plus the Concession. `regrade` and `sort` are in the
/// database's set and not in this one: the API refuses them, so offering them
/// would be offering a refusal.
abstract final class DispositionType {
  static const String scrap = 'scrap';
  static const String rework = 'rework';
  static const String returnToSupplier = 'return_to_supplier';
  static const String useAsIs = 'use_as_is';

  /// What a recorder may choose from — the three that need no authority.
  static const List<String> choices = [scrap, rework, returnToSupplier];

  static String label(String type) => switch (type) {
        scrap => 'Scrap',
        rework => 'Rework',
        returnToSupplier => 'Return to supplier',
        useAsIs => 'Use as is',
        _ => type,
      };
}

/// One Disposition: the decision about what happens to some of a
/// Non-conformance's product, and who decided it (issue #206).
///
/// A Concession is a Disposition whose kind is `use_as_is`, so the model says
/// so once ([isConcession]) rather than making every reader compare strings.
@immutable
class Disposition {
  const Disposition({
    required this.id,
    required this.dispositionType,
    required this.isConcession,
    required this.quantity,
    required this.uomCode,
    required this.reworkMinutes,
    required this.decidedAt,
    required this.reference,
    required this.note,
    required this.decidedByAccountId,
    required this.decidedByAccountName,
    required this.decidedByEmployeeId,
    required this.decidedByEmployeeName,
  });

  factory Disposition.fromJson(Map<String, dynamic> json) => Disposition(
        id: json['id'].toString(),
        dispositionType: json['dispositionType'] as String? ?? DispositionType.scrap,
        isConcession: json['isConcession'] == true,
        quantity: _quantity(json['quantity']),
        uomCode: json['uomCode'] as String? ?? '',
        reworkMinutes: _quantity(json['reworkMinutes']),
        decidedAt: json['decidedAt'] as String?,
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        decidedByAccountId: json['decidedByAccountId']?.toString(),
        decidedByAccountName: json['decidedByAccountName'] as String?,
        decidedByEmployeeId: json['decidedByEmployeeId']?.toString(),
        decidedByEmployeeName: json['decidedByEmployeeName'] as String?,
      );

  final String id;
  final String dispositionType;

  /// Whether this Disposition is the Concession — product used as it is, which
  /// only a holder of Quality authority may grant.
  final bool isConcession;

  final double quantity;
  final String uomCode;

  /// How long the rework took. Zero for everything that is not a rework.
  final double reworkMinutes;

  final String? decidedAt;

  /// The deviation or approval number a Concession is granted under. Null for
  /// a Disposition that was not.
  final String? reference;

  final String? note;

  final String? decidedByAccountId;
  final String? decidedByAccountName;
  final String? decidedByEmployeeId;
  final String? decidedByEmployeeName;

  /// The kind in the words a person reads — "Concession" where the product was
  /// accepted as it is, which is the word the record's own reader is looking
  /// for.
  String get label =>
      isConcession ? 'Concession' : DispositionType.label(dispositionType);

  /// Who decided it. An Employee named at a floor device wins where both are
  /// somehow present, and an unattributed row (which every route in this
  /// Module refuses to write) reads as unknown rather than as a blank.
  String get decidedBy {
    final employee = decidedByEmployeeName;
    if (employee != null && employee.isNotEmpty) return employee;
    final account = decidedByAccountName;
    if (account != null && account.isNotEmpty) return account;
    return 'Unknown';
  }
}

/// The corrections a holder of Quality authority can make to a
/// Non-conformance (issue #206) — the baseline's own CHECK set on
/// `quality_issue_corrections.kind`.
abstract final class CorrectionKind {
  static const String severityLowered = 'severity_lowered';
  static const String reopened = 'reopened';
  static const String cancelled = 'cancelled';

  static String label(String kind) => switch (kind) {
        severityLowered => 'Severity lowered',
        reopened => 'Reopened',
        cancelled => 'Cancelled',
        _ => kind,
      };
}

/// One correction: what the record was, what it became, why, and who decided
/// it — the "readable back with who and when" half of issue #206.
@immutable
class Correction {
  const Correction({
    required this.id,
    required this.kind,
    required this.previousSeverity,
    required this.newSeverity,
    required this.previousStatus,
    required this.newStatus,
    required this.note,
    required this.correctedAt,
    required this.correctedByAccountId,
    required this.correctedByAccountName,
  });

  factory Correction.fromJson(Map<String, dynamic> json) => Correction(
        id: json['id'].toString(),
        kind: json['kind'] as String? ?? CorrectionKind.reopened,
        previousSeverity: json['previousSeverity'] as String?,
        newSeverity: json['newSeverity'] as String?,
        previousStatus: json['previousStatus'] as String?,
        newStatus: json['newStatus'] as String?,
        note: json['note'] as String?,
        correctedAt: json['correctedAt'] as String?,
        correctedByAccountId: json['correctedByAccountId']?.toString(),
        correctedByAccountName: json['correctedByAccountName'] as String?,
      );

  final String id;
  final String kind;
  final String? previousSeverity;
  final String? newSeverity;
  final String? previousStatus;
  final String? newStatus;
  final String? note;
  final String? correctedAt;
  final String? correctedByAccountId;
  final String? correctedByAccountName;

  String get label => CorrectionKind.label(kind);

  /// What changed, in the words a reader wants: a severity lowering names both
  /// severities, a reopen and a cancel name both states.
  String get summary => switch (kind) {
        CorrectionKind.severityLowered =>
          'Severity lowered from ${DefectSeverity.label(previousSeverity ?? '')} '
              'to ${DefectSeverity.label(newSeverity ?? '')}',
        CorrectionKind.reopened =>
          'Reopened from ${NonconformanceStatus.label(previousStatus ?? '')}',
        CorrectionKind.cancelled =>
          'Cancelled from ${NonconformanceStatus.label(previousStatus ?? '')}',
        _ => label,
      };

  /// Who decided it, said the way [Disposition.decidedBy] is.
  String get correctedBy {
    final name = correctedByAccountName;
    return name == null || name.isEmpty ? 'Unknown' : name;
  }
}

/// One Concern a Non-conformance is linked to (issue #208), as the record's
/// own detail read names it — the shape `nonconformances.js`'s `toConcern`
/// sends.
///
/// The status and its tone, and the kind's own label, come from the Actions
/// Module through its client entry point (`lib/actions/actions.dart`): a
/// Concern is an Action, its five states are the action log's five words, and
/// the tone each carries is this client's shared status vocabulary. A second
/// copy of that map here would be the drift the Module seam exists to prevent —
/// which is exactly why that entry point exists.
///
/// [isSource] is the fact a reader of a Non-conformance wants first: whether
/// this Concern was raised *from* this record, rather than gathered it later as
/// one of the same problem's other occurrences.
@immutable
class LinkedConcern {
  const LinkedConcern({
    required this.id,
    required this.actionNo,
    required this.title,
    required this.actionType,
    required this.status,
    required this.priority,
    required this.isOverdue,
    required this.isSource,
    this.ownerName,
    this.dueDate,
    this.raisedAt,
    this.orgUnitId,
    this.orgUnitName,
    this.linkedAt,
  });

  factory LinkedConcern.fromJson(Map<String, dynamic> json) => LinkedConcern(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String,
        title: json['title'] as String,
        actionType: json['actionType'] as String? ?? 'concern',
        status: json['status'] as String? ?? 'open',
        priority: (json['priority'] as int?) ?? 3,
        isOverdue: json['isOverdue'] == true,
        isSource: json['isSource'] == true,
        ownerName: json['ownerName'] as String?,
        dueDate: json['dueDate'] as String?,
        raisedAt: json['raisedAt'] == null ? null : DateTime.tryParse(json['raisedAt'] as String),
        orgUnitId: json['orgUnitId']?.toString(),
        orgUnitName: json['orgUnitName'] as String?,
        linkedAt: json['linkedAt'] == null ? null : DateTime.tryParse(json['linkedAt'] as String),
      );

  final String id;

  /// The number a person quotes: `AC-HCM-2026-00001`.
  final String actionNo;

  final String title;
  final String actionType;
  final String status;
  final int priority;

  /// Whether the Concern is past its due date, as the server judges it — the
  /// register's own rule, not a client's comparison against its own clock.
  final bool isOverdue;

  final String? ownerName;
  final String? dueDate;
  final DateTime? raisedAt;
  final String? orgUnitId;
  final String? orgUnitName;
  final DateTime? linkedAt;

  /// Whether this is the Concern raised from this Non-conformance.
  final bool isSource;

  String get statusLabel => actionStatusLabel(status);
  StatusTone get statusTone => actionStatusTone(status);
  String get typeLabel => actionTypeLabel(actionType);

  /// Whether the cause is still being answered — what a reader of the record
  /// wants to know, said as a fact rather than left to the status's word.
  bool get isLive => const {'open', 'in_progress', 'blocked'}.contains(status);
}

@immutable
class Nonconformance {
  const Nonconformance({
    required this.id,
    required this.issueNo,
    required this.status,
    required this.detectionPoint,
    required this.severity,
    required this.quantityAffected,
    required this.quantityDispositioned,
    required this.uomCode,
    required this.lotRef,
    required this.detectedAt,
    required this.recordedByAccountId,
    required this.description,
    required this.immediateContainment,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.siteCode,
    required this.siteName,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.defectCodeId,
    required this.defectCodeCode,
    required this.defectCodeName,
    required this.defectCodeDefaultSeverity,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.shiftInstanceId,
    required this.productionDate,
    required this.shiftCode,
    required this.shiftName,
    required this.closedAt,
    required this.quantityChanges,
    required this.dispositions,
    required this.corrections,
    required this.concerns,
  });

  factory Nonconformance.fromJson(Map<String, dynamic> json) => Nonconformance(
        id: json['id'].toString(),
        issueNo: json['issueNo'] as String,
        status: json['status'] as String? ?? NonconformanceStatus.open,
        detectionPoint: json['detectionPoint'] as String? ?? DetectionPoint.inProcess,
        severity: json['severity'] as String? ?? DefectSeverity.minor,
        quantityAffected: _quantity(json['quantityAffected']),
        quantityDispositioned: _quantity(json['quantityDispositioned']),
        uomCode: json['uomCode'] as String? ?? '',
        lotRef: json['lotRef'] as String?,
        detectedAt: json['detectedAt'] as String?,
        recordedByAccountId: json['recordedByAccountId']?.toString(),
        description: json['description'] as String?,
        immediateContainment: json['immediateContainment'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String? ?? '',
        siteId: json['siteId'].toString(),
        siteCode: json['siteCode'] as String? ?? '',
        siteName: json['siteName'] as String? ?? '',
        productId: json['productId'].toString(),
        productCode: json['productCode'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        defectCodeId: json['defectCodeId'].toString(),
        defectCodeCode: json['defectCodeCode'] as String? ?? '',
        defectCodeName: json['defectCodeName'] as String? ?? '',
        defectCodeDefaultSeverity:
            json['defectCodeDefaultSeverity'] as String? ?? DefectSeverity.minor,
        assetId: json['assetId']?.toString(),
        assetCode: json['assetCode'] as String?,
        assetName: json['assetName'] as String?,
        shiftInstanceId: json['shiftInstanceId']?.toString(),
        productionDate: json['productionDate'] as String?,
        shiftCode: json['shiftCode'] as String?,
        shiftName: json['shiftName'] as String?,
        closedAt: json['closedAt'] as String?,
        quantityChanges: [
          for (final change in (json['quantityChanges'] as List<dynamic>? ?? const []))
            QuantityChange.fromJson(change as Map<String, dynamic>),
        ],
        dispositions: [
          for (final disposition in (json['dispositions'] as List<dynamic>? ?? const []))
            Disposition.fromJson(disposition as Map<String, dynamic>),
        ],
        corrections: [
          for (final correction in (json['corrections'] as List<dynamic>? ?? const []))
            Correction.fromJson(correction as Map<String, dynamic>),
        ],
        concerns: [
          for (final concern in (json['concerns'] as List<dynamic>? ?? const []))
            LinkedConcern.fromJson(concern as Map<String, dynamic>),
        ],
      );

  final String id;

  /// The number a person quotes: `NC-HCM-2026-00001`.
  final String issueNo;

  final String status;
  final String detectionPoint;
  final String severity;

  /// How much product the Non-conformance covers. Grows as sorting finds more
  /// and never shrinks — see [quantityChanges] for every step it took.
  final double quantityAffected;

  /// How much of it has been dispositioned. Maintained by the baseline's own
  /// trigger from the disposition rows; this slice never writes it.
  final double quantityDispositioned;

  final String uomCode;
  final String? lotRef;
  final String? detectedAt;

  /// The Account that recorded it. Every Non-conformance this slice records
  /// has one; a row recorded at a floor device would name an Employee through
  /// `detected_by` instead and leave this null.
  final String? recordedByAccountId;

  final String? description;
  final String? immediateContainment;

  final String orgUnitId;
  final String orgUnitName;
  final String siteId;
  final String siteCode;
  final String siteName;

  final String productId;
  final String productCode;
  final String productName;

  final String defectCodeId;
  final String defectCodeCode;
  final String defectCodeName;

  /// The severity this Non-conformance started at — the Defect code's own
  /// default, kept on the row so a reader can see whether the recorded
  /// severity was raised above it.
  final String defectCodeDefaultSeverity;

  final String? assetId;
  final String? assetCode;
  final String? assetName;

  /// The shift instance the moment was filed against, and the production day
  /// it belongs to (ADR-0017). Null when the Site's calendar does not cover
  /// the moment.
  final String? shiftInstanceId;
  final String? productionDate;
  final String? shiftCode;
  final String? shiftName;

  /// When the record finished with itself: set the moment its whole quantity
  /// had a Disposition, or when a holder of Quality authority cancelled it
  /// (issue #206). Null while either has still to happen.
  final String? closedAt;

  final List<QuantityChange> quantityChanges;

  /// What has been decided about the product, in the order it was decided
  /// (issue #206).
  final List<Disposition> dispositions;

  /// The corrections a holder of Quality authority has made to the record, in
  /// the order they were made (issue #206).
  final List<Correction> corrections;

  /// The Concerns this record is evidence behind (issue #208) — the one raised
  /// from it first, then any further occurrence of the same problem linked to
  /// that Concern. Empty when nothing is being done about the cause, which is
  /// a real state and the one the Screen offers to change.
  final List<LinkedConcern> concerns;

  /// Whether anything is being done about the cause at all — what the Screen's
  /// empty state and its controls turn on.
  bool get hasConcerns => concerns.isNotEmpty;

  String get statusLabel => NonconformanceStatus.label(status);
  StatusTone get statusTone => NonconformanceStatus.tone(status);
  String get detectionPointLabel => DetectionPoint.label(detectionPoint);
  String get severityLabel => DefectSeverity.label(severity);

  /// Whether the record is finished: closed because its whole quantity has
  /// been dealt with, or cancelled because it should never have been written
  /// down.
  bool get isClosed => status == NonconformanceStatus.closed;
  bool get isCancelled => status == NonconformanceStatus.cancelled;

  /// How much of the product no Disposition covers yet — what a Disposition
  /// may still be recorded against, and nothing more (issue #206).
  double get undispositionedQuantity => quantityAffected - quantityDispositioned;

  /// Whether a Disposition could be recorded against it at all: a cancelled
  /// record accepts none, and a closed one has none of its quantity left
  /// undecided.
  bool get acceptsDisposition => !isCancelled && undispositionedQuantity > 0;

  /// Whether a Concession could be granted against it — the same rule as any
  /// other Disposition, since a Concession is one.
  bool get acceptsConcession => acceptsDisposition;

  /// Whether the record could be reopened: only a closed one can (issue #206).
  bool get canBeReopened => isClosed;

  /// Whether it could be cancelled: not one that was already cancelled, and
  /// not one that closed itself — a closed record is reopened first, so that
  /// the closing time its own closure produced is not overwritten.
  bool get canBeCancelled => !isCancelled && !isClosed;

  /// Whether a severity could be lowered on it at all — a cancelled record
  /// accepts no corrections.
  bool get canBeLowered => !isCancelled;

  /// Whether the affected quantity has been raised above what was first
  /// counted — what the detail reads at a glance, and what makes the history
  /// worth showing rather than merely keeping.
  bool get quantityChanged => quantityChanges.isNotEmpty;

  /// The production day in the words a reader wants, falling back to the
  /// detected moment's own reading when the Site's calendar did not cover it —
  /// said as a fact rather than hidden, since a blank would read as "no date".
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
/// the request it sends cannot drift apart.
///
/// A filter is a *read* filter over an already-visible register, never an
/// entitlement: the Site is the only scope question the address asks, and
/// picking an Org Unit narrows the list by area rather than by what the caller
/// is granted.
@immutable
class NonconformanceFilters {
  const NonconformanceFilters({
    this.orgUnitId,
    this.orgUnitName,
    this.status,
    this.defectCodeId,
    this.productId,
    this.severity,
    this.from,
    this.to,
  });

  final String? orgUnitId;

  /// The chosen Org Unit's own name, for the button that says which area is on
  /// screen. Never sent — the id is what the address takes.
  final String? orgUnitName;

  final String? status;
  final String? defectCodeId;
  final String? productId;
  final String? severity;

  /// The first and last production day the register covers, as `YYYY-MM-DD`.
  final String? from;
  final String? to;

  bool get isSet =>
      orgUnitId != null ||
      status != null ||
      defectCodeId != null ||
      productId != null ||
      severity != null ||
      from != null ||
      to != null;

  NonconformanceFilters copyWith({
    String? orgUnitId,
    String? orgUnitName,
    String? status,
    String? defectCodeId,
    String? productId,
    String? severity,
    String? from,
    String? to,
    bool clearOrgUnit = false,
    bool clearStatus = false,
    bool clearDefectCode = false,
    bool clearProduct = false,
    bool clearSeverity = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return NonconformanceFilters(
      orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
      orgUnitName: clearOrgUnit ? null : (orgUnitName ?? this.orgUnitName),
      status: clearStatus ? null : (status ?? this.status),
      defectCodeId: clearDefectCode ? null : (defectCodeId ?? this.defectCodeId),
      productId: clearProduct ? null : (productId ?? this.productId),
      severity: clearSeverity ? null : (severity ?? this.severity),
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
    final defectCode = defectCodeId;
    if (defectCode != null) params['defectCodeId'] = defectCode;
    final product = productId;
    if (product != null) params['productId'] = product;
    final severityValue = severity;
    if (severityValue != null) params['severity'] = severityValue;
    final fromValue = from;
    if (fromValue != null) params['from'] = fromValue;
    final toValue = to;
    if (toValue != null) params['to'] = toValue;
    return params;
  }
}

/// One read of the register: the rows, and whether the server capped them.
///
/// The cap is part of the answer rather than something a caller infers from a
/// row count — a list that was truncated must not read as a whole Site
/// (ADR-0026's rule, applied to a register), and the only honest source for
/// "there is more" is the server that decided it.
@immutable
class NonconformanceRegister {
  const NonconformanceRegister({required this.nonconformances, required this.truncated});

  final List<Nonconformance> nonconformances;
  final bool truncated;
}

double _quantity(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
