/// The skill catalogue's own state (issue #89): the shared reference data
/// that every Employee's held skills and every Site's coverage report are
/// built from (`skills.js`'s own header) — and, on this Screen, an
/// administrator's own write surface over it (`POST`/`PATCH /api/people/
/// skills`, skill-routes.js), following the exact shape `JobRolesBloc`
/// already draws for its own catalogue (issue #88).
///
/// Also drives the "who holds this skill" query (AC5): opened as a dialog
/// over this same Screen (`SkillQualifiedEmployeesDialog`), not as a Bloc of
/// its own — the same "the dialog dispatches into the Screen's own Bloc"
/// shape `EmployeeAssignmentDialog` uses against `EmployeeDetailBloc`, since
/// the query is a question asked *about* one catalogue row, not a Screen of
/// its own (`orgUnitId` is required by the route, so there is nothing this
/// query could answer on its own address — see the dialog's own header).
///
/// Route-scoped, like `JobRolesBloc`: one Screen's own reading of the
/// server, re-read on arrival rather than restored stale.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'skill.dart';

sealed class SkillsEvent {
  const SkillsEvent();
}

/// Load the whole catalogue, active and deactivated rows alike. Also the
/// retry a failed load offers.
class SkillsStarted extends SkillsEvent {
  const SkillsStarted();
}

/// The add form has decided: a whole new skill (issue #89). Same contract as
/// `JobRolesAddConfirmed` — the dialog decides, the Bloc only ever sees a
/// decision already made.
class SkillsAddConfirmed extends SkillsEvent {
  const SkillsAddConfirmed({
    required this.code,
    required this.name,
    required this.skillCategory,
    required this.requiresCertification,
    this.revalidationMonths,
  });

  final String code;
  final String name;
  final String skillCategory;
  final bool requiresCertification;
  final int? revalidationMonths;
}

