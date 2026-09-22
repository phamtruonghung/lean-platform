/// The attendance sheet's own state machine (issue #249) — opens (and
/// pre-fills) the sheet for one shift instance, marks exceptions, adds
/// stand-ins, removes rows, and confirms. Mirrors `EmployeeDetailBloc`'s own
/// shape: one record loaded at a time, a single `isMutating` flag rather
/// than one per row action, and every write re-read afterwards rather than
/// trusted from its own response.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'attendance.dart';

sealed class AttendanceSheetEvent {
  const AttendanceSheetEvent();
}

/// Load (and pre-fill, the first time) the sheet — the Screen's first build,
/// and the retry a failed load offers.
class AttendanceSheetRequested extends AttendanceSheetEvent {
  const AttendanceSheetRequested(this.shiftInstanceId);
  final String shiftInstanceId;
}

/// Marks an exception, changes worked/overtime minutes, or corrects a row
/// already confirmed (ADR-0040: a confirmed sheet can still be corrected).
/// [changes] carries only the keys the caller actually decided to change —
/// the same `hasOwnProperty` contract [PeopleApi.updateAttendanceRecord]
/// documents.
class AttendanceRecordCorrected extends AttendanceSheetEvent {
  const AttendanceRecordCorrected({required this.recordId, required this.changes});
  final String recordId;
  final Map<String, Object?> changes;
}

/// Adds a stand-in drawn from the Directory (ADR-0040).
class AttendanceStandInAdded extends AttendanceSheetEvent {
  const AttendanceStandInAdded({required this.employeeId});
  final String employeeId;
}

/// Removes a row — someone who was never actually rostered (ADR-0040).
class AttendanceRecordRemoved extends AttendanceSheetEvent {
  const AttendanceRecordRemoved({required this.recordId});
  final String recordId;
}

/// Confirms the sheet.
class AttendanceSheetConfirmed extends AttendanceSheetEvent {
  const AttendanceSheetConfirmed();
}

sealed class AttendanceSheetState {
  const AttendanceSheetState();
}

class AttendanceSheetLoading extends AttendanceSheetState {
  const AttendanceSheetLoading();
}

class AttendanceSheetUnavailable extends AttendanceSheetState {
  const AttendanceSheetUnavailable({required this.message});
  final String message;
}

class AttendanceSheetLoaded extends AttendanceSheetState {
  const AttendanceSheetLoaded({
    required this.shiftInstanceId,
    required this.started,
    required this.sheet,
    required this.records,
    this.absenceReasons = const [],
    this.isMutating = false,
    this.mutationFailure,
  });

  /// The shift instance this sheet belongs to — carried independently of
  /// [sheet], which is null exactly when [started] is false, so a write
  /// dispatch always has an id to act against even before anything exists.
  final String shiftInstanceId;

  /// False only when this caller lacks the edit Grant that would have
  /// started the sheet, and no sheet exists yet (`PeopleApi.fetchAttendanceSheet`'s
  /// own header) — [sheet] is null and [records] is empty in that state, and
  /// the Screen renders a read-only "not started yet" placeholder with no
  /// write affordances, regardless of [AttendanceSheetScreen.canRecord]'s
  /// own coarse "can write somewhere" signal: a caller this specific shift's
  /// Org Unit refused has nothing to start here either way.
  final bool started;

  final AttendanceSheet? sheet;
  final List<AttendanceRecord> records;

  /// Read once alongside the sheet, the same "read once, tolerate its own
  /// failure" shape `EmployeeDetailLoaded.jobRoles` already uses — a failure
  /// to read the catalogue leaves the reason dropdown short, not the whole
  /// Screen unavailable.
  final List<AbsenceReason> absenceReasons;

  /// A correction, a stand-in, a removal or a confirm is in flight — one
  /// flag, not one per row, the same reasoning `EmployeeDetailLoaded.isMutating`
  /// gives.
  final bool isMutating;

  /// Why the last write did not land, shown inline by whichever row or
  /// dialog is open.
  final String? mutationFailure;

  AttendanceSheetLoaded copyWith({
    String? shiftInstanceId,
    bool? started,
    AttendanceSheet? sheet,
    List<AttendanceRecord>? records,
    List<AbsenceReason>? absenceReasons,
    bool? isMutating,
    String? mutationFailure,
  }) =>
      AttendanceSheetLoaded(
        shiftInstanceId: shiftInstanceId ?? this.shiftInstanceId,
        started: started ?? this.started,
        sheet: sheet ?? this.sheet,
        records: records ?? this.records,
        absenceReasons: absenceReasons ?? this.absenceReasons,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `EmployeeDetailLoaded.copyWith` gives `mutationFailure`.
        mutationFailure: mutationFailure,
      );
}

