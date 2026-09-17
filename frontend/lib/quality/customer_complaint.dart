/// One Customer complaint, as `GET /api/quality/complaints/:id` and the
/// register send it (customer-complaints.js's own `toComplaint`), plus the
/// filters the register narrows by.
///
/// CONTEXT.md has no **Customer complaint** entry of its own — the record is
/// the baseline's and the ticket's words are the ones used here: a Customer
/// complained about a Product, the plant wrote down what they said, and the
/// complained-of product is controlled by a Non-conformance. The two dates the
/// record carries are the two a reader needs: when it arrived, and the day the
/// customer was promised an answer ([responseDueDate], a day in the Site's own
/// calendar — ADR-0017 — with [isOverdue] the fact somebody is waiting).
///
/// The response the complaint was closed with ([responseNote]) is what says
/// what was actually said back; `firstResponseAt` is when the first reply went
/// out, which the baseline keeps apart from `closedAt` because customers judge
/// both.
library;

import 'package:flutter/foundation.dart';

import '../status_tone.dart';

/// The states a complaint can be in, and what each means in the shared status
/// vocabulary (issue #168). `open` and `investigating` are the two that want
/// something; `responded` is answered and not yet finished with; a closed or
/// rejected complaint is quiet.
abstract final class ComplaintStatus {
  static const String open = 'open';
  static const String investigating = 'investigating';
  static const String responded = 'responded';
  static const String closed = 'closed';
  static const String rejected = 'rejected';

  static const List<String> values = [open, investigating, responded, closed, rejected];

  static String label(String status) => switch (status) {
        open => 'Open',
        investigating => 'Investigating',
        responded => 'Responded',
        closed => 'Closed',
        rejected => 'Rejected',
        _ => status,
      };

  static StatusTone tone(String status) => switch (status) {
        open => StatusTone.warning,
        investigating => StatusTone.info,
        responded => StatusTone.success,
        closed => StatusTone.success,
        _ => StatusTone.neutral,
      };
}

/// What the customer was complaining about, from the baseline's own set. The
/// register shows the label; the record form chooses from it (ADR-0023).
abstract final class ComplaintType {
  static const String quality = 'quality';
  static const String delivery = 'delivery';
  static const String quantity = 'quantity';
  static const String documentation = 'documentation';
  static const String packaging = 'packaging';
  static const String service = 'service';

  static const List<String> values = [quality, delivery, quantity, documentation, packaging, service];

  static String label(String type) => switch (type) {
        quality => 'Quality',
        delivery => 'Delivery',
        quantity => 'Quantity',
        documentation => 'Documentation',
        packaging => 'Packaging',
        service => 'Service',
        _ => type,
      };
}

/// The Non-conformance that controls the complained-of product, as the
/// complaint's own read carries it. The record's own address is where a reader
/// goes to work on it; this is the link, named so the complaint can say what
/// happened to it.
@immutable
class ComplaintNonconformance {
  const ComplaintNonconformance({
    required this.id,
    required this.issueNo,
    required this.status,
    this.detectionPoint,
    this.severity,
  });

  factory ComplaintNonconformance.fromJson(Map<String, dynamic> json) =>
      ComplaintNonconformance(
        id: json['id'].toString(),
        issueNo: json['issueNo'] as String,
        status: json['status'] as String,
        detectionPoint: json['detectionPoint'] as String?,
        severity: json['severity'] as String?,
      );

  final String id;
  final String issueNo;
  final String status;

  /// Where the problem was found. `customer` is the one a record made from this
  /// complaint carries; a linked record keeps its own.
  final String? detectionPoint;

  final String? severity;
}

@immutable
class CustomerComplaint {
  const CustomerComplaint({
    required this.id,
    required this.complaintNo,
    required this.status,
    required this.customerId,
    required this.customerCode,
    required this.customerName,
    required this.productId,
    required this.productCode,
    required this.productName,
    this.defectCodeId,
    this.defectCodeCode,
    this.defectCodeName,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
    required this.complaintType,
    required this.severity,
    this.quantityAffected,
    this.uomCode,
    this.customerRef,
    this.lotRef,
    required this.description,
    required this.receivedAt,
    this.responseDueDate,
    this.isOverdue = false,
    this.daysOverdue,
    this.firstResponseAt,
    this.isWarranty = false,
    this.closedAt,
    this.responseNote,
    this.nonconformance,
  });

