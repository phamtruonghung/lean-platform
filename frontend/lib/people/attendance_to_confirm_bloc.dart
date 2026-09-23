/// The attendance-to-confirm worklist's own small state machine (issue
/// #250): reads `GET /api/people/attendance-to-confirm`, filtered by an
/// optional Org Unit (and everything beneath it) and an optional production
/// day range. Unlike `AttendancePickerBloc`, no filter is required before a
/// read happens — the worklist is already scoped server-side to the
/// caller's own edit Grants (or every Site, for an administrator), so
/// showing it with no filter at all is a meaningful, non-empty starting
/// point, not a placeholder waiting on a choice.
///
/// Org Unit browsing is `OrgUnitPickerBloc`'s job, reused exactly as
/// `AttendancePickerScreen`/`AttendancePickerBloc` already do: this Bloc only
/// ever sees the choice already made, as an id and a name.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'attendance.dart';

sealed class AttendanceToConfirmEvent {
  const AttendanceToConfirmEvent();
}

/// The initial read, with whatever filters the Screen was built with (none,
/// ordinarily). Also what a failed read's own retry dispatches.
class AttendanceToConfirmStarted extends AttendanceToConfirmEvent {
  const AttendanceToConfirmStarted();
}

class AttendanceToConfirmOrgUnitChosen extends AttendanceToConfirmEvent {
  const AttendanceToConfirmOrgUnitChosen({required this.orgUnitId, required this.orgUnitName});
  final String orgUnitId;
  final String orgUnitName;
}

class AttendanceToConfirmOrgUnitCleared extends AttendanceToConfirmEvent {
  const AttendanceToConfirmOrgUnitCleared();
}

class AttendanceToConfirmFromChosen extends AttendanceToConfirmEvent {
  const AttendanceToConfirmFromChosen(this.from);
  final String? from;
}

class AttendanceToConfirmToChosen extends AttendanceToConfirmEvent {
  const AttendanceToConfirmToChosen(this.to);
  final String? to;
}

class AttendanceToConfirmState {
  const AttendanceToConfirmState({
    this.orgUnitId,
    this.orgUnitName,
    this.from,
    this.to,
    this.entries = const [],
    this.isLoading = true,
    this.failure,
  });

  final String? orgUnitId;
  final String? orgUnitName;
  final String? from;
  final String? to;
  final List<AttendanceToConfirmEntry> entries;
  final bool isLoading;
  final String? failure;

  AttendanceToConfirmState copyWith({
    String? orgUnitId,
    bool clearOrgUnitId = false,
    String? orgUnitName,
    bool clearOrgUnitName = false,
    String? from,
    bool clearFrom = false,
    String? to,
    bool clearTo = false,
    List<AttendanceToConfirmEntry>? entries,
    bool? isLoading,
    String? failure,
    bool clearFailure = false,
  }) {
    return AttendanceToConfirmState(
      orgUnitId: clearOrgUnitId ? null : (orgUnitId ?? this.orgUnitId),
      orgUnitName: clearOrgUnitName ? null : (orgUnitName ?? this.orgUnitName),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class AttendanceToConfirmBloc extends Bloc<AttendanceToConfirmEvent, AttendanceToConfirmState> {
  AttendanceToConfirmBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const AttendanceToConfirmState()) {
    on<AttendanceToConfirmStarted>((event, emit) => _reload(emit));
    on<AttendanceToConfirmOrgUnitChosen>(_onOrgUnitChosen);
    on<AttendanceToConfirmOrgUnitCleared>(_onOrgUnitCleared);
    on<AttendanceToConfirmFromChosen>(_onFromChosen);
    on<AttendanceToConfirmToChosen>(_onToChosen);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  Future<void> _onOrgUnitChosen(
    AttendanceToConfirmOrgUnitChosen event,
    Emitter<AttendanceToConfirmState> emit,
  ) async {
    emit(state.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.orgUnitName, clearFailure: true));
    await _reload(emit);
  }

  Future<void> _onOrgUnitCleared(
    AttendanceToConfirmOrgUnitCleared event,
    Emitter<AttendanceToConfirmState> emit,
  ) async {
    emit(state.copyWith(clearOrgUnitId: true, clearOrgUnitName: true, clearFailure: true));
    await _reload(emit);
  }

  Future<void> _onFromChosen(
    AttendanceToConfirmFromChosen event,
    Emitter<AttendanceToConfirmState> emit,
  ) async {
    emit(
      event.from == null
          ? state.copyWith(clearFrom: true, clearFailure: true)
          : state.copyWith(from: event.from, clearFailure: true),
    );
    await _reload(emit);
  }

  Future<void> _onToChosen(
    AttendanceToConfirmToChosen event,
    Emitter<AttendanceToConfirmState> emit,
  ) async {
    emit(
      event.to == null
          ? state.copyWith(clearTo: true, clearFailure: true)
          : state.copyWith(to: event.to, clearFailure: true),
    );
    await _reload(emit);
  }

  Future<void> _reload(Emitter<AttendanceToConfirmState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(isLoading: false, failure: 'This session has ended. Sign in again to continue.'));
      return;
    }

    emit(state.copyWith(isLoading: true, clearFailure: true));
    try {
      final entries = await _api.fetchAttendanceToConfirm(
        token,
        orgUnitId: state.orgUnitId,
        from: state.from,
        to: state.to,
      );
      emit(state.copyWith(entries: entries, isLoading: false));
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isLoading: false, failure: error.message, entries: const []));
    }
  }
}
