/// One Store as `GET /api/maintenance/sites/:siteId/stores` and
/// `GET /api/maintenance/stores/:id` send it (issue #80) — one Site's shelf,
/// sitting at an Org Unit. The Site is derived from that Org Unit server-side
/// and carried back, never sent by the client.
library;

import 'package:flutter/foundation.dart';

@immutable
class Store {
  const Store({
    required this.id,
    required this.siteId,
    required this.orgUnitId,
    required this.orgUnitName,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String siteId;
  final String orgUnitId;
  final String orgUnitName;
  final String code;
  final String name;
  final bool isActive;

  String get label => '$code · $name';
}
