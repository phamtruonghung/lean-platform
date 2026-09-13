/// Every write issue #90's own Screen needs against the plant's shape:
/// creating a Site, adding an Org Unit beneath a parent (or starting a new
/// root branch), retiring or reinstating one, and importing a branch in
/// bulk. Searching a Site's tree by name (`GET .../org-units/search`) moved
/// out to `OrgUnitsScreen`'s own `AppSearchField` (issue #130) — a dumb
/// per-term fetch called directly against `PeopleApi`, the same shape
/// `SiteFormDialog`'s own `AppSearchField` field already uses for its
/// filtered-in-memory timezone list — so this Bloc no longer holds any
/// search state of its own.
///
/// Deliberately does NOT own the tree itself — that stays `OrgUnitPickerBloc`'s
/// job exactly as its own header describes it ("a Site, a partly-expanded
/// tree, a Granted set"). This Bloc knows nothing about Sites loaded, nodes
/// expanded, or which rows exist; `OrgUnitsScreen` drives both Blocs side by
/// side, the same "the Bloc is shared, the view is not" shape
/// `employee_assignment_dialog.dart`'s own header already settles for a
/// tree-picking dialog. What is new here, and does not fit
/// `OrgUnitPickerBloc`'s own stated job, is that this Screen's writes mutate
/// the very tree being browsed — so a successful write is reported through
/// [OrgUnitAdminState.effect], a one-shot value `OrgUnitsScreen`'s own
/// listener consumes by dispatching the matching `OrgUnitPickerRefreshed` (or
/// `OrgUnitPickerSiteSelected`/`OrgUnitPickerStarted`) event at
/// `OrgUnitPickerBloc`, then clears with [OrgUnitAdminEffectConsumed] so it is
/// never replayed on an unrelated rebuild.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';

sealed class OrgUnitAdminEvent {
  const OrgUnitAdminEvent();
}

/// The add-Site form has decided (`POST /api/people/sites`, administrator
/// only). Same contract every catalogue's own add event carries
/// (`JobRolesAddConfirmed`, `SkillsAddConfirmed`): the dialog decides, this
/// Bloc only ever sees a decision already made.
class OrgUnitAdminSiteCreated extends OrgUnitAdminEvent {
  const OrgUnitAdminSiteCreated({
    required this.code,
    required this.name,
    required this.timezone,
    this.countryCode,
  });

  final String code;
  final String name;
  final String timezone;
  final String? countryCode;
}

/// The edit-Site form has decided (`PATCH /api/people/sites/:siteId`, issue
/// #137, ADR-0025) — the labels always, the timezone only while the Site has
/// no shift calendar. Distinct from [OrgUnitAdminSiteCreated] in the route and
/// the presence of [siteId]; the failure path is identical, so the server's own
/// refusal (a 409 for a locked timezone, a 400 for an unknown zone) lands in
/// the same `mutationFailure` the dialog already renders.
class OrgUnitAdminSiteUpdated extends OrgUnitAdminEvent {
  const OrgUnitAdminSiteUpdated({
    required this.siteId,
    required this.code,
    required this.name,
    required this.timezone,
    this.countryCode,
  });

  final String siteId;
  final String code;
  final String name;
  final String timezone;
  final String? countryCode;
}

/// The add-Org-Unit form has decided (`POST /sites/:siteId/org-units`).
/// [parentId] null means a new root branch — offered to an administrator
/// only (ADR-0008), enforced by `OrgUnitsScreen` not even showing the control
/// to anyone else, with the server's own 403 as the real gate regardless.
class OrgUnitAdminOrgUnitCreated extends OrgUnitAdminEvent {
  const OrgUnitAdminOrgUnitCreated({
    required this.siteId,
    this.parentId,
    required this.code,
    required this.name,
    required this.unitType,
    this.sortOrder,
  });

  final String siteId;
  final String? parentId;
  final String code;
  final String name;
  final String unitType;
  final int? sortOrder;
}

