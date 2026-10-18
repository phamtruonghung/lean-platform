/// The Training record register's state machine (issue #287): reads
/// `GET /api/people/training` filtered by an optional Org Unit (and everything
/// beneath it — the server does that) and an optional range of days, and
/// carries the one write the register offers, raising a Training record.
///
/// Org Unit browsing is `OrgUnitPickerBloc`'s job, reused exactly as
/// `AttendanceToConfirmBloc` does: this Bloc only ever sees the choice already
/// made, as an id and a name.
///
/// A raise that lands re-reads the register in place, so the new draft is on
/// screen when the dialog closes. A refusal is kept as [raiseFailure] — the
/// server's own message — for the dialog to render with what the person typed
/// still in place.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'training_record.dart';

sealed class TrainingEvent {
  const TrainingEvent();
}

/// The initial read. Also what a failed read's own retry dispatches.
class TrainingStarted extends TrainingEvent {
  const TrainingStarted();
}

class TrainingOrgUnitChosen extends TrainingEvent {
  const TrainingOrgUnitChosen({required this.orgUnitId, required this.orgUnitName});
  final String orgUnitId;
  final String orgUnitName;
}

class TrainingOrgUnitCleared extends TrainingEvent {
  const TrainingOrgUnitCleared();
}

class TrainingFromChosen extends TrainingEvent {
  const TrainingFromChosen(this.from);
  final String? from;
}

class TrainingToChosen extends TrainingEvent {
  const TrainingToChosen(this.to);
  final String? to;
}

/// The raise dialog has decided.
class TrainingRaised extends TrainingEvent {
  const TrainingRaised({
    required this.orgUnitId,
    required this.title,
    required this.trainedOn,
    required this.durationHours,
    this.trainerEmployeeId,
    this.objective,
  });

  final String orgUnitId;
  final String title;
  final String trainedOn;
  final double durationHours;
  final String? trainerEmployeeId;
  final String? objective;
}

class TrainingState {
  const TrainingState({
    this.orgUnitId,
    this.orgUnitName,
    this.from,
    this.to,
    this.records = const [],
    this.isLoading = true,
    this.failure,
    this.isRaising = false,
    this.raiseFailure,
  });

  final String? orgUnitId;
  final String? orgUnitName;
  final String? from;
  final String? to;
  final List<TrainingRecord> records;
  final bool isLoading;
  final String? failure;

  /// A raise is in flight.
  final bool isRaising;

  /// Why the last raise did not land — the server's own message. Always
  /// overwritten, never carried forward.
  final String? raiseFailure;

  bool get isFiltered => orgUnitId != null || from != null || to != null;

  TrainingState copyWith({
    String? orgUnitId,
    String? orgUnitName,
    bool clearOrgUnit = false,
    String? from,
    bool clearFrom = false,
    String? to,
    bool clearTo = false,
    List<TrainingRecord>? records,
    bool? isLoading,
    String? failure,
    bool clearFailure = false,
    bool? isRaising,
    String? raiseFailure,
    bool clearRaiseFailure = false,
  }) {
    return TrainingState(
      orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
      orgUnitName: clearOrgUnit ? null : (orgUnitName ?? this.orgUnitName),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRaising: isRaising ?? this.isRaising,
      raiseFailure: clearRaiseFailure ? null : (raiseFailure ?? this.raiseFailure),
    );
  }
}

class TrainingBloc extends Bloc<TrainingEvent, TrainingState> {
  TrainingBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const TrainingState()) {
    on<TrainingStarted>((event, emit) => _reload(emit));
    on<TrainingOrgUnitChosen>((event, emit) async {
      emit(state.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.orgUnitName, clearFailure: true));
      await _reload(emit);
    });
    on<TrainingOrgUnitCleared>((event, emit) async {
      emit(state.copyWith(clearOrgUnit: true, clearFailure: true));
      await _reload(emit);
    });
    on<TrainingFromChosen>((event, emit) async {
      emit(
        event.from == null
            ? state.copyWith(clearFrom: true, clearFailure: true)
            : state.copyWith(from: event.from, clearFailure: true),
      );
      await _reload(emit);
    });
    on<TrainingToChosen>((event, emit) async {
      emit(
        event.to == null
            ? state.copyWith(clearTo: true, clearFailure: true)
            : state.copyWith(to: event.to, clearFailure: true),
      );
      await _reload(emit);
    });
    on<TrainingRaised>(_onRaised);
  }

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  final PeopleApi _api;
  final AuthGateway _auth;

  Future<void> _onRaised(TrainingRaised event, Emitter<TrainingState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(raiseFailure: signedOutMessage));
      return;
    }
    emit(state.copyWith(isRaising: true, clearRaiseFailure: true));
    try {
      await _api.raiseTrainingRecord(
        token,
        orgUnitId: event.orgUnitId,
        title: event.title,
        trainedOn: event.trainedOn,
        durationHours: event.durationHours,
        trainerEmployeeId: event.trainerEmployeeId,
        objective: event.objective,
      );
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isRaising: false, raiseFailure: error.message));
      return;
    }
    await _reload(emit);
    emit(state.copyWith(isRaising: false));
  }

  Future<void> _reload(Emitter<TrainingState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(isLoading: false, failure: signedOutMessage));
      return;
    }

    emit(state.copyWith(isLoading: true, clearFailure: true));
    try {
      final records = await _api.fetchTrainingRecords(
        token,
        orgUnitId: state.orgUnitId,
        from: state.from,
        to: state.to,
      );
      emit(state.copyWith(records: records, isLoading: false));
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isLoading: false, failure: error.message, records: const []));
    }
  }
}
