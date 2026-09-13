/// One store's stock (issue #80): what is on the shelf, derived from the
/// store's movements, and the receive action that adds to it.
///
/// Route-scoped, like `WorkOrderDetailBloc`: one Screen's reading of the
/// server, keyed on the store id in the address and re-read on arrival. The
/// parts catalogue rides along so the receive dialog can offer a part to pick
/// without a second Screen.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'part.dart';
import 'stock_level.dart';
import 'store.dart';

sealed class StoreStockEvent {
  const StoreStockEvent();
}

/// Load the store, its stock and the parts catalogue the receive dialog
/// offers. Also the retry a failed load offers.
class StoreStockStarted extends StoreStockEvent {
  const StoreStockStarted();
}

/// The receive form has decided: this many of this part arrived.
class StockReceiveConfirmed extends StoreStockEvent {
  const StockReceiveConfirmed({required this.partId, required this.quantity, this.reason});

  final String partId;
  final num quantity;
  final String? reason;
}

sealed class StoreStockState {
  const StoreStockState();
}

class StoreStockLoading extends StoreStockState {
  const StoreStockLoading();
}

class StoreStockLoaded extends StoreStockState {
  const StoreStockLoaded({
    required this.store,
    required this.parts,
    required this.stock,
    this.isReceiving = false,
    this.receiveFailure,
  });

  final Store store;
  final List<Part> parts;
  final List<StockLevel> stock;

  /// A receive is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isReceiving;

  /// Why the last receive did not land. Reported by the open dialog, which
  /// stays open so the caller can fix the quantity or reason.
  final String? receiveFailure;

  StoreStockLoaded copyWith({
    List<StockLevel>? stock,
    bool? isReceiving,
    String? receiveFailure,
  }) =>
      StoreStockLoaded(
        store: store,
        parts: parts,
        stock: stock ?? this.stock,
        isReceiving: isReceiving ?? this.isReceiving,
        // Always overwritten, never carried forward — the same rule
        // PartsLoaded.copyWith gives addFailure.
        receiveFailure: receiveFailure,
      );
}

class StoreStockUnavailable extends StoreStockState {
  const StoreStockUnavailable({required this.message});
  final String message;
}

class StoreStockBloc extends Bloc<StoreStockEvent, StoreStockState> {
  StoreStockBloc({
    required MaintenanceApi maintenanceApi,
    required AuthGateway authGateway,
    required this.storeId,
  })  : _api = maintenanceApi,
        _auth = authGateway,
        super(const StoreStockLoading()) {
    on<StoreStockStarted>(_onStarted);
    on<StockReceiveConfirmed>(_onReceiveConfirmed);
  }

  final MaintenanceApi _api;
  final AuthGateway _auth;
  final String storeId;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(StoreStockStarted event, Emitter<StoreStockState> emit) async {
    emit(const StoreStockLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const StoreStockUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final (store, stock) = await _api.fetchStoreStock(token, storeId);
      final parts = await _api.fetchParts(token);
      emit(StoreStockLoaded(store: store, parts: parts, stock: stock));
    } on MaintenanceApiException catch (error) {
      emit(StoreStockUnavailable(message: error.message));
    }
  }

  Future<void> _onReceiveConfirmed(StockReceiveConfirmed event, Emitter<StoreStockState> emit) async {
    final current = state;
    if (current is! StoreStockLoaded || current.isReceiving) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(receiveFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isReceiving: true, receiveFailure: null));
    try {
      await _api.receiveStock(
        token,
        storeId,
        partId: event.partId,
        quantity: event.quantity,
        reason: event.reason,
      );
      // Re-read the derived level rather than patching the response in: the
      // level is a server-owned sum, and the server is the only thing that
      // knows all of its terms. The store row itself is unchanged by a
      // receipt, so only its stock is taken from the re-read.
      final (_, stock) = await _api.fetchStoreStock(token, storeId);
      final settled = state;
      if (settled is! StoreStockLoaded) return;
      emit(settled.copyWith(stock: stock, isReceiving: false));
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! StoreStockLoaded) return;
      emit(settled.copyWith(isReceiving: false, receiveFailure: error.message));
    }
  }
}
