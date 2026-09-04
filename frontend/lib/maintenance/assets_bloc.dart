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
    String? notice,
  }) =>
      AssetsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        assets: assets ?? this.assets,
        isLoadingAssets: isLoadingAssets ?? this.isLoadingAssets,
        isAdding: isAdding ?? this.isAdding,
        addFailure: addFailure,
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
  }

  final MaintenanceApi _maintenance;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage =
      'There are no Sites you can see, so there is no register to show.';

  /// The last Site the caller actually settled on — set wherever a Site is
  /// settled, below. `AssetsStarted` is also what "Try again" on
  /// `AssetsUnavailable` dispatches, and that retry must re-open on the Site
  /// the caller was looking at, not silently jump back to the first one.
  String? _lastSiteId;

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
    emit(AssetsLoaded(sites: sites, siteId: opensOn, isLoadingAssets: true));
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
      final assets = await _maintenance.fetchAssets(token, siteId: siteId);
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
          // Sorted by (orgUnitName, code) to match the server's own `ORDER BY
          // ou.name, a.code` (assets.js) — the client's order must agree with
          // the server's, or every existing row visibly reshuffles on an add
          // and flips back on the next read.
          assets: asset.siteId == settled.siteId
              ? ([...settled.assets, asset]..sort(
                  (a, b) {
                    final byOrgUnit = a.orgUnitName.compareTo(b.orgUnitName);
                    return byOrgUnit != 0 ? byOrgUnit : a.code.compareTo(b.code);
                  },
                ))
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
}
