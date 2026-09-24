/// The product standard cost catalogue's own state (issue #252): what one unit
/// of a Product is costed at, and an administrator's own write surface over it
/// (`POST`/`PATCH /api/people/product-costs`, plus the revision route,
/// product-cost-routes.js).
///
/// `CostRatesBloc`'s shape exactly, with the scope list replaced by the Product
/// list the form picks from — see that file's own header for why the picker's
/// list is read alongside the catalogue and why a revision is its own event.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'product_cost.dart';

sealed class ProductCostsEvent {
  const ProductCostsEvent();
}

class ProductCostsStarted extends ProductCostsEvent {
  const ProductCostsStarted();
}

class ProductCostsAddConfirmed extends ProductCostsEvent {
  const ProductCostsAddConfirmed({required this.body});

  final Map<String, Object?> body;
}

class ProductCostsCorrectionConfirmed extends ProductCostsEvent {
  const ProductCostsCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

class ProductCostsRevisionConfirmed extends ProductCostsEvent {
  const ProductCostsRevisionConfirmed({required this.id, required this.body});

  final String id;
  final Map<String, Object?> body;
}

sealed class ProductCostsState {
  const ProductCostsState();
}

class ProductCostsLoading extends ProductCostsState {
  const ProductCostsLoading();
}

class ProductCostsLoaded extends ProductCostsState {
  const ProductCostsLoaded({
    required this.productCosts,
    this.products = const [],
    this.productsFailure,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<ProductCost> productCosts;

  /// The Products a cost may be recorded against. Empty with a
  /// [productsFailure] set means the list could not be read — the form blocks
  /// submission rather than falling back to a typed id (ADR-0023 point 6).
  final List<CostableProduct> products;
  final String? productsFailure;

  final bool isMutating;
  final String? mutationFailure;

  ProductCostsLoaded copyWith({
    List<ProductCost>? productCosts,
    List<CostableProduct>? products,
    String? productsFailure,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      ProductCostsLoaded(
        productCosts: productCosts ?? this.productCosts,
        products: products ?? this.products,
        productsFailure: productsFailure ?? this.productsFailure,
        isMutating: isMutating ?? this.isMutating,
        mutationFailure: mutationFailure,
      );
}

class ProductCostsUnavailable extends ProductCostsState {
  const ProductCostsUnavailable({required this.message});

  final String message;
}

class ProductCostsBloc extends Bloc<ProductCostsEvent, ProductCostsState> {
  ProductCostsBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const ProductCostsLoading()) {
    on<ProductCostsStarted>(_onStarted);
    on<ProductCostsAddConfirmed>(_onAddConfirmed);
    on<ProductCostsCorrectionConfirmed>(_onCorrectionConfirmed);
    on<ProductCostsRevisionConfirmed>(_onRevisionConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(ProductCostsStarted event, Emitter<ProductCostsState> emit) async {
    emit(const ProductCostsLoading());

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ProductCostsUnavailable(message: signedOutMessage));
      return;
    }

    List<ProductCost> productCosts;
    try {
      productCosts = await _api.fetchProductCosts(token);
    } on PeopleApiException catch (error) {
      emit(ProductCostsUnavailable(message: error.message));
      return;
    }

    List<CostableProduct> products = const [];
    String? productsFailure;
    try {
      products = await _api.fetchCostableProducts(token);
    } on PeopleApiException catch (error) {
      productsFailure = error.message;
    }

    emit(ProductCostsLoaded(
      productCosts: productCosts,
      products: products,
      productsFailure: productsFailure,
    ));
  }

  Future<void> _readList(Emitter<ProductCostsState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ProductCostsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final productCosts = await _api.fetchProductCosts(token);
      final settled = state;
      emit(
        settled is ProductCostsLoaded
            ? settled.copyWith(productCosts: productCosts, isMutating: false)
            : ProductCostsLoaded(productCosts: productCosts),
      );
    } on PeopleApiException catch (error) {
      emit(ProductCostsUnavailable(message: error.message));
    }
  }

  Future<void> _write(
    Emitter<ProductCostsState> emit,
    Future<void> Function(String token) send,
  ) async {
    final current = state;
    if (current is! ProductCostsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await send(token);
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! ProductCostsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onAddConfirmed(
    ProductCostsAddConfirmed event,
    Emitter<ProductCostsState> emit,
  ) =>
      _write(emit, (token) => _api.createProductCost(token, event.body));

  Future<void> _onCorrectionConfirmed(
    ProductCostsCorrectionConfirmed event,
    Emitter<ProductCostsState> emit,
  ) =>
      _write(emit, (token) => _api.updateProductCost(token, event.id, event.changes));

  Future<void> _onRevisionConfirmed(
    ProductCostsRevisionConfirmed event,
    Emitter<ProductCostsState> emit,
  ) =>
      _write(emit, (token) => _api.reviseProductCost(token, event.id, event.body));
}
