/// The per-Employee worked-hours summary's state machine (issue #263): reads
/// one Employee's confirmed hours across an optional date window from
/// `GET /api/people/employees/:employeeId/work-hours`.
///
/// The route is an open read (ADR-0009 — an Employee's own work record is
/// part of the directory, which is deliberately not a secret), so this Bloc
/// needs no Org Unit scope question: it is keyed to one Employee by the
/// Screen's own [employeeId] and asks nothing about Grants. Its only choices
/// are the optional [from]/[to] window, each of which re-reads.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'worked_hours.dart';

sealed class WorkedHoursEvent {
  const WorkedHoursEvent();
}

/// The initial read, with the optional window the Screen was built with. Also
/// what a failed read's own retry dispatches.
class WorkedHoursStarted extends WorkedHoursEvent {
  const WorkedHoursStarted({this.from, this.to});

  final String? from;
  final String? to;
}

/// Re-read with a new [from] bound. `null` clears the lower bound.
class WorkedHoursFromChosen extends WorkedHoursEvent {
  const WorkedHoursFromChosen(this.from);
  final String? from;
}

/// Re-read with a new [to] bound. `null` clears the upper bound.
class WorkedHoursToChosen extends WorkedHoursEvent {
  const WorkedHoursToChosen(this.to);
  final String? to;
}

class WorkedHoursState {
  const WorkedHoursState({
    this.from,
    this.to,
    this.days = const [],
    this.totals,
    this.isLoading = true,
    this.failure,
  });

  final String? from;
  final String? to;
  final List<WorkedHoursDay> days;
  final WorkedHoursTotals? totals;
  final bool isLoading;
  final String? failure;

  WorkedHoursState copyWith({
    String? from,
    bool clearFrom = false,
    String? to,
    bool clearTo = false,
    List<WorkedHoursDay>? days,
    WorkedHoursTotals? totals,
    bool clearTotals = false,
    bool? isLoading,
    String? failure,
    bool clearFailure = false,
  }) {
    return WorkedHoursState(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      days: days ?? this.days,
      totals: clearTotals ? null : (totals ?? this.totals),
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class WorkedHoursBloc extends Bloc<WorkedHoursEvent, WorkedHoursState> {
  WorkedHoursBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.employeeId,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const WorkedHoursState()) {
    on<WorkedHoursStarted>((event, emit) => _reload(emit, from: event.from, to: event.to));
    on<WorkedHoursFromChosen>((event, emit) => _reload(emit, from: event.from, to: state.to));
    on<WorkedHoursToChosen>((event, emit) => _reload(emit, from: state.from, to: event.to));
  }

  final PeopleApi _api;
  final AuthGateway _auth;
  final String employeeId;

  Future<void> _reload(Emitter<WorkedHoursState> emit, {String? from, String? to}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(failure: 'This session has ended. Sign in again to continue.', isLoading: false));
      return;
    }

    emit(state.copyWith(from: from, to: to, isLoading: true, clearFailure: true));
    try {
      final result = await _api.fetchEmployeeWorkedHours(token, employeeId, from: from, to: to);
      emit(state.copyWith(days: result.days, totals: result.totals, isLoading: false));
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isLoading: false, failure: error.message, days: const [], clearTotals: true));
    }
  }
}