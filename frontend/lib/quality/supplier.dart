/// One Supplier, as `GET /api/quality/suppliers` sends it (suppliers.js's own
/// `toSupplier`).
///
/// CONTEXT.md's **Supplier**: who supplies the incoming material, and who a
/// supplier NCR belongs to. The baseline's own comment is the design — "a
/// supplier problem ... an incoming non-conformance has someone to charge" — so
/// a Supplier is a code a person quotes, a name, an optional contact address and
/// whether the plant still buys from them. Nothing here carries a Site, a
/// quality rating or a history, because nothing reads one.
library;

import 'package:flutter/foundation.dart';

@immutable
class Supplier {
  const Supplier({
    required this.id,
    required this.code,
    required this.name,
    this.contactEmail,
    required this.isActive,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        contactEmail: json['contactEmail'] as String?,
        isActive: json['isActive'] == true,
      );

  final String id;

  /// The code a supplier NCR quotes and a person searches by. UNIQUE in the
  /// database, which is what makes a duplicate a 409 rather than a race.
  final String code;

  final String name;

  /// Where a claim would be sent, when the plant knows it. Optional: an
  /// incoming lot can be argued about through a purchase order's own contacts.
  final String? contactEmail;

  /// Whether the plant still buys from this Supplier. Deactivated, never
  /// deleted — a supplier NCR already belongs to them (suppliers.js's own
  /// header).
  final bool isActive;

  /// How a row reads: the name a person knows, the code they quote, and the
  /// address a claim would go to when there is one.
  String get summary =>
      contactEmail == null ? '$name · $code' : '$name · $code · $contactEmail';

  /// Whether [term] names this Supplier — matched against the code and the
  /// name, the two things a caller has to hand when they are recording a
  /// supplier NCR. The Screen's own filter box uses this; it issues no request,
  /// and the address's own `?search=` is what a caller with neither uses.
  bool matches(String term) {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return code.toLowerCase().contains(needle) || name.toLowerCase().contains(needle);
  }
}