/// The correction form has decided: only the keys present are the ones that
/// actually changed — same contract `JobRolesCorrectionConfirmed` carries.
/// `isActive` rides in [changes] too: deactivating or reactivating a skill is
/// a correction, not a dedicated verb (skills.js's own header — there is no
/// delete, and no second action here for it).
class SkillsCorrectionConfirmed extends SkillsEvent {
  const SkillsCorrectionConfirmed({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

/// Asks who holds [skillId], scoped to [orgUnitId] (required by the route
/// itself — skill-routes.js's own header) and filtered to at least
/// [minimumLevel] (1–4; null defers to the server's own default of 1).
class SkillsQualifiedEmployeesRequested extends SkillsEvent {
  const SkillsQualifiedEmployeesRequested({
    required this.skillId,
    required this.orgUnitId,
    this.minimumLevel,
  });

  final String skillId;
  final String orgUnitId;
  final int? minimumLevel;
}

/// Closes the qualified-employees query — leaving [SkillsLoaded.query] set
/// after the dialog it drove has been dismissed would otherwise show stale
/// results the next time it is opened for a different skill.
class SkillsQualifiedEmployeesCleared extends SkillsEvent {
  const SkillsQualifiedEmployeesCleared();
}

sealed class SkillsState {
  const SkillsState();
}

class SkillsLoading extends SkillsState {
  const SkillsLoading();
}

enum QualifiedEmployeesStatus { loading, ready, failed }

/// The qualified-employees query currently open on this Screen, if any — one
/// at a time, the same "this Screen has one mutation/query at a time" rule
/// [SkillsLoaded.isMutating] already keeps for a write.
class QualifiedEmployeesQuery {
  const QualifiedEmployeesQuery({
    required this.skillId,
    required this.status,
    this.employees = const [],
    this.failure,
  });

  final String skillId;
  final QualifiedEmployeesStatus status;
  final List<QualifiedEmployee> employees;
  final String? failure;
}

/// The catalogue as it last read. An empty [skills] is not a state of its
/// own — the same reasoning `JobRolesLoaded` gives its own empty list.
class SkillsLoaded extends SkillsState {
  const SkillsLoaded({
    required this.skills,
    this.isMutating = false,
    this.mutationFailure,
    this.query,
  });

  final List<Skill> skills;

  /// An add or a correction is in flight — one flag, not two, the same
  /// reasoning `JobRolesLoaded.isMutating` gives its own catalogue.
  final bool isMutating;

  /// Why the last add or correction did not land. Reported by whichever
  /// dialog is open, which stays open so the caller can fix the field rather
  /// than retype the whole skill.
  final String? mutationFailure;

  /// The qualified-employees query currently open, or null when no such
  /// dialog is open.
  final QualifiedEmployeesQuery? query;

  SkillsLoaded copyWith({
    List<Skill>? skills,
    bool? isMutating,
    String? mutationFailure,
    QualifiedEmployeesQuery? query,
    bool clearQuery = false,
  }) =>
      SkillsLoaded(
        skills: skills ?? this.skills,
        isMutating: isMutating ?? this.isMutating,
        // Always overwritten, never carried forward — the same rule
        // `JobRolesLoaded.copyWith` gives `mutationFailure`.
        mutationFailure: mutationFailure,
        query: clearQuery ? null : (query ?? this.query),
      );
}

class SkillsUnavailable extends SkillsState {
  const SkillsUnavailable({required this.message});

  final String message;
}

class SkillsBloc extends Bloc<SkillsEvent, SkillsState> {
  SkillsBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const SkillsLoading()) {
    on<SkillsStarted>(_onStarted);
    on<SkillsAddConfirmed>(_onAddConfirmed);
    on<SkillsCorrectionConfirmed>(_onCorrectionConfirmed);
    on<SkillsQualifiedEmployeesRequested>(_onQualifiedEmployeesRequested);
    on<SkillsQualifiedEmployeesCleared>(_onQualifiedEmployeesCleared);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(SkillsStarted event, Emitter<SkillsState> emit) async {
    emit(const SkillsLoading());
    await _readList(emit);
  }

  // Deactivated rows included (`includeInactive: true`): unlike every other
  // reader of this catalogue, this Screen's whole purpose is reaching a
  // retired row to reactivate it — the same reasoning `JobRolesBloc._readList`
  // already gives.
  Future<void> _readList(Emitter<SkillsState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SkillsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final skills = await _api.fetchSkills(token, includeInactive: true);
      final settled = state;
      emit(
        settled is SkillsLoaded
            ? settled.copyWith(skills: skills, isMutating: false)
            : SkillsLoaded(skills: skills),
      );
    } on PeopleApiException catch (error) {
      emit(SkillsUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(SkillsAddConfirmed event, Emitter<SkillsState> emit) async {
    final current = state;
    if (current is! SkillsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.createSkill(
        token,
        code: event.code,
        name: event.name,
        skillCategory: event.skillCategory,
        requiresCertification: event.requiresCertification,
        revalidationMonths: event.revalidationMonths,
      );
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! SkillsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onCorrectionConfirmed(
    SkillsCorrectionConfirmed event,
    Emitter<SkillsState> emit,
  ) async {
    final current = state;
    if (current is! SkillsLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await _api.updateSkill(token, event.id, event.changes);
      await _readList(emit);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! SkillsLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onQualifiedEmployeesRequested(
    SkillsQualifiedEmployeesRequested event,
    Emitter<SkillsState> emit,
  ) async {
    final current = state;
    if (current is! SkillsLoaded) return;

    emit(
      current.copyWith(
        query: QualifiedEmployeesQuery(skillId: event.skillId, status: QualifiedEmployeesStatus.loading),
      ),
    );

    final token = _auth.currentAccessToken;
    if (token == null) {
      final settled = state;
      if (settled is! SkillsLoaded) return;
      emit(
        settled.copyWith(
          query: QualifiedEmployeesQuery(
            skillId: event.skillId,
            status: QualifiedEmployeesStatus.failed,
            failure: signedOutMessage,
          ),
        ),
      );
      return;
    }

    try {
      final employees = await _api.fetchQualifiedEmployees(
        token,
        event.skillId,
        orgUnitId: event.orgUnitId,
        minimumLevel: event.minimumLevel,
      );
      final settled = state;
      if (settled is! SkillsLoaded) return;
      emit(
        settled.copyWith(
          query: QualifiedEmployeesQuery(
            skillId: event.skillId,
            status: QualifiedEmployeesStatus.ready,
            employees: employees,
          ),
        ),
      );
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! SkillsLoaded) return;
      emit(
        settled.copyWith(
          query: QualifiedEmployeesQuery(
            skillId: event.skillId,
            status: QualifiedEmployeesStatus.failed,
            failure: error.message,
          ),
        ),
      );
    }
  }

  void _onQualifiedEmployeesCleared(
    SkillsQualifiedEmployeesCleared event,
    Emitter<SkillsState> emit,
  ) {
    final current = state;
    if (current is! SkillsLoaded) return;
    emit(current.copyWith(clearQuery: true));
  }
}