/// Retires, or reinstates, one Org Unit (`PATCH /api/people/org-units/:id`).
/// [refreshParentId] is the tree level to re-read once this lands — null for
/// the root level, matching `OrgUnitPickerRefreshed.parentId` exactly. Given
/// by the caller rather than looked up here: this Bloc holds no tree to look
/// an Org Unit's own parent up in (see this file's own header).
class OrgUnitAdminActiveSet extends OrgUnitAdminEvent {
  const OrgUnitAdminActiveSet({
    required this.orgUnitId,
    required this.isActive,
    required this.refreshParentId,
  });

  final String orgUnitId;
  final bool isActive;
  final String? refreshParentId;
}

/// Fetches the timezone list a Site's `timezone` is chosen from (`GET
/// /timezones`, issue #123/#127, ADR-0023) — dispatched once by
/// `SiteFormDialog` when it opens, and again by its own retry after a failed
/// fetch. The whole ~1,200-row list is fetched here and filtered in memory
/// from there; there is deliberately no per-keystroke event, unlike
/// `OrgUnitAdminSearchRequested` beside it.
class OrgUnitAdminTimezonesRequested extends OrgUnitAdminEvent {
  const OrgUnitAdminTimezonesRequested();
}

/// Submits a whole branch in one call (`POST .../org-units/import`,
/// ADR-0011). [orgUnits] is already the raw row set the dialog built —
/// `{code, name, unitType, parentCode, sortOrder}` per row, rows naming their
/// own parent by `code` rather than an id most of them do not have yet.
class OrgUnitAdminImportRequested extends OrgUnitAdminEvent {
  const OrgUnitAdminImportRequested({required this.siteId, required this.orgUnits});

  final String siteId;
  final List<Map<String, Object?>> orgUnits;
}

/// Consumes [OrgUnitAdminState.effect] after `OrgUnitsScreen`'s listener has
/// acted on it.
class OrgUnitAdminEffectConsumed extends OrgUnitAdminEvent {
  const OrgUnitAdminEffectConsumed();
}

/// What changed in the tree after a write landed, and therefore what part of
/// `OrgUnitPickerBloc`'s own cached state is now stale. One-shot: read once
/// by `OrgUnitsScreen`'s listener, then cleared via
/// [OrgUnitAdminEffectConsumed] — never re-read by a later, unrelated
/// rebuild.
sealed class OrgUnitAdminEffect {
  const OrgUnitAdminEffect();
}

/// A Site was created — nothing about the tree changed, only the Sites list
/// `OrgUnitPickerBloc.sites` holds, so the listener re-dispatches
/// `OrgUnitPickerStarted`, the same event that loads it the first time.
class OrgUnitAdminSitesChanged extends OrgUnitAdminEffect {
  const OrgUnitAdminSitesChanged();
}

/// One level of the tree changed — an Org Unit was added beneath [parentId],
/// or one sitting at [parentId]'s level was retired or reinstated. Null means
/// the root level.
class OrgUnitAdminLevelChanged extends OrgUnitAdminEffect {
  const OrgUnitAdminLevelChanged(this.parentId);

  final String? parentId;
}

/// A whole branch was imported — rather than guess which levels the payload
/// touched, the listener re-selects [siteId], the same "collapse and re-read
/// this Site from the top" `OrgUnitPickerSiteSelected` already means.
class OrgUnitAdminTreeReplaced extends OrgUnitAdminEffect {
  const OrgUnitAdminTreeReplaced(this.siteId);

  final String siteId;
}

/// What `SiteFormDialog`'s own timezone field is showing (issue #127,
/// ADR-0023) — `failed` is the one status that blocks submission outright:
/// the control shows `PlatformFailureState` in place of the search field
/// itself rather than falling back to free text.
enum OrgUnitAdminTimezoneStatus { idle, loading, ready, failed }

