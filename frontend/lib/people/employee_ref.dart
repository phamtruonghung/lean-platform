/// A minimal reference to an Employee — an id, an employee number, and a
/// display name — shared by every place this Module names an Employee
/// without needing the fuller [Employee]/[EmployeeDetail] record (issue #116,
/// ADR-0022): the Approval queue's own suggested Employee
/// (`GET /accounts/pending`'s `suggestedEmployee`), an Account's linked
/// Employee as the Accounts Screen shows it, and a Directory search result
/// offered for either to pick.
library;

import 'package:flutter/foundation.dart';

@immutable
class EmployeeRef {
  const EmployeeRef({required this.id, required this.employeeNo, required this.displayName});

  final String id;
  final String employeeNo;
  final String displayName;

  /// "employee number and display name" — the naming the Approval flow's own
  /// suggestion and the Accounts Screen's own linked-Employee cell both need
  /// (issue #116's acceptance criteria), spelled out once here so every
  /// caller renders it the same way.
  String get label => '$employeeNo · $displayName';
}
