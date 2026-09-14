/// The Asset register's state: which Site is being looked at, what is in it,
/// and an Asset being added.
///
/// Route-scoped, like `AccountsBloc` and unlike `AccountBloc`: one Screen's
/// reading of the server, re-read on arrival rather than restored stale.
///
/// It holds two APIs on purpose. The register itself is Maintenance's
/// (`MaintenanceApi`); the list of Sites to choose between is People's, and
/// there is no Maintenance endpoint that answers it — ADR-0006's rule is that
/// a Module asks the owning Module rather than growing its own copy of Sites.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'asset.dart';
import 'maintenance_api.dart';

sealed class AssetsEvent {
  const AssetsEvent();
}

/// Load the Sites, then the Assets at the first of them. Also the retry a
/// failed load offers, so a retry re-does whichever half failed.
class AssetsStarted extends AssetsEvent {
  const AssetsStarted();
}

/// Look at a different Site's register.
class AssetsSiteSelected extends AssetsEvent {
  const AssetsSiteSelected(this.siteId);
  final String siteId;
}

/// The form has decided: this is a whole Asset, with the Org Unit already
/// chosen. Same contract as the Approval queue's admission event — the dialog
/// decides, the Bloc only ever sees a decision already made.
class AssetAddConfirmed extends AssetsEvent {
  const AssetAddConfirmed({
    required this.orgUnitId,
    required this.code,
    required this.name,
    required this.assetType,
    required this.criticality,
  });

  final String orgUnitId;
  final String code;
  final String name;
  final String assetType;
  final String criticality;
}

/// Toggle whether the register includes retired Assets. Re-reads with
/// `includeRetired` rather than filtering client-side, since a retired Asset
/// is not even sent unless asked for.
class AssetsShowRetiredChanged extends AssetsEvent {
  const AssetsShowRetiredChanged(this.showRetired);
  final bool showRetired;
}

/// Retire or reinstate one Asset (issue #61). Not a deletion — the row stays
/// on the register either way.
class AssetActiveToggled extends AssetsEvent {
  const AssetActiveToggled({required this.assetId, required this.isActive});
  final String assetId;
  final bool isActive;
}

/// Nest one Asset beneath another, or detach it back to top-level when
/// [parentId] is null.
class AssetParentChanged extends AssetsEvent {
  const AssetParentChanged({required this.assetId, required this.parentId});
  final String assetId;
  final String? parentId;
}

/// Change where one Asset sits (issue #171) — the Org Unit that decides who
/// may work on it. The server requires a write Grant reaching both the Org
/// Unit the Asset is leaving and the one it is going to, so a caller whose
/// reach does not cover both is refused (403) rather than half-served.
class AssetOrgUnitChanged extends AssetsEvent {
  const AssetOrgUnitChanged({required this.assetId, required this.orgUnitId});
  final String assetId;
  final String orgUnitId;
}

sealed class AssetsState {
  const AssetsState();
}

/// The first load, before even the Site list is known.
class AssetsLoading extends AssetsState {
  const AssetsLoading();
}

class AssetsLoaded extends AssetsState {
  const AssetsLoaded({
    required this.sites,
    required this.siteId,
    this.assets = const [],
    this.isLoadingAssets = false,
    this.isAdding = false,
    this.addFailure,
    this.showRetired = false,
    this.mutatingAssetId,
    this.notice,
  });

  final List<Site> sites;
  final String? siteId;
  final List<Asset> assets;

  /// A Site switch re-reads the register while the Site chooser stays on
  /// screen — the placeholders belong to the list, not to the whole Screen.
  final bool isLoadingAssets;

  /// An add is in flight. Kept on the state, not only in the dialog, so the
  /// Screen can refuse a second one.
  final bool isAdding;

  /// Why the last add did not land. Reported by the open dialog, which stays
  /// open so the caller can fix the code rather than retype the Asset.
  final String? addFailure;