/// One state class, not a sealed family — the same reasoning
/// `OrgUnitPickerState`'s own header gives: a write in flight, a search in
/// flight and an import in flight are independent concerns, and a caller
/// mid-search with an earlier write failure still on screen is an ordinary
/// situation, not a state of its own.
class OrgUnitAdminState {
  const OrgUnitAdminState({
    this.isMutating = false,
    this.mutationFailure,
    this.effect,
    this.isImporting = false,
    this.importErrors = const [],
    this.importFailure,
    this.timezoneStatus = OrgUnitAdminTimezoneStatus.idle,
    this.timezones = const [],
    this.timezoneFailure,
  });

  /// Creating a Site, creating an Org Unit, or retiring/reinstating one — one
  /// flag, not three, the same "this Screen has one mutation at a time" rule
  /// `JobRolesLoaded.isMutating` already keeps for its own catalogue.
  final bool isMutating;
  final String? mutationFailure;

  /// What the last successful mutation changed, waiting to be acted on. See
  /// this file's own header.
  final OrgUnitAdminEffect? effect;

  final bool isImporting;

  /// One entry per offending row, from the import's own `422`
  /// (`OrgUnitImportException.errors`) — empty whenever [importFailure] is a
  /// plain refusal (a malformed envelope, a scope 403) rather than a
  /// row-shaped validation failure.
  final List<OrgUnitImportRowError> importErrors;
  final String? importFailure;

  /// `SiteFormDialog`'s own timezone list (issue #127) — fetched once per
  /// dialog open, then filtered in memory; see `OrgUnitAdminTimezonesRequested`.
  final OrgUnitAdminTimezoneStatus timezoneStatus;
  final List<String> timezones;
  final String? timezoneFailure;

  OrgUnitAdminState copyWith({
    bool? isMutating,
    String? mutationFailure,
    bool clearMutationFailure = false,
    OrgUnitAdminEffect? effect,
    bool clearEffect = false,
    bool? isImporting,
    List<OrgUnitImportRowError>? importErrors,
    String? importFailure,
    bool clearImportFailure = false,
    OrgUnitAdminTimezoneStatus? timezoneStatus,
    List<String>? timezones,
    String? timezoneFailure,
    bool clearTimezoneFailure = false,
  }) {
    return OrgUnitAdminState(
      isMutating: isMutating ?? this.isMutating,
      mutationFailure: clearMutationFailure ? null : (mutationFailure ?? this.mutationFailure),
      effect: clearEffect ? null : (effect ?? this.effect),
      isImporting: isImporting ?? this.isImporting,
      importErrors: importErrors ?? this.importErrors,
      importFailure: clearImportFailure ? null : (importFailure ?? this.importFailure),
      timezoneStatus: timezoneStatus ?? this.timezoneStatus,
      timezones: timezones ?? this.timezones,
      timezoneFailure: clearTimezoneFailure ? null : (timezoneFailure ?? this.timezoneFailure),
    );
  }
}

