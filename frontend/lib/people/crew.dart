/// A Crew: the named group of Employees a Site's floor works as, with how many
/// of them it holds (`GET /api/people/sites/:siteId/crews`).
///
/// A Crew belongs to a Site, not to an Org Unit, so there is no Org Unit name
/// here. [employeeCount] is what the assign pickers show beside the name, so a
/// person can see how many people choosing the Crew would reach before the
/// server's own preview answers.
library;

import 'package:flutter/foundation.dart';

@immutable
class Crew {
  const Crew({
    required this.id,
    required this.siteId,
    required this.code,
    required this.name,
    required this.isActive,
    required this.employeeCount,
  });

  final String id;
  final String siteId;
  final String code;
  final String name;
  final bool isActive;
  final int employeeCount;

  @override
  bool operator ==(Object other) =>
      other is Crew &&
      other.id == id &&
      other.siteId == siteId &&
      other.code == code &&
      other.name == name &&
      other.isActive == isActive &&
      other.employeeCount == employeeCount;

  @override
  int get hashCode => Object.hash(id, siteId, code, name, isActive, employeeCount);
}