  /// Whether the register was last (re-)read with `includeRetired` (issue
  /// #61). Kept alongside [siteId] for the same reason `_lastSiteId` is kept
  /// on the Bloc: a Site switch and a retry must both survive it rather than
  /// silently resetting to "active only".
  final bool showRetired;

  /// The Asset a retire/reinstate/nest/detach is in flight for, if any.
  /// Checked alongside [isAdding] — the register handles one mutation at a
  /// time, the same rule `AccountsBloc.busyId` enforces.
  final String? mutatingAssetId;

  /// What the last act had to say for itself. Never the failure of a load:
  /// that is [AssetsUnavailable].
  final String? notice;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  AssetsLoaded copyWith({
    List<Asset>? assets,
    String? siteId,
    bool? isLoadingAssets,
    bool? isAdding,
    String? addFailure,
    bool? showRetired,
    String? mutatingAssetId,
    bool clearMutatingAssetId = false,
    String? notice,
  }) =>
      AssetsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        assets: assets ?? this.assets,
        isLoadingAssets: isLoadingAssets ?? this.isLoadingAssets,
        isAdding: isAdding ?? this.isAdding,
        addFailure: addFailure,
        showRetired: showRetired ?? this.showRetired,
        mutatingAssetId: clearMutatingAssetId ? null : (mutatingAssetId ?? this.mutatingAssetId),
        notice: notice,
      );
}

class AssetsUnavailable extends AssetsState {
  const AssetsUnavailable({required this.message});
  final String message;
}