class OrgUnitAdminBloc extends Bloc<OrgUnitAdminEvent, OrgUnitAdminState> {
  OrgUnitAdminBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const OrgUnitAdminState()) {
    on<OrgUnitAdminSiteCreated>(_onSiteCreated);
    on<OrgUnitAdminSiteUpdated>(_onSiteUpdated);
    on<OrgUnitAdminOrgUnitCreated>(_onOrgUnitCreated);
    on<OrgUnitAdminActiveSet>(_onActiveSet);
    on<OrgUnitAdminImportRequested>(_onImportRequested);
    on<OrgUnitAdminEffectConsumed>(_onEffectConsumed);
    on<OrgUnitAdminTimezonesRequested>(_onTimezonesRequested);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onSiteCreated(OrgUnitAdminSiteCreated event, Emitter<OrgUnitAdminState> emit) async {
    if (state.isMutating) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(mutationFailure: signedOutMessage));
      return;
    }
    emit(state.copyWith(isMutating: true, clearMutationFailure: true));
    try {
      await _api.createSite(
        token,
        code: event.code,
        name: event.name,
        timezone: event.timezone,
        countryCode: event.countryCode,
      );
      emit(state.copyWith(isMutating: false, effect: const OrgUnitAdminSitesChanged()));
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onSiteUpdated(OrgUnitAdminSiteUpdated event, Emitter<OrgUnitAdminState> emit) async {
    if (state.isMutating) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(mutationFailure: signedOutMessage));
      return;
    }
    emit(state.copyWith(isMutating: true, clearMutationFailure: true));
    try {
      await _api.updateSite(
        token,
        event.siteId,
        code: event.code,
        name: event.name,
        timezone: event.timezone,
        countryCode: event.countryCode,
      );
      emit(state.copyWith(isMutating: false, effect: const OrgUnitAdminSitesChanged()));
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onOrgUnitCreated(
    OrgUnitAdminOrgUnitCreated event,
    Emitter<OrgUnitAdminState> emit,
  ) async {
    if (state.isMutating) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(mutationFailure: signedOutMessage));
      return;
    }
    emit(state.copyWith(isMutating: true, clearMutationFailure: true));
    try {
      await _api.createOrgUnit(
        token,
        siteId: event.siteId,
        parentId: event.parentId,
        code: event.code,
        name: event.name,
        unitType: event.unitType,
        sortOrder: event.sortOrder,
      );
      emit(
        state.copyWith(
          isMutating: false,
          effect: OrgUnitAdminLevelChanged(event.parentId),
        ),
      );
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onActiveSet(OrgUnitAdminActiveSet event, Emitter<OrgUnitAdminState> emit) async {
    if (state.isMutating) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(mutationFailure: signedOutMessage));
      return;
    }
    emit(state.copyWith(isMutating: true, clearMutationFailure: true));
    try {
      await _api.setOrgUnitActive(token, event.orgUnitId, isActive: event.isActive);
      emit(
        state.copyWith(
          isMutating: false,
          effect: OrgUnitAdminLevelChanged(event.refreshParentId),
        ),
      );
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }

  Future<void> _onImportRequested(
    OrgUnitAdminImportRequested event,
    Emitter<OrgUnitAdminState> emit,
  ) async {
    if (state.isImporting) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(importFailure: signedOutMessage));
      return;
    }
    emit(
      state.copyWith(
        isImporting: true,
        clearImportFailure: true,
        importErrors: const [],
      ),
    );
    try {
      await _api.importOrgUnits(token, siteId: event.siteId, orgUnits: event.orgUnits);
      emit(
        state.copyWith(
          isImporting: false,
          effect: OrgUnitAdminTreeReplaced(event.siteId),
        ),
      );
    } on OrgUnitImportException catch (error) {
      emit(
        state.copyWith(
          isImporting: false,
          importErrors: error.errors,
          importFailure: error.message,
        ),
      );
    } on PeopleApiException catch (error) {
      emit(state.copyWith(isImporting: false, importFailure: error.message));
    }
  }

  void _onEffectConsumed(OrgUnitAdminEffectConsumed event, Emitter<OrgUnitAdminState> emit) {
    emit(state.copyWith(clearEffect: true));
  }

  Future<void> _onTimezonesRequested(
    OrgUnitAdminTimezonesRequested event,
    Emitter<OrgUnitAdminState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(
        state.copyWith(
          timezoneStatus: OrgUnitAdminTimezoneStatus.failed,
          timezoneFailure: signedOutMessage,
        ),
      );
      return;
    }
    emit(state.copyWith(timezoneStatus: OrgUnitAdminTimezoneStatus.loading, clearTimezoneFailure: true));
    try {
      final timezones = await _api.fetchTimezones(token);
      emit(
        state.copyWith(timezoneStatus: OrgUnitAdminTimezoneStatus.ready, timezones: timezones),
      );
    } on PeopleApiException catch (error) {
      emit(
        state.copyWith(
          timezoneStatus: OrgUnitAdminTimezoneStatus.failed,
          timezoneFailure: error.message,
        ),
      );
    }
  }
}
