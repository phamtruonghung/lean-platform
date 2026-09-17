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
    required this.quantityChanges,
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
        quantityChanges: [
          for (final change in (json['quantityChanges'] as List<dynamic>? ?? const []))
            QuantityChange.fromJson(change as Map<String, dynamic>),
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

  final List<QuantityChange> quantityChanges;

  String get statusLabel => NonconformanceStatus.label(status);
  StatusTone get statusTone => NonconformanceStatus.tone(status);
  String get detectionPointLabel => DetectionPoint.label(detectionPoint);
  String get severityLabel => DefectSeverity.label(severity);

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
