/// One supplier NCR, as `GET /api/quality/supplier-ncrs/:id` and the register
/// send it (supplier-ncrs.js's own `toSupplierNcr`), plus the filters the
/// register narrows by.
///
/// CONTEXT.md's **Supplier NCR**: an incoming lot the Supplier got wrong, the
/// Non-conformance that controls the material, and the plant's own answer for
/// it. The record's two dates are the two a reader needs: when the lot was
/// found ([detectedAt], the baseline's `detected_at`) and the day the Supplier
/// was given to answer ([responseDueDate], a day in the Site's own calendar —
/// ADR-0017 — with [isOverdue] the fact somebody is waiting).
///
/// [disposition] and [costRecovered] are the commercial half, and the baseline's
/// own comment is why they matter: "A supplier problem logged without a recovery
/// figure is an inconvenience; the same problem with the cost attached is a
/// conversation with the supplier."
library;

import 'package:flutter/foundation.dart';

import '../status_tone.dart';

/// The states a supplier NCR can be in, from the baseline's own CHECK. `open`
/// and `issued` are the two that want an answer back from the Supplier;
/// `responded` is answered and not yet finished with; a closed or rejected NCR
/// is quiet. This slice writes only `open` and `closed` — the intermediate
/// states are the register's filter, not a state machine this slice invents.
abstract final class SupplierNcrStatus {
  static const String open = 'open';
  static const String issued = 'issued';
  static const String responded = 'responded';
  static const String closed = 'closed';
  static const String rejected = 'rejected';

  static const List<String> values = [open, issued, responded, closed, rejected];

  static String label(String status) => switch (status) {
        open => 'Open',
        issued => 'Issued',
        responded => 'Responded',
        closed => 'Closed',
        rejected => 'Rejected',
        _ => status,
      };

  static StatusTone tone(String status) => switch (status) {
        open => StatusTone.warning,
        issued => StatusTone.info,
        responded => StatusTone.success,
        closed => StatusTone.success,
        _ => StatusTone.neutral,
      };
}

/// What the plant decided happens to the received material, from the baseline's
/// own five. The register shows the label; the disposition form chooses from it
/// (ADR-0023).
abstract final class SupplierNcrDisposition {
  static const String returnToSupplier = 'return_to_supplier';
  static const String scrap = 'scrap';
  static const String reworkAtCost = 'rework_at_cost';
  static const String sort = 'sort';
  static const String useAsIs = 'use_as_is';

  static const List<String> values = [returnToSupplier, scrap, reworkAtCost, sort, useAsIs];

  static String label(String disposition) => switch (disposition) {
        returnToSupplier => 'Return to the Supplier',
        scrap => 'Scrap',
        reworkAtCost => 'Rework at the Supplier\'s cost',
        sort => 'Sort',
        useAsIs => 'Use as it is',
        _ => disposition,
      };
}

/// The Non-conformance that controls the received lot, as the NCR's own read
/// carries it. The record's own address is where a reader goes to work on it;
/// this is the link, named so the NCR can say what happened to the material.
@immutable
class SupplierNcrNonconformance {
  const SupplierNcrNonconformance({
    required this.id,
    required this.issueNo,
    required this.status,
    this.detectionPoint,
    this.severity,
  });

  factory SupplierNcrNonconformance.fromJson(Map<String, dynamic> json) =>
      SupplierNcrNonconformance(
        id: json['id'].toString(),
        issueNo: json['issueNo'] as String,
        status: json['status'] as String,
        detectionPoint: json['detectionPoint'] as String?,
        severity: json['severity'] as String?,
      );

  final String id;
  final String issueNo;
  final String status;

  /// Where the problem was found. `incoming` is the one a record made from this
  /// NCR carries; a linked record keeps its own.
  final String? detectionPoint;

  final String? severity;
}

