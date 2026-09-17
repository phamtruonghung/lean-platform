/// The Customer list's own state (issue #214): the record a complaint belongs
/// to, read by every approved Account and written by an administrator alone
/// (`POST`/`PATCH /api/quality/customers`, customer-routes.js).
///
/// Route-scoped, like `ProductsBloc`: one Screen's own reading of the server,
/// re-read on arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'customer.dart';
import 'quality_api.dart';

sealed class CustomersEvent {
  const CustomersEvent();
}

/// Load the whole list, deactivated Customers included: the Screen's own
/// purpose includes reaching a retired row to reactivate it.
class CustomersStarted extends CustomersEvent {
  const CustomersStarted();
}

/// The form has decided: a whole new Customer. The dialog decides, the Bloc
/// only ever sees a decision already made — `ProductsAddConfirmed`'s own
/// contract.
class CustomersAddConfirmed extends CustomersEvent {
  const CustomersAddConfirmed({
    required this.code,
    required this.name,
    this.contactEmail,
  });

  final String code;
  final String name;
  final String? contactEmail;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed, on `updateCustomer`'s (customers.js) `hasOwnProperty`
/// idiom at the other end. `isActive` rides in [changes] too: retiring or
/// reactivating a Customer is a correction, not a dedicated verb.
class CustomersCorrectionConfirmed extends CustomersEvent {
  const CustomersCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

sealed class CustomersState {
  const CustomersState();
}

class CustomersLoading extends CustomersState {
  const CustomersLoading();
}

/// The list as it last read. An empty [customers] is not a state of its own —
/// the same reasoning `ProductsLoaded` gives its own empty list.
class CustomersLoaded extends CustomersState {
  const CustomersLoaded({
    required this.customers,
    this.isMutating = false,
    this.mutationFailure,
  });

  final List<Customer> customers;

  /// An add or a correction is in flight — one flag, not two: this Screen has
  /// one mutation at a time.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by the form, which
  /// stays open so the caller can fix the field rather than retype the whole
  /// Customer.
  final String? mutationFailure;

  CustomersLoaded copyWith({
    List<Customer>? customers,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      CustomersLoaded(
        customers: customers ?? this.customers,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `ProductsLoaded.copyWith` gives its own failure.
        mutationFailure: mutationFailure,
      );
}

class CustomersUnavailable extends CustomersState {
  const CustomersUnavailable({required this.message});

  final String message;
}

class CustomersBloc extends Bloc<CustomersEvent, CustomersState> {
  CustomersBloc({required QualityApi qualityApi, required AuthGateway authGateway})
      : _api = qualityApi,
        _auth = authGateway,
        super(const CustomersLoading()) {
    on<CustomersStarted>(_onStarted);
    on<CustomersAddConfirmed>(_onAddConfirmed);
    on<CustomersCorrectionConfirmed>(_onCorrectionConfirmed);
  }

  final QualityApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(CustomersStarted event, Emitter<CustomersState> emit) async {
    emit(const CustomersLoading());
    await _readList(emit);
  }

  // Deactivated rows included (`includeInactive: true`): this Screen's whole
  // purpose is reaching a retired Customer to reactivate them.
  Future<void> _readList(Emitter<CustomersState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CustomersUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final customers = await _api.fetchCustomers(token, includeInactive: true);
      final settled = state;
      emit(
        settled is CustomersLoaded
            ? settled.copyWith(customers: customers, isMutating: false)
            : CustomersLoaded(customers: customers),
      );
    } on QualityApiException catch (error) {
      emit(CustomersUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(CustomersAddConfirmed event, Emitter<CustomersState> emit) async {
    final current = state;
    if (current is! CustomersLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createCustomer(
        token,
        code: event.code,
        name: event.name,
        contactEmail: event.contactEmail,
      );
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! CustomersLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    CustomersCorrectionConfirmed event,
    Emitter<CustomersState> emit,
  ) async {
    final current = state;
    if (current is! CustomersLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateCustomer(token, event.id, event.changes);
      await _readList(emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! CustomersLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
