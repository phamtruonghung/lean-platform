/// One Customer, as `GET /api/quality/customers` sends it (customers.js's own
/// `toCustomer`).
///
/// CONTEXT.md's **Customer**: who complains, and who a complaint belongs to.
/// The baseline's own comment is the design — "Deliberately minimal. This is
/// not a CRM" — so a Customer is a code a person quotes, a name, an optional
/// contact address and whether the plant still trades with them. Nothing here
/// carries a Site, a volume or a history, because nothing reads one.
library;

import 'package:flutter/foundation.dart';

@immutable
class Customer {
  const Customer({
    required this.id,
    required this.code,
    required this.name,
    this.contactEmail,
    required this.isActive,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        contactEmail: json['contactEmail'] as String?,
        isActive: json['isActive'] == true,
      );

  final String id;

  /// The code a complaint quotes and a person searches by. UNIQUE in the
  /// database, which is what makes a duplicate a 409 rather than a race.
  final String code;

  final String name;

  /// Where a response would be sent, when the plant knows it. Optional: a
  /// complaint can be answered through a purchase order's own contacts.
  final String? contactEmail;

  /// Whether the plant still trades with this Customer. Deactivated, never
  /// deleted — a complaint already belongs to them (customers.js's own
  /// header).
  final bool isActive;

  /// How a row reads: the name a person knows, the code they quote, and the
  /// address a response would go to when there is one.
  String get summary =>
      contactEmail == null ? '$name · $code' : '$name · $code · $contactEmail';

  /// Whether [term] names this Customer — matched against the code and the
  /// name, the two things a caller has to hand when they are recording a
  /// complaint. The Screen's own filter box uses this; it issues no request,
  /// and the address's own `?search=` is what a caller with neither uses.
  bool matches(String term) {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return code.toLowerCase().contains(needle) || name.toLowerCase().contains(needle);
  }
}
