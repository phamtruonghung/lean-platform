/// The floor surface's own small models (issue #77).
///
/// Deliberately not `WorkOrder` cousins: a device's read answers with the Org
/// Unit it is registered against, and the identify exchange answers with the
/// Employee it resolved — neither is a Maintenance record the rest of the app
/// reads, so neither belongs in a Screen-driven Bloc's own model file.
library;

/// The Org Unit a shared device is registered against, and the Site it belongs
/// to — what the floor Screen names at the top of the work list.
class FloorInfo {
  const FloorInfo({
    required this.orgUnitId,
    required this.orgUnitName,
    required this.siteId,
  });

  final String orgUnitId;
  final String orgUnitName;
  final String siteId;
}

/// One technician's short-lived identification, exchanged for a PIN at the
/// identify endpoint. The [token] lives only as long as the action it is
/// attached to: the Bloc holds it in a local variable and never puts it on a
/// state object, so a Screen that is left alone does not carry the last
/// person's authority into the next person's shift (ADR-0016).
class FloorIdentification {
  const FloorIdentification({
    required this.token,
    required this.employeeId,
    required this.employeeName,
  });

  final String token;
  final String employeeId;
  final String employeeName;
}
