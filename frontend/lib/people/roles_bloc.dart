/// The roles editor's own state (issue #492, ADR-0061): the permission
/// catalogue every role draws from, and the roles themselves — the groups an
/// administrator edits and assigns.
///
/// Route-scoped, like `JobRolesBloc`: one Screen's own reading of the server,
/// re-read on arrival rather than restored stale. Both reads happen together
/// on start, because the editor cannot draw a single row without the catalogue
/// to name each permission by.
///
/// The Server is the only authority on what a role carries: every mutation
/// re-reads rather than patching the local list, so a code this image does not
/// know (dropped by the backend's `knownPermissionCodes`) never appears as
/// granted in the UI.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'app_role.dart';
import '../l10n/notices.dart';

sealed class RolesEvent {
  const RolesEvent();
}

/// Load the catalogue and every role, retired ones included. Also the retry a
/// failed load offers, and the re-read every mutation ends with.
class RolesStarted extends RolesEvent {
  const RolesStarted();
}

/// The add form has decided: a whole new role.
class RoleCreated extends RolesEvent {
  const RoleCreated({
    required this.code,
    required this.name,
    required this.description,
    this.permissions = const [],
  });

  final String code;
  final String name;
  final String description;
  final List<String> permissions;
}

/// The correction form has decided. Only the keys that actually changed are
/// carried — `updateRole`'s (roles.js) own `hasOwnProperty` contract on the
/// other end.
class RoleCorrected extends RolesEvent {
  const RoleCorrected({required this.id, required this.changes});

  final String id;
  final Map<String, Object?> changes;
}

/// The permission editor has decided: the complete set this role should carry,
/// not a patch of additions. The server replaces the set in one transaction.
class RolePermissionsSaved extends RolesEvent {
  const RolePermissionsSaved({required this.id, required this.permissions});

  final String id;
  final List<String> permissions;
}

sealed class RolesState {
  const RolesState();
}

class RolesLoading extends RolesState {
  const RolesLoading();
}

/// The catalogue and the roles as they last read. An empty [roles] is not a
/// state of its own — the seed guarantees at least the default group, so an
/// empty list means something is wrong with the deployment, not with the plant.
class RolesLoaded extends RolesState {
  const RolesLoaded({
    required this.roles,
    required this.permissions,
    this.isMutating = false,
    this.mutationFailure,
    this.notice,
  });

  final List<AppRole> roles;
  final List<Permission> permissions;

  /// A create, a correction or a permission save is in flight — one flag, not
  /// three: this Screen has one mutation at a time.
  final bool isMutating;

  /// Why the last mutation did not land. Reported by whichever dialog is open,
  /// which stays open so the caller can fix the field rather than start over.
  final String? mutationFailure;

  /// What the last mutation did, for the Screen's own notice line — carried
  /// through the re-read that follows it.
  final String? notice;

  /// The catalogue grouped by Module, in the server's own order: the editor
  /// draws one section per Module. `LinkedHashMap` order (Dart's `Map`
  /// literal) is the catalogue's order, because the server sends it sorted by
  /// `sort_order`.
  Map<String, List<Permission>> get permissionsByModule {
    final grouped = <String, List<Permission>>{};
    for (final permission in permissions) {
      grouped.putIfAbsent(permission.module, () => []).add(permission);
    }
    return grouped;
  }

  RolesLoaded copyWith({
    List<AppRole>? roles,
    List<Permission>? permissions,
    bool? isMutating,
    String? mutationFailure,
    String? notice,
  }) =>
      RolesLoaded(
        roles: roles ?? this.roles,
        permissions: permissions ?? this.permissions,
        isMutating: isMutating ?? this.isMutating,
        // Both always overwritten, never carried forward — the same rule
        // `JobRolesLoaded.copyWith` gives its own failure line.
        mutationFailure: mutationFailure,
        notice: notice,
      );
}

class RolesUnavailable extends RolesState {
  const RolesUnavailable({required this.message});

  final String message;
}

class RolesBloc extends Bloc<RolesEvent, RolesState> {
  RolesBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const RolesLoading()) {
    on<RolesStarted>(_onStarted);
    on<RoleCreated>(_onRoleCreated);
    on<RoleCorrected>(_onRoleCorrected);
    on<RolePermissionsSaved>(_onRolePermissionsSaved);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  Future<void> _onStarted(RolesStarted event, Emitter<RolesState> emit) async {
    emit(const RolesLoading());
    await _read(emit);
  }

  Future<void> _read(Emitter<RolesState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const RolesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final results = await Future.wait([
        _api.fetchRoles(token),
        _api.fetchPermissions(token),
      ]);
      emit(RolesLoaded(
        roles: results[0] as List<AppRole>,
        permissions: results[1] as List<Permission>,
        notice: notice,
      ));
    } on PeopleApiException catch (error) {
      emit(RolesUnavailable(message: error.message));
    }
  }

  /// The shared shape of the three mutations: refuse while one is in flight,
  /// mark the Screen busy, act, then re-read — reporting the server's own
  /// sentence on the way back rather than inventing one.
  Future<void> _mutate(
    Emitter<RolesState> emit,
    Future<void> Function(String token) act,
    String notice,
  ) async {
    final current = state;
    if (current is! RolesLoaded || current.isMutating) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true, mutationFailure: null));
    try {
      await act(token);
      await _read(emit, notice: notice);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! RolesLoaded) return;
      emit(settled.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onRoleCreated(RoleCreated event, Emitter<RolesState> emit) => _mutate(
        emit,
        (token) => _api.createRole(
          token,
          code: event.code,
          name: event.name,
          description: event.description,
          permissions: event.permissions,
        ).then((_) {}),
        '${event.code.trim().toUpperCase()} created.',
      );

  Future<void> _onRoleCorrected(RoleCorrected event, Emitter<RolesState> emit) => _mutate(
        emit,
        (token) => _api.updateRole(token, event.id, event.changes).then((_) {}),
        'Role saved.',
      );

  Future<void> _onRolePermissionsSaved(RolePermissionsSaved event, Emitter<RolesState> emit) => _mutate(
        emit,
        (token) => _api.setRolePermissions(token, event.id, event.permissions).then((_) {}),
        'What the role carries is saved.',
      );
}