class AssetsBloc extends Bloc<AssetsEvent, AssetsState> {
  AssetsBloc({
    required MaintenanceApi maintenanceApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _maintenance = maintenanceApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const AssetsLoading()) {
    on<AssetsStarted>(_onStarted);
    on<AssetsSiteSelected>(_onSiteSelected);
    on<AssetAddConfirmed>(_onAddConfirmed);
    on<AssetsShowRetiredChanged>(_onShowRetiredChanged);
    on<AssetActiveToggled>(_onActiveToggled);
    on<AssetParentChanged>(_onParentChanged);
    on<AssetOrgUnitChanged>(_onOrgUnitChanged);
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage =
      'There are no Sites you can see, so there is no register to show.';

  /// What a second row action reports, rather than dropping silently, when
  /// one mutation is already in flight — same text `AccountsBloc` uses for
  /// exactly the same shape of guard.
  static const String inFlightMessage = 'Another action is already in progress. Try again in a moment.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, below. `AssetsStarted` is also what "Try again" on
  /// `AssetsUnavailable` dispatches, and that retry must re-open on the Site
  /// the caller was looking at, not silently jump back to the first one.
  String? _lastSiteId;

  /// The last "Show retired" setting the caller chose, kept for the same
  /// reason as [_lastSiteId]: a retry or a Site switch must reopen on it
  /// rather than silently resetting to active-only.
  bool _lastShowRetired = false;

  Future<void> _onStarted(AssetsStarted event, Emitter<AssetsState> emit) async {
    emit(const AssetsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssetsUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(AssetsUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const AssetsUnavailable(message: noSitesMessage));
      return;
    }
    // A remembered Site the caller can no longer see must not strand them on
    // an empty pane — the same `sites.any` guard `OrgUnitPickerBloc._onStarted`
    // uses for `initialSiteId`. Keep the two consistent.
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(
      AssetsLoaded(
        sites: sites,
        siteId: opensOn,
        isLoadingAssets: true,
        showRetired: _lastShowRetired,
      ),
    );
    await _readRegister(opensOn, emit);
  }

  Future<void> _onSiteSelected(AssetsSiteSelected event, Emitter<AssetsState> emit) async {
    final current = state;
    if (current is! AssetsLoaded) return;
    _lastSiteId = event.siteId;
    emit(current.copyWith(siteId: event.siteId, assets: const [], isLoadingAssets: true));
    await _readRegister(event.siteId, emit);
  }

  Future<void> _readRegister(String siteId, Emitter<AssetsState> emit, {String? notice}) async {
    final token = _auth.currentAccessToken;
    final current = state;
    if (current is! AssetsLoaded) return;
    if (token == null) {
      emit(const AssetsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final assets = await _maintenance.fetchAssets(
        token,
        siteId: siteId,
        includeRetired: current.showRetired,
      );
      if (state is! AssetsLoaded || (state as AssetsLoaded).siteId != siteId) return;
      emit((state as AssetsLoaded).copyWith(assets: assets, isLoadingAssets: false, notice: notice));
    } on MaintenanceApiException catch (error) {
      if (state is! AssetsLoaded || (state as AssetsLoaded).siteId != siteId) return;
      emit(AssetsUnavailable(message: error.message));
    }
  }

  Future<void> _onAddConfirmed(AssetAddConfirmed event, Emitter<AssetsState> emit) async {
    final current = state;
    if (current is! AssetsLoaded || current.isAdding) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(addFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isAdding: true));
    try {
      final asset = await _maintenance.createAsset(
        token,
        orgUnitId: event.orgUnitId,
        code: event.code,
        name: event.name,
        assetType: event.assetType,
        criticality: event.criticality,
      );
      final settled = state;
      if (settled is! AssetsLoaded) return;
      // The response already says what the row became, so the register is
      // updated in place — the same reasoning the Approval queue's own writes
      // follow. An Asset placed in a Site that is not on screen simply does
      // not appear, which is honest: the caller is looking elsewhere.
      emit(
        settled.copyWith(
          isAdding: false,
          // Sorted into the register's own order — see [_inRegisterOrder].
          assets: asset.siteId == settled.siteId
              ? _inRegisterOrder([...settled.assets, asset])
              : settled.assets,
          notice: '${asset.code} is on the register, at ${asset.orgUnitName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! AssetsLoaded) return;
      emit(settled.copyWith(isAdding: false, addFailure: error.message));
    }
  }

  Future<void> _onShowRetiredChanged(
    AssetsShowRetiredChanged event,
    Emitter<AssetsState> emit,
  ) async {
    final current = state;
    if (current is! AssetsLoaded) return;
    final siteId = current.siteId;
    if (siteId == null) return;
    _lastShowRetired = event.showRetired;
    emit(current.copyWith(showRetired: event.showRetired, assets: const [], isLoadingAssets: true));
    await _readRegister(siteId, emit);
  }

  Future<void> _onActiveToggled(AssetActiveToggled event, Emitter<AssetsState> emit) async {
    final current = state;
    if (current is! AssetsLoaded) return;
    // Reported, not silently dropped — the same guard `AccountsBloc` uses for
    // `busyId`/`correctingId`, generalised to one flag since an Asset row
    // only ever has one mutation of its own.
    if (current.isAdding || current.mutatingAssetId != null) {
      emit(current.copyWith(notice: inFlightMessage));
      return;
    }

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(mutatingAssetId: event.assetId));
    try {
      final asset = await _maintenance.setAssetActive(token, event.assetId, isActive: event.isActive);
      final settled = state;
      if (settled is! AssetsLoaded) return;
      emit(
        settled.copyWith(
          clearMutatingAssetId: true,
          assets: _applyMutation(settled, asset),
          notice: event.isActive
              ? '${asset.code} is back on the active register.'
              : '${asset.code} has been retired.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! AssetsLoaded) return;
      emit(settled.copyWith(clearMutatingAssetId: true, notice: error.message));
    }
  }

  Future<void> _onParentChanged(AssetParentChanged event, Emitter<AssetsState> emit) async {
    final current = state;
    if (current is! AssetsLoaded) return;
    if (current.isAdding || current.mutatingAssetId != null) {
      emit(current.copyWith(notice: inFlightMessage));
      return;
    }

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(mutatingAssetId: event.assetId));
    try {
      final asset = await _maintenance.setAssetParent(token, event.assetId, parentId: event.parentId);
      final settled = state;
      if (settled is! AssetsLoaded) return;
      emit(
        settled.copyWith(
          clearMutatingAssetId: true,
          assets: _applyMutation(settled, asset),
          notice: event.parentId == null
              ? '${asset.code} is a top-level Asset again.'
              : '${asset.code} now sits beneath its new parent.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! AssetsLoaded) return;
      emit(settled.copyWith(clearMutatingAssetId: true, notice: error.message));
    }
  }

  /// Moves one Asset to another Org Unit (issue #171).
  ///
  /// Two things this does that its neighbours do not. The list is re-sorted:
  /// a move changes the Org Unit name the register orders by, so leaving the
  /// row where it was would show the machine in the wrong place until the
  /// next read. And a move to another Site takes the row out of the list
  /// rather than leaving it there — this register is one Site's, and an Asset
  /// that has left that Site is not on it. The notice says where it went, so
  /// a row that disappears is accounted for rather than doubted.
  Future<void> _onOrgUnitChanged(AssetOrgUnitChanged event, Emitter<AssetsState> emit) async {
    final current = state;
    if (current is! AssetsLoaded) return;
    if (current.isAdding || current.mutatingAssetId != null) {
      emit(current.copyWith(notice: inFlightMessage));
      return;
    }

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(notice: signedOutMessage));
      return;
    }

    emit(current.copyWith(mutatingAssetId: event.assetId));
    try {
      final asset = await _maintenance.setAssetOrgUnit(
        token,
        event.assetId,
        orgUnitId: event.orgUnitId,
      );
      final settled = state;
      if (settled is! AssetsLoaded) return;

      final staysOnThisRegister = asset.siteId == settled.siteId;
      final destinationSite = _siteNameFor(settled.sites, asset.siteId);
      final notice = staysOnThisRegister
          ? '${asset.code} now sits at ${asset.orgUnitName}.'
          : destinationSite == null
              ? '${asset.code} has left this Site — it now sits at ${asset.orgUnitName}.'
              : '${asset.code} has left this Site — it now sits at '
                  '${asset.orgUnitName}, at $destinationSite.';

      emit(
        settled.copyWith(
          clearMutatingAssetId: true,
          assets: staysOnThisRegister
              ? _inRegisterOrder(_applyMutation(settled, asset))
              : [for (final row in settled.assets) if (row.id != asset.id) row],
          notice: notice,
        ),
      );
    } on MaintenanceApiException catch (error) {
      final settled = state;
      if (settled is! AssetsLoaded) return;
      emit(settled.copyWith(clearMutatingAssetId: true, notice: error.message));
    }
  }

  /// The Sites the caller can see, by id — used only to name a Site the
  /// register is no longer showing, so `null` costs a shorter sentence rather
  /// than a wrong one.
  String? _siteNameFor(List<Site> sites, String? siteId) {
    for (final site in sites) {
      if (site.id == siteId) return site.name;
    }
    return null;
  }

  /// The register in the order the server sends it — `ORDER BY ou.name,
  /// a.code` (assets.js). The client's order has to agree with the server's,
  /// or every row reshuffles visibly on a mutation and flips back on the next
  /// read; a move is the mutation that changes the Org Unit name itself, so
  /// this matters most there.
  List<Asset> _inRegisterOrder(List<Asset> assets) => [...assets]..sort(
        (a, b) {
          final byOrgUnit = a.orgUnitName.compareTo(b.orgUnitName);
          return byOrgUnit != 0 ? byOrgUnit : a.code.compareTo(b.code);
        },
      );

  /// The register patched in place with one Asset's new state, rather than
  /// re-read — same reasoning [_onAddConfirmed] follows. An Asset that has
  /// just been retired drops out of the list entirely when the register is
  /// not currently showing retired ones, keeping the toggle honest about what
  /// it means rather than leaving a retired row visible until the next read.
  List<Asset> _applyMutation(AssetsLoaded state, Asset updated) {
    if (!state.showRetired && !updated.isActive) {
      return [for (final asset in state.assets) if (asset.id != updated.id) asset];
    }
    return [for (final asset in state.assets) if (asset.id == updated.id) updated else asset];
  }
}
