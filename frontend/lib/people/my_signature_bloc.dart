/// The My signature Screen's state machine (issue #317, ADR-0052): reads the
/// caller's own current Signature (`GET /api/people/me/signature`), keeps a new
/// one (`PUT`) and removes the current one (`DELETE`).
///
/// A write that lands leaves the Screen showing what was sent - the server
/// stores those bytes unchanged - rather than reading them back. A refusal
/// leaves the Signature as it was and is carried beside it.
library;

import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';

sealed class MySignatureEvent {
  const MySignatureEvent();
}

/// The read, also what a failed read's retry dispatches.
class MySignatureStarted extends MySignatureEvent {
  const MySignatureStarted();
}

/// A new Signature: [png] is already normalised; [origin] is `upload` or
/// `on_screen`.
class MySignatureKept extends MySignatureEvent {
  const MySignatureKept(this.png, this.origin);
  final Uint8List png;
  final String origin;
}

class MySignatureRemoved extends MySignatureEvent {
  const MySignatureRemoved();
}

class MySignatureState {
  const MySignatureState({
    this.image,
    this.isLoading = true,
    this.isWriting = false,
    this.failure,
    this.writeFailure,
  });

  /// The current Signature's PNG bytes; null when none is kept.
  final Uint8List? image;
  final bool isLoading;
  final bool isWriting;

  /// The read failed: the Signature cannot be shown.
  final String? failure;

  /// The last write was refused; [image] is as it was.
  final String? writeFailure;
}

class MySignatureBloc extends Bloc<MySignatureEvent, MySignatureState> {
  MySignatureBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const MySignatureState()) {
    on<MySignatureStarted>(_onStarted);
    on<MySignatureKept>(_onKept);
    on<MySignatureRemoved>(_onRemoved);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(MySignatureStarted event, Emitter<MySignatureState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const MySignatureState(isLoading: false, failure: signedOutMessage));
      return;
    }
    emit(const MySignatureState());
    try {
      emit(MySignatureState(image: await _api.fetchMySignature(token), isLoading: false));
    } on PeopleApiException catch (error) {
      emit(MySignatureState(isLoading: false, failure: error.message));
    }
  }

  Future<void> _onKept(MySignatureKept event, Emitter<MySignatureState> emit) async {
    final current = state;
    if (current.isWriting || current.isLoading || current.failure != null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(MySignatureState(image: current.image, isLoading: false, writeFailure: signedOutMessage));
      return;
    }
    emit(MySignatureState(image: current.image, isLoading: false, isWriting: true));
    try {
      await _api.keepMySignature(token, event.png, origin: event.origin);
      emit(MySignatureState(image: event.png, isLoading: false));
    } on PeopleApiException catch (error) {
      emit(MySignatureState(image: current.image, isLoading: false, writeFailure: error.message));
    }
  }

  Future<void> _onRemoved(MySignatureRemoved event, Emitter<MySignatureState> emit) async {
    final current = state;
    if (current.isWriting || current.isLoading || current.failure != null || current.image == null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(MySignatureState(image: current.image, isLoading: false, writeFailure: signedOutMessage));
      return;
    }
    emit(MySignatureState(image: current.image, isLoading: false, isWriting: true));
    try {
      await _api.removeMySignature(token);
      emit(const MySignatureState(isLoading: false));
    } on PeopleApiException catch (error) {
      emit(MySignatureState(image: current.image, isLoading: false, writeFailure: error.message));
    }
  }
}
