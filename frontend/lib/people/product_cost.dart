/// One Product standard cost, as `GET /api/people/product-costs` sends it
/// (issue #252, `product-costs.js`'s own `toProductCost`), plus the Product
/// list the form picks from.
///
/// CONTEXT.md has no entry of its own for this: a standard cost is what one
/// unit of a Product is costed at, and from when — what the baseline's
/// cost-of-poor-quality view prices scrap with
/// (`product_standard_cost(product_id, at)`). Versioned for the same reason a
/// cost rate is: a cost reported for March must stay what it was in March. One
/// catalogue shared by every Site (ADR-0005), maintained by an administrator.
library;

import 'package:flutter/foundation.dart';

/// One Product a standard cost can be recorded against, as
/// `GET /api/people/product-costs/products` sends it — the known set the form
/// picks from rather than typing an id (ADR-0023).
@immutable
class CostableProduct {
  const CostableProduct({required this.id, required this.code, required this.name});

  factory CostableProduct.fromJson(Map<String, dynamic> json) => CostableProduct(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
      );

  final String id;
  final String code;
  final String name;

  /// The name first, because that is what a person recognises, then the code
  /// they quote — the shape every catalogue label in this app takes.
  String get label => '$name · $code';
}

@immutable
class ProductCost {
  const ProductCost({
    required this.id,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.standardCost,
    required this.currency,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.note,
  });

  factory ProductCost.fromJson(Map<String, dynamic> json) => ProductCost(
        id: json['id'].toString(),
        productId: json['productId'].toString(),
        productCode: json['productCode'] as String,
        productName: json['productName'] as String,
        standardCost: (json['standardCost'] as num).toDouble(),
        currency: json['currency'] as String,
        effectiveFrom: json['effectiveFrom'] as String,
        effectiveTo: json['effectiveTo'] as String?,
        note: json['note'] as String?,
      );

  final String id;
  final String productId;
  final String productCode;
  final String productName;
  final double standardCost;
  final String currency;

  /// The day this cost starts applying, as `YYYY-MM-DD`.
  final String effectiveFrom;

  /// The day it stops, exclusive — null means it is still current. A cost is
  /// never deleted: it is closed, and a successor opened.
  final String? effectiveTo;

  final String? note;

  bool get isCurrent => effectiveTo == null;

  String get productLabel => '$productName · $productCode';

  String get costLabel => '$standardCost $currency';

  /// See [CostRate.periodLabel] — the same reading, for the same reason.
  String get periodLabel =>
      effectiveTo == null ? 'From $effectiveFrom' : '$effectiveFrom to $effectiveTo';
}
