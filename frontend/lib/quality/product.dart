/// One Product, as `GET /api/quality/products` sends it
/// (products.js's own `toProduct`).
///
/// CONTEXT.md's **Product**: what the plant makes, kept in one catalogue
/// shared by every Site and maintained by an administrator. A lot is not a
/// Product — it is a reference recorded against one — which is why nothing
/// here carries a Site, a quantity or a date.
///
/// [uomName] is the unit of measure's own name, joined onto the row by the
/// API so a catalogue row can say what the Product is measured in without a
/// second read. [uomCode] is what a write sends.
library;

import 'package:flutter/foundation.dart';

@immutable
class Product {
  const Product({
    required this.id,
    required this.code,
    required this.name,
    required this.uomCode,
    required this.uomName,
    required this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        uomCode: json['uomCode'] as String,
        uomName: json['uomName'] as String? ?? '',
        isActive: json['isActive'] == true,
      );

  final String id;
  final String code;
  final String name;

  /// The unit of measure this Product is measured in — a code the plant uses
  /// (ADR-0023: chosen from the list, never typed).
  final String uomCode;

  /// That unit's own name, for display.
  final String uomName;

  /// Whether the Product is still in use. A deactivated Product is one the
  /// catalogue has retired; it is never deleted, because a Non-conformance
  /// recorded against it is history (products.js's own header).
  final bool isActive;
}
