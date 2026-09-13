/// The parts catalogue's own state (issue #80): the shared catalogue
/// (ADR-0005, CONTEXT.md's Part entry) that every store draws from, and an
/// administrator's own write surface over it (`POST /api/maintenance/parts`,
/// inventory-routes.js).
///
/// Route-scoped, like `AssetsBloc`: one Screen's reading of the server,
/// re-read on arrival rather than restored stale. No Site is involved — a
/// part number means the same thing at every Site.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'maintenance_api.dart';
import 'part.dart';

sealed class PartsEvent {
  const PartsEvent();
}

/// Load the whole catalogue, retired rows included. Also the retry a failed
/// load offers.
class PartsStarted extends PartsEvent {
  const PartsStarted();
}

/// The add form has decided: a whole new Part, with its unit already chosen.
class PartAddConfirmed extends PartsEvent {
  const PartAddConfirmed({
    required this.partNo,
    required this.description,
    required this.uomCode,
  });

  final String partNo;
  final String description;
  final String uomCode;
}

sealed class PartsState {
  const PartsState();
}

class PartsLoading extends PartsState {
  const PartsLoading();
}

class PartsLoaded extends PartsState {
  const PartsLoaded({required this.parts, this.isAdding = false, this.addFailure});

  final List<Part> parts;
  final bool isAdding;

  /// Why the last add did not land. Reported by the open dialog, which stays
  /// open so the caller can fix the field rather than retype the part.
  final String? addFailure;

  PartsLoaded copyWith({List<Part>? parts, bool? isAdding, String? addFailure}) => PartsLoaded(
        parts: parts ?? this.parts,
        isAdding: isAdding ?? this.isAdding,
        // Always overwritten, never carried forward — the same rule
        // JobRolesLoaded.copyWith gives mutationFailure.
        addFailure: addFailure,
      );
}

class PartsUnavailable extends PartsState {
  const PartsUnavailable({required this.message});
  final String message;
}

class PartsBloc extends Bloc<PartsEvent, PartsState> {
  PartsBloc({required MaintenanceApi maintenanceApi, required AuthGateway authGateway})
      : _api = maintenanceApi,
        _auth = authGateway,
        super(const PartsLoading()) {
    on<PartsStarted>(_onStarted);
    on<PartAddConfirmed>(_onAddConfirmed);
  }

  final MaintenanceApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(PartsStarted event, Emitter<PartsState> emit) async {
    emit(const PartsLoading());
    await _readList(emit);
  }

  Future<void> _readList(Emitter<PartsState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const PartsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final parts = await _api.fetchParts(token, includeInactive: true);
      final settled = state;
      emit(settled is PartsLoaded ? settled.copyWith(parts: parts, isAdding: false) : PartsLoaded(parts: parts));
    } on MaintenanceApiException catch (error) {
      emit(PartsUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(PartAddConfirmed event, Emitter<PartsState> emit) async {
    final current = state;
    if (current is! PartsLoaded || current.isAdding) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(addFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isAdding: true, addFailure: null));
    try {
      await _api.createPart(
        token,
        partNo: event.partNo,
        description: event.description,
        uomCode: event.uomCode,
      );
      await _readList(emit);
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! PartsLoaded) return;
      emit(settled.copyWith(isAdding: false, addFailure: error.message));
    }
  }
}
