/// One Injury type, as `GET /api/safety/injury-types` sends it (issue #224,
/// `injury-types.js`'s own `toInjuryType`).
///
/// CONTEXT.md has no entry of its own for this: it is what an injury *was* —
/// a cut, a fracture, a burn — one half of the pair an injury classification
/// draws on, the other being [BodyPart]. One catalogue shared by every Site
/// (ADR-0005) and maintained by an administrator, which is why nothing here
/// carries a Site or an Org Unit.
///
/// The catalogue itself is not restricted. ADR-0037 restricts the three
/// structured fields on a *Safety incident* — the identified Employee, the
/// injury type and the body part — because together they are one person's
/// diagnosis. A list of the words the plant classifies injuries with names
/// nobody, so any active Account reads it.
library;

import 'package:flutter/foundation.dart';

@immutable
class InjuryType {
  const InjuryType({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
  });

  factory InjuryType.fromJson(Map<String, dynamic> json) => InjuryType(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] == true,
      );

  final String id;
  final String code;
  final String name;

  /// Whether the type is still offered as a choice. A deactivated Injury type
  /// is never deleted — an incident recorded against it is history, and an
  /// injury rate is computed from that history years later — so it is
  /// excluded from a classify dialog's choices while staying readable on an
  /// incident that already names it.
  final bool isActive;

  /// What a row and a chosen value both read as: the name first, because that
  /// is what a person recognises, then the code they quote.
  String get label => '$name · $code';
}
