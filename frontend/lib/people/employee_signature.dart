/// An Employee's current Signature as an administrator sees it (issue #320,
/// CONTEXT.md's Signature, ADR-0052): the image, who set it, and whether they
/// set it for the Employee or the Employee set it themselves
/// (`GET /api/people/employees/:id/signature` and its `/details`).
library;

import 'package:flutter/foundation.dart';

@immutable
class EmployeeSignature {
  const EmployeeSignature({
    required this.image,
    required this.setByName,
    required this.setForEmployee,
    required this.origin,
  });

  final Uint8List image;

  /// The display name of the Account that set it; null when that Account is gone.
  final String? setByName;

  /// True when an administrator set it for the Employee; false when the
  /// Employee set it themselves.
  final bool setForEmployee;

  /// `upload` or `on_screen`.
  final String origin;

  factory EmployeeSignature.fromDetailsJson(Map<String, dynamic> json, Uint8List image) =>
      EmployeeSignature(
        image: image,
        setByName: json['setByName'] as String?,
        setForEmployee: json['setForEmployee'] as bool? ?? true,
        origin: json['origin'] as String? ?? 'upload',
      );
}
