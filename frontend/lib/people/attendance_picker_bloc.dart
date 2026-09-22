/// The Attendance picker's own small state machine (issue #249): once an
/// Org Unit and a production day are both chosen, reads that day's shift
/// instances at the Org Unit, so a supervisor can open the one they mean.
/// Org Unit browsing itself is `OrgUnitPickerBloc`'s job, reused as-is
/// (`directory_org_unit_filter_dialog.dart`'s own precedent for driving that
/// Bloc from a second Screen); this Bloc only ever sees the choice already
/// made.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'attendance.dart';

sealed class AttendancePickerEvent {
  const AttendancePickerEvent();
}

class AttendancePickerOrgUnitChosen extends AttendancePickerEvent {
  const AttendancePickerOrgUnitChosen({required this.orgUnitId, required this.orgUnitName});
  final String orgUnitId;
  final String orgUnitName;
}

class AttendancePickerDateChosen extends AttendancePickerEvent {
  const AttendancePickerDateChosen(this.date);
  final String date;
}

class AttendancePickerState {
  const AttendancePickerState({
    this.orgUnitId,
    this.orgUnitName,
    this.date,
    this.shiftInstances = const [],
    this.isLoading = false,
    this.failure,
  });

  final String? orgUnitId;
  final String? orgUnitName;
  final String? date;
  final List<ShiftInstanceSummary> shiftInstances;
  final bool isLoading;
  final String? failure;

  AttendancePickerState copyWith({
    String? orgUnitId,
    String? orgUnitName,
    String? date,
    List<ShiftInstanceSummary>? shiftInstances,
    bool? isLoading,
    String? failure,
  }) =>
      AttendancePickerState(
        orgUnitId: orgUnitId ?? this.orgUnitId,
        orgUnitName: orgUnitName ?? this.orgUnitName,
        date: date ?? this.date,
        shiftInstances: shiftInstances ?? this.shiftInstances,
        isLoading: isLoading ?? this.isLoading,
        failure: failure,
      );
}

class AttendancePickerBloc extends Bloc<AttendancePickerEvent, AttendancePickerState> {
  AttendancePickerBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const AttendancePickerState()) {
    on<AttendancePickerOrgUnitChosen>(_onOrgUnitChosen);
    on<AttendancePickerDateChosen>(_onDateChosen);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  Future<void> _onOrgUnitChosen(
    AttendancePickerOrgUnitChosen event,
    Emitter<AttendancePickerState> emit,
  ) async {
    emit(state.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.orgUnitName, failure: null));
    await _reload(emit);
  }

  Future<void> _onDateChosen(
    AttendancePickerDateChosen event,
    Emitter<AttendancePickerState> emit,
  ) async {
    emit(state.copyWith(date: event.date, failure: null));
    await _reload(emit);
  }

  Future<void> _reload(Emitter<AttendancePickerState> emit) async {
    final orgUnitId = state.orgUnitId;
    final date = state.date;
    if (orgUnitId == null || date == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(failure: 'This session has ended. Sign in again to continue.'));
      return;
    }

    emit(state.copyWith(isLoading: true, failure: null));
    try {
      final shiftInstances = await _api.fetchShiftInstances(token, orgUnitId, date: date);
      emit(state.copyWith(shiftInstances: shiftInstances, isLoading: false));
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isLoading: false, failure: error.message, shiftInstances: const []));
    }
  }
}
