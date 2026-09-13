/// One row of a store's stock as `GET
/// /api/maintenance/stores/:storeId/stock` sends it (issue #80). The quantity
/// is derived from the store's movements, never a number the client or the
/// database stores directly.
library;

import 'package:flutter/foundation.dart';

@immutable
class StockLevel {
  const StockLevel({
    required this.partId,
    required this.partNo,
    required this.description,
    required this.uomCode,
    required this.quantity,
  });

  final String partId;
  final String partNo;
  final String description;
  final String uomCode;
  final num quantity;
}