class AttendanceSheetBloc extends Bloc<AttendanceSheetEvent, AttendanceSheetState> {
  AttendanceSheetBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const AttendanceSheetLoading()) {
    on<AttendanceSheetRequested>(_onRequested);
    on<AttendanceRecordCorrected>(_onRecordCorrected);
    on<AttendanceStandInAdded>(_onStandInAdded);
    on<AttendanceRecordRemoved>(_onRecordRemoved);
    on<AttendanceSheetConfirmed>(_onConfirmed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  /// The shift instance this Screen was last asked to show — remembered so a
  /// write's own re-read (`_reload`) asks for the same sheet.
  String? _shiftInstanceId;

  Future<void> _onRequested(
    AttendanceSheetRequested event,
    Emitter<AttendanceSheetState> emit,
  ) async {
    emit(const AttendanceSheetLoading());
    _shiftInstanceId = event.shiftInstanceId;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AttendanceSheetUnavailable(message: signedOutMessage));
      return;
    }
    // The reason catalogue, for the exception dialog's own dropdown — read
    // once, its own failure tolerated, the same shape
    // `EmployeeDetailBloc._onRequested` already uses for its two catalogues.
    List<AbsenceReason> absenceReasons = const [];
    try {
      absenceReasons = await _api.fetchAbsenceReasons(token);
    } on PeopleApiException {
      absenceReasons = const [];
    }
    try {
      final page = await _api.fetchAttendanceSheet(token, event.shiftInstanceId);
      emit(
        AttendanceSheetLoaded(
          shiftInstanceId: event.shiftInstanceId,
          started: page.started,
          sheet: page.sheet,
          records: page.records,
          absenceReasons: absenceReasons,
        ),
      );
    } on PeopleApiException catch (error) {
      emit(AttendanceSheetUnavailable(message: error.message));
    }
  }

  /// Re-reads the sheet in place after a successful write — the response to
  /// a single-row PATCH/POST is one row, never the whole sheet, so this is
  /// what keeps every other row (and the sheet's own confirmation) in view.
  Future<void> _reload(Emitter<AttendanceSheetState> emit) async {
    final shiftInstanceId = _shiftInstanceId;
    final token = _auth.currentAccessToken;
    if (shiftInstanceId == null || token == null) {
      emit(const AttendanceSheetUnavailable(message: signedOutMessage));
      return;
    }
    final settledBefore = state;
    final absenceReasons =
        settledBefore is AttendanceSheetLoaded ? settledBefore.absenceReasons : const <AbsenceReason>[];
    try {
      final page = await _api.fetchAttendanceSheet(token, shiftInstanceId);
      emit(
        AttendanceSheetLoaded(
          shiftInstanceId: shiftInstanceId,
          started: page.started,
          sheet: page.sheet,
          records: page.records,
          absenceReasons: absenceReasons,
        ),
      );
    } on PeopleApiException catch (error) {
      emit(AttendanceSheetUnavailable(message: error.message));
    }
  }

  Future<void> _onRecordCorrected(
    AttendanceRecordCorrected event,
    Emitter<AttendanceSheetState> emit,
  ) async {
    final current = state;
    if (current is! AttendanceSheetLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateAttendanceRecord(token, current.shiftInstanceId, event.recordId, event.changes);
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! AttendanceSheetLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onStandInAdded(
    AttendanceStandInAdded event,
    Emitter<AttendanceSheetState> emit,
  ) async {
    final current = state;
    if (current is! AttendanceSheetLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.addAttendanceStandIn(
        token,
        current.shiftInstanceId,
        employeeId: event.employeeId,
      );
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! AttendanceSheetLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onRecordRemoved(
    AttendanceRecordRemoved event,
    Emitter<AttendanceSheetState> emit,
  ) async {
    final current = state;
    if (current is! AttendanceSheetLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.removeAttendanceRecord(token, current.shiftInstanceId, event.recordId);
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! AttendanceSheetLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onConfirmed(
    AttendanceSheetConfirmed event,
    Emitter<AttendanceSheetState> emit,
  ) async {
    final current = state;
    if (current is! AttendanceSheetLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.confirmAttendanceSheet(token, current.shiftInstanceId);
      await _reload(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! AttendanceSheetLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