  factory CustomerComplaint.fromJson(Map<String, dynamic> json) => CustomerComplaint(
        id: json['id'].toString(),
        complaintNo: json['complaintNo'] as String,
        status: json['status'] as String,
        customerId: json['customerId'].toString(),
        customerCode: json['customerCode'] as String? ?? '',
        customerName: json['customerName'] as String? ?? '',
        productId: json['productId'].toString(),
        productCode: json['productCode'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        defectCodeId: json['defectCodeId']?.toString(),
        defectCodeCode: json['defectCodeCode'] as String?,
        defectCodeName: json['defectCodeName'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String? ?? '',
        siteId: json['siteId'].toString(),
        complaintType: json['complaintType'] as String? ?? ComplaintType.quality,
        severity: json['severity'] as String? ?? 'major',
        quantityAffected: (json['quantityAffected'] as num?)?.toDouble(),
        uomCode: json['uomCode'] as String?,
        customerRef: json['customerRef'] as String?,
        lotRef: json['lotRef'] as String?,
        description: json['description'] as String? ?? '',
        receivedAt: json['receivedAt'] as String? ?? '',
        responseDueDate: json['responseDueDate'] as String?,
        isOverdue: json['isOverdue'] == true,
        daysOverdue: (json['daysOverdue'] as num?)?.toInt(),
        firstResponseAt: json['firstResponseAt'] as String?,
        isWarranty: json['isWarranty'] == true,
        closedAt: json['closedAt'] as String?,
        responseNote: json['responseNote'] as String?,
        nonconformance: json['nonconformance'] == null
            ? null
            : ComplaintNonconformance.fromJson(
                json['nonconformance'] as Map<String, dynamic>,
              ),
      );

  final String id;

  /// The number a person quotes: the baseline's own `CC-<year>-<sequence>`.
  final String complaintNo;

  final String status;

  final String customerId;
  final String customerCode;
  final String customerName;

  final String productId;
  final String productCode;
  final String productName;

  /// The Defect code, when the complaint names one — optional in the baseline
  /// and on the route, and needed to record a Non-conformance from the
  /// complaint (or named in that write's own body when it is absent here).
  final String? defectCodeId;
  final String? defectCodeCode;
  final String? defectCodeName;

  final String orgUnitId;
  final String orgUnitName;
  final String siteId;

  final String complaintType;
  final String severity;

  final double? quantityAffected;
  final String? uomCode;
  final String? customerRef;
  final String? lotRef;

  /// What the customer said, in their own words — the baseline's NOT NULL
  /// column, and the reason a complaint with nothing written down is refused.
  final String description;

  final String receivedAt;

  /// The day the customer was promised an answer, in the Site's own calendar.
  /// Null when nobody promised one, which is not the same as being on time.
  final String? responseDueDate;

  /// Past the day it was due and not yet finished with. A closed complaint is
  /// never late, whatever its due day was.
  final bool isOverdue;

  /// How many days late the reply is — or was.
  final int? daysOverdue;

  final String? firstResponseAt;
  final bool isWarranty;
  final String? closedAt;

  /// What was said back, written when the complaint was closed. Required to
  /// close one at all (customer-complaints.js), which is the whole point of
  /// keeping it.
  final String? responseNote;

  final ComplaintNonconformance? nonconformance;

  String get statusLabel => ComplaintStatus.label(status);

  StatusTone get statusTone => ComplaintStatus.tone(status);

  String get typeLabel => ComplaintType.label(complaintType);

  bool get isFinished => status == ComplaintStatus.closed || status == ComplaintStatus.rejected;

  /// The quantity as a person writes it — 20, not 20.0 — with the unit it is
  /// measured in, or a plain sentence when the customer gave no figure.
  String get quantityLabel {
    final quantity = quantityAffected;
    if (quantity == null) return 'No quantity given';
    final number = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toString();
    return '$number ${uomCode ?? ''}'.trim();
  }

  /// The deadline as one sentence: the day it was promised, and — while the
  /// complaint is still being worked — that it is late.
  String get dueLabel {
    if (responseDueDate == null) return 'No response date was promised';
    if (isOverdue) {
      final days = daysOverdue;
      return days == null
          ? 'Past the response date of $responseDueDate'
          : 'Past the response date of $responseDueDate by $days day${days == 1 ? '' : 's'}';
    }
    return 'Response due $responseDueDate';
  }
}

/// One read of the complaint register: the rows, and whether the server capped
/// them. The cap is part of the answer rather than something a caller infers
/// from a row count — a truncated list must not read as a whole Site
/// (ADR-0026's rule, applied to a register).
@immutable
class ComplaintRegister {
  const ComplaintRegister({required this.complaints, required this.truncated});

  final List<CustomerComplaint> complaints;
  final bool truncated;
}

/// The register's own filters (issue #214): the two the ticket names — status
/// and Org Unit — over an already-visible register.
@immutable
class ComplaintFilters {
  const ComplaintFilters({this.status, this.orgUnitId, this.orgUnitName});

  final String? status;

  /// The chosen Org Unit, whose complaints *and everything beneath it* are on
  /// screen — the server's ltree walk, not a filter this client applies.
  final String? orgUnitId;

  /// That Org Unit's own name, for the button that says which area is on
  /// screen. Never sent — the id is what the address takes.
  final String? orgUnitName;

  bool get isSet => status != null || orgUnitId != null;

  /// The query the register's address takes, in one place so a filter cannot be
  /// added to one and forgotten in the other. Built in two steps rather than as
  /// a map literal with `if (x != null)` elements, which `flutter analyze`
  /// reports as `use_null_aware_elements` — and an `info` diagnostic fails this
  /// repo's check just as an error does.
  Map<String, String> get queryParameters {
    final params = <String, String>{};
    final chosenStatus = status;
    if (chosenStatus != null) params['status'] = chosenStatus;
    final orgUnit = orgUnitId;
    if (orgUnit != null) params['orgUnitId'] = orgUnit;
    return params;
  }

  ComplaintFilters copyWith({
    String? status,
    String? orgUnitId,
    String? orgUnitName,
    bool clearStatus = false,
    bool clearOrgUnit = false,
  }) =>
      ComplaintFilters(
        status: clearStatus ? null : (status ?? this.status),
        orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
        orgUnitName: clearOrgUnit ? null : (orgUnitName ?? this.orgUnitName),
      );
}
