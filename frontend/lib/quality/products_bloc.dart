/// The Product catalogue's own state (issue #203): the shared reference data
/// (ADR-0005, CONTEXT.md's Product entry) every later Quality record will
/// point at, and — on this Screen — an administrator's own write surface over
/// it (`POST`/`PATCH /api/quality/products`, product-routes.js).
///
/// Route-scoped, like `JobRolesBloc`: one Screen's own reading of the server,
/// re-read on arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'product.dart';
import 'quality_api.dart';

sealed class ProductsEvent {
  const ProductsEvent();
}

/// Load the whole catalogue, deactivated rows included. Also the retry a
/// failed load offers.
class ProductsStarted extends ProductsEvent {
  const ProductsStarted();
}

/// The add form has decided: a whole new Product. Same contract as
/// `JobRolesAddConfirmed` — the dialog decides, the Bloc only ever sees a
/// decision already made.
class ProductsAddConfirmed extends ProductsEvent {
  const ProductsAddConfirmed({required this.code, required this.name, required this.uomCode});

  final String code;
  final String name;
  final String uomCode;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed — the same contract `JobRolesCorrectionConfirmed` carries,
/// on `updateProduct`'s (products.js) `hasOwnProperty` idiom at the other end.
/// `isActive` rides in [changes] too: retiring or reactivating a Product is a
/// correction, not a dedicated verb (products.js's own header — there is no
/// delete, and no second action here for it).
class ProductsCorrectionConfirmed extends ProductsEvent {
  const ProductsCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class ProductsState {
  const ProductsState();
}

class ProductsLoading extends ProductsState {
  const ProductsLoading();
}

/// The catalogue as it last read. An empty [products] is not a state of its
/// own — the same reasoning `JobRolesLoaded` gives its own empty list.
class ProductsLoaded extends ProductsState {
  const ProductsLoaded({required this.products, this.isMutating = false, this.mutationFailure});

  final List<Product> products;

  /// An add or a correction is in flight — one flag, not two: this Screen has
  /// one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by whichever dialog
  /// is open, which stays open so the caller can fix the field rather than
  /// retype the whole Product.
  final String? mutationFailure;

  ProductsLoaded copyWith({List<Product>? products, bool? isMutating, String? mutationFailure}) =>
      ProductsLoaded(
        products: products ?? this.products,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `JobRolesLoaded.copyWith` gives its own failure.
        mutationFailure: mutationFailure,
      );
}

class ProductsUnavailable extends ProductsState {
  const ProductsUnavailable({required this.message});

  final String message;
}

class ProductsBloc extends Bloc<ProductsEvent, ProductsState> {
  ProductsBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const ProductsLoading()) {
    on<ProductsStarted>(_onStarted);
    on<ProductsAddConfirmed>(_onAddConfirmed);
    on<ProductsCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(ProductsStarted event, Emitter<ProductsState> emit) async {
    emit(const ProductsLoading());
    await _readList(emit);
  }

  // Deactivated rows included (`includeInactive: true`): this Screen's whole
  // purpose is reaching a retired Product to reactivate it, the same choice
  // `JobRolesBloc._readList` makes for the job role catalogue.
  Future<void> _readList(Emitter<ProductsState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ProductsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final products = await _api.fetchProducts(token, includeInactive: true);
      final settled = state;
      emit(
        settled is ProductsLoaded
            ? settled.copyWith(products: products, isMutating: false)
            : ProductsLoaded(products: products),
      );
    } on QualityApiException catch (error) {
      emit(ProductsUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(ProductsAddConfirmed event, Emitter<ProductsState> emit) async {
    final current = state;
    if (current is! ProductsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createProduct(token, code: event.code, name: event.name, uomCode: event.uomCode);
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! ProductsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    ProductsCorrectionConfirmed event,
    Emitter<ProductsState> emit,
  ) async {
    final current = state;
    if (current is! ProductsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateProduct(token, event.id, event.changes);
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! ProductsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
