/// The Employee Signature dialog's state machine (issue #320, ADR-0052): reads
/// an Employee's current Signature as an administrator (`GET
/// /api/people/employees/:id/signature`), keeps a new one (`PUT`) and removes
/// it (`DELETE`).
///
/// A write that lands is followed by a re-read, so the dialog shows who set it
/// and for whom as the server now records it. A 409 - the Employee holds an
/// Account of their own - ends the dialog's writes: [refusal] carries the
/// Module's own words. Any other refusal leaves the Signature as it was.
library;

import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'employee_signature.dart';

sealed class EmployeeSignatureEvent {
  const EmployeeSignatureEvent();
}

class EmployeeSignatureStarted extends EmployeeSignatureEvent {
  const EmployeeSignatureStarted();
}

class EmployeeSignatureKept extends EmployeeSignatureEvent {
  const EmployeeSignatureKept(this.png, this.origin);
  final Uint8List png;
  final String origin;
}

class EmployeeSignatureRemoved extends EmployeeSignatureEvent {
  const EmployeeSignatureRemoved();
}

class EmployeeSignatureState {
  const EmployeeSignatureState({
    this.signature,
    this.isLoading = true,
    this.isWriting = false,
    this.failure,
    this.writeFailure,
    this.refusal,
  });

  final EmployeeSignature? signature;
  final bool isLoading;
  final bool isWriting;
  final String? failure;
  final String? writeFailure;

  /// The 409's own words: the Employee holds an Account, so only they set it.
  final String? refusal;
}

class EmployeeSignatureBloc extends Bloc<EmployeeSignatureEvent, EmployeeSignatureState> {
  EmployeeSignatureBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.employeeId,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const EmployeeSignatureState()) {
    on<EmployeeSignatureStarted>(_onStarted);
    on<EmployeeSignatureKept>(_onKept);
    on<EmployeeSignatureRemoved>(_onRemoved);
  }

  final PeopleApi _api;
  final AuthGateway _auth;
  final String employeeId;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(EmployeeSignatureStarted event, Emitter<EmployeeSignatureState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const EmployeeSignatureState(isLoading: false, failure: signedOutMessage));
      return;
    }
    emit(const EmployeeSignatureState());
    try {
      emit(EmployeeSignatureState(signature: await _api.fetchEmployeeSignature(token, employeeId), isLoading: false));
    } on PeopleApiException catch (error) {
      emit(EmployeeSignatureState(isLoading: false, failure: error.message));
    }
  }

  Future<void> _onKept(EmployeeSignatureKept event, Emitter<EmployeeSignatureState> emit) =>
      _write(emit, (token) => _api.keepEmployeeSignature(token, employeeId, event.png, origin: event.origin));

  Future<void> _onRemoved(EmployeeSignatureRemoved event, Emitter<EmployeeSignatureState> emit) {
    if (state.signature == null) return Future<void>.value();
    return _write(emit, (token) => _api.removeEmployeeSignature(token, employeeId));
  }

  Future<void> _write(
    Emitter<EmployeeSignatureState> emit,
    Future<void> Function(String token) write,
  ) async {
    final current = state;
    if (current.isWriting || current.isLoading || current.failure != null || current.refusal != null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(EmployeeSignatureState(signature: current.signature, isLoading: false, writeFailure: signedOutMessage));
      return;
    }
    emit(EmployeeSignatureState(signature: current.signature, isLoading: false, isWriting: true));
    try {
      await write(token);
      emit(EmployeeSignatureState(signature: await _api.fetchEmployeeSignature(token, employeeId), isLoading: false));
    } on PeopleApiException catch (error) {
      if (error.statusCode == 409) {
        emit(EmployeeSignatureState(signature: current.signature, isLoading: false, refusal: error.message));
      } else {
        emit(EmployeeSignatureState(signature: current.signature, isLoading: false, writeFailure: error.message));
      }
    }
  }
}