@immutable
class SupplierNcr {
  const SupplierNcr({
    required this.id,
    required this.ncrNo,
    required this.status,
    required this.supplierId,
    required this.supplierCode,
    required this.supplierName,
    this.productId,
    this.productCode,
    this.productName,
    this.defectCodeId,
    this.defectCodeCode,
    this.defectCodeName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    this.incomingLotRef,
    this.purchaseRef,
    required this.quantityAffected,
    required this.uomCode,
    required this.disposition,
    required this.detectedAt,
    this.responseDueDate,
    this.isOverdue = false,
    this.daysOverdue,
    this.costRecovered,
    required this.currency,
    this.description,
    this.closedAt,
    this.nonconformance,
  });

  factory SupplierNcr.fromJson(Map<String, dynamic> json) => SupplierNcr(
        id: json['id'].toString(),
        ncrNo: json['ncrNo'] as String,
        status: json['status'] as String,
        supplierId: json['supplierId'].toString(),
        supplierCode: json['supplierCode'] as String? ?? '',
        supplierName: json['supplierName'] as String? ?? '',
        productId: json['productId']?.toString(),
        productCode: json['productCode'] as String?,
        productName: json['productName'] as String?,
        defectCodeId: json['defectCodeId']?.toString(),
        defectCodeCode: json['defectCodeCode'] as String?,
        defectCodeName: json['defectCodeName'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String? ?? '',
        siteId: json['siteId'].toString(),
        incomingLotRef: json['incomingLotRef'] as String?,
        purchaseRef: json['purchaseRef'] as String?,
        quantityAffected: (json['quantityAffected'] as num?)?.toDouble() ?? 0,
        uomCode: json['uomCode'] as String? ?? '',
        disposition: json['disposition'] as String? ?? SupplierNcrDisposition.returnToSupplier,
        detectedAt: json['detectedAt'] as String? ?? '',
        responseDueDate: json['responseDueDate'] as String?,
        isOverdue: json['isOverdue'] == true,
        daysOverdue: (json['daysOverdue'] as num?)?.toInt(),
        costRecovered: (json['costRecovered'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'USD',
        description: json['description'] as String?,
        closedAt: json['closedAt'] as String?,
        nonconformance: json['nonconformance'] == null
            ? null
            : SupplierNcrNonconformance.fromJson(
                json['nonconformance'] as Map<String, dynamic>,
              ),
      );

  final String id;

  /// The number a person quotes: the baseline's own `SN-<year>-<sequence>`.
  final String ncrNo;

  final String status;

  final String supplierId;
  final String supplierCode;
  final String supplierName;

  /// The Product, when the NCR names one — optional in the baseline and on the
  /// route, because what arrives on a pallet may not be destined for a Product
  /// yet. A Non-conformance recorded from the NCR needs one, either this or one
  /// named in that write's own body.
  final String? productId;
  final String? productCode;
  final String? productName;

  /// The Defect code, when the NCR names one — optional in the same way, and
  /// needed to record a Non-conformance from the NCR.
  final String? defectCodeId;
  final String? defectCodeCode;
  final String? defectCodeName;

  final String orgUnitId;
  final String orgUnitName;
  final String siteId;

  /// The lot reference the inspector quotes off the delivery note.
  final String? incomingLotRef;

  /// The purchase order the lot arrived against.
  final String? purchaseRef;

  final double quantityAffected;
  final String uomCode;

  /// What the plant decided happens to the material. The baseline's own default
  /// stands until a quality engineer records one, which is why this is never
  /// null on a row that was just recorded.
  final String disposition;

  final String detectedAt;

  /// The day the Supplier was given to answer, in the Site's own calendar. Null
  /// when nobody gave them one, which is not the same as being on time.
  final String? responseDueDate;

  /// Past the day it was due and not yet finished with. A closed NCR is never
  /// late, whatever its due day was.
  final bool isOverdue;

  /// How many days late the answer is — or was.
  final int? daysOverdue;

  /// What was clawed back from the Supplier, when anything was. Null is a real
  /// state — a lot returned without a claim — and is not a zero.
  final double? costRecovered;

  final String currency;

  final String? description;

  final String? closedAt;

  final SupplierNcrNonconformance? nonconformance;

  String get statusLabel => SupplierNcrStatus.label(status);

  StatusTone get statusTone => SupplierNcrStatus.tone(status);

  String get dispositionLabel => SupplierNcrDisposition.label(disposition);

  bool get isFinished => status == SupplierNcrStatus.closed || status == SupplierNcrStatus.rejected;

  /// The quantity as a person writes it — 250, not 250.0 — with the unit it is
  /// measured in.
  String get quantityLabel {
    final quantity = quantityAffected;
    final number = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toString();
    return '$number $uomCode'.trim();
  }

  /// What was recovered, as one sentence: the figure in its currency, or that
  /// nothing was — which is a different fact from nobody having decided.
  String get costRecoveredLabel {
    final cost = costRecovered;
    if (cost == null) return 'Nothing recovered';
    final number = cost == cost.roundToDouble() ? cost.toStringAsFixed(0) : cost.toString();
    return '$number $currency';
  }

  /// The deadline as one sentence: the day the Supplier was given, and — while
  /// the NCR is still being worked — that it is late.
  String get dueLabel {
    if (responseDueDate == null) return 'No answer date was given';
    if (isOverdue) {
      final days = daysOverdue;
      return days == null
          ? 'Past the answer date of $responseDueDate'
          : 'Past the answer date of $responseDueDate by $days day${days == 1 ? '' : 's'}';
    }
    return 'Answer due $responseDueDate';
  }
}

/// One read of the supplier NCR register: the rows, and whether the server
/// capped them. The cap is part of the answer rather than something a caller
/// infers from a row count — a truncated list must not read as a whole Site
/// (ADR-0026's rule, applied to a register).
@immutable
class SupplierNcrRegister {
  const SupplierNcrRegister({required this.supplierNcrs, required this.truncated});

  final List<SupplierNcr> supplierNcrs;
  final bool truncated;
}

/// The register's own filters (issue #215): the two the ticket names — Supplier
/// and status — over an already-visible register, plus the Org Unit the
/// Non-conformance register established as an area filter.
@immutable
class SupplierNcrFilters {
  const SupplierNcrFilters({
    this.status,
    this.supplierId,
    this.supplierName,
    this.orgUnitId,
    this.orgUnitName,
  });

  final String? status;

  /// The chosen Supplier, whose NCRs are on screen — the ticket's first filter.
  final String? supplierId;

  /// That Supplier's own name, for the button that says whose NCRs are on
  /// screen. Never sent — the id is what the address takes.
  final String? supplierName;

  /// The chosen Org Unit, whose NCRs *and everything beneath it* are on screen —
  /// the server's ltree walk, not a filter this client applies.
  final String? orgUnitId;

  /// That Org Unit's own name, for the button that says which area is on
  /// screen. Never sent — the id is what the address takes.
  final String? orgUnitName;

  bool get isSet => status != null || supplierId != null || orgUnitId != null;

  /// The query the register's address takes, in one place so a filter cannot be
  /// added to one and forgotten in the other. Built in two steps rather than as
  /// a map literal with `if (x != null)` elements, which `flutter analyze`
  /// reports as `use_null_aware_elements` — and an `info` diagnostic fails this
  /// repo's check just as an error does.
  Map<String, String> get queryParameters {
    final params = <String, String>{};
    final chosenStatus = status;
    if (chosenStatus != null) params['status'] = chosenStatus;
    final supplier = supplierId;
    if (supplier != null) params['supplierId'] = supplier;
    final orgUnit = orgUnitId;
    if (orgUnit != null) params['orgUnitId'] = orgUnit;
    return params;
  }

  SupplierNcrFilters copyWith({
    String? status,
    String? supplierId,
    String? supplierName,
    String? orgUnitId,
    String? orgUnitName,
    bool clearStatus = false,
    bool clearSupplier = false,
    bool clearOrgUnit = false,
  }) =>
      SupplierNcrFilters(
        status: clearStatus ? null : (status ?? this.status),
        supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
        supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
        orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
        orgUnitName: clearOrgUnit ? null : (orgUnitName ?? this.orgUnitName),
      );
}
