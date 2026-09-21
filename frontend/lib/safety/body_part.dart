/// One Body part, as `GET /api/safety/body-parts` sends it (issue #224,
/// `body-parts.js`'s own `toBodyPart`).
///
/// Where on the body an injury was, filed under the region it belongs to —
/// the other half of the pair an injury classification draws on. One
/// catalogue shared by every Site (ADR-0005), and not itself restricted; see
/// `injury_type.dart`'s own header for why ADR-0037 has nothing to say about
/// a catalogue.
library;

import 'package:flutter/foundation.dart';

/// The regions a Body part is filed under — the baseline's own CHECK on
/// `body_parts.region`, repeated here so the form offers the set rather than
/// letting a caller invent one (ADR-0023). Six fixed values, so the control is
/// a `DropdownButtonFormField` per `docs/frontend-layout.md`'s set-size rule.
abstract final class BodyPartRegion {
  static const String head = 'head';
  static const String trunk = 'trunk';
  static const String upperLimb = 'upper_limb';
  static const String lowerLimb = 'lower_limb';
  static const String multiple = 'multiple';
  static const String other = 'other';

  /// Head downward, then the two catch-alls — the order a person reads a body
  /// in, never alphabetical, and the order `body-parts.js` lists its own set
  /// in.
  static const List<String> values = [head, trunk, upperLimb, lowerLimb, multiple, other];

  static String label(String region) => switch (region) {
        head => 'Head',
        trunk => 'Trunk',
        upperLimb => 'Upper limb',
        lowerLimb => 'Lower limb',
        multiple => 'Multiple',
        other => 'Other',
        _ => region,
      };
}

@immutable
class BodyPart {
  const BodyPart({
    required this.id,
    required this.code,
    required this.name,
    required this.region,
    required this.isActive,
  });

  factory BodyPart.fromJson(Map<String, dynamic> json) => BodyPart(
        id: json['id'].toString(),
        code: json['code'] as String,
        name: json['name'] as String,
        region: json['region'] as String? ?? BodyPartRegion.other,
        isActive: json['isActive'] == true,
      );

  final String id;
  final String code;
  final String name;

  /// One of [BodyPartRegion.values].
  final String region;

  /// Whether the part is still offered as a choice — see
  /// [InjuryType.isActive]'s own note; the rule is the same.
  final bool isActive;

  String get regionLabel => BodyPartRegion.label(region);

  /// What a row and a chosen value both read as: the name, the code a person
  /// quotes, and the region it is filed under — the field that groups the
  /// catalogue and the only one this model has that an Injury type does not.
  String get label => '$name · $code · $regionLabel';
}
