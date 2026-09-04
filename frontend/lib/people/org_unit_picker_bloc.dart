/// The Org Unit picker's own state: browsing a Site's tree one level at a
/// time, and the Grant set being assembled from it.
///
/// Deliberately its own Bloc, not a corner of `ApprovalQueueBloc`. Choosing
/// Org Units is a job several Screens will have (an Account's Grants being
/// edited later, an Asset being placed), and none of them has an Approval
/// queue behind it. What the picker knows — a Site, a partly-expanded tree, a
/// Granted set — is the whole of that job; what an Approval does with the
/// result is the Approval's business.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'org_unit.dart';

sealed class OrgUnitPickerEvent {
  const OrgUnitPickerEvent();
}

/// Load the Sites this Account can see. Also the retry a failed load offers.
class OrgUnitPickerStarted extends OrgUnitPickerEvent {
  const OrgUnitPickerStarted();
}

/// Browse a different Site. The tree is emptied; the Granted set is not —
/// Grants may span Sites in one Approval. Also what the tree pane's retry
/// dispatches for a root-level failure, re-reading the same Site rather than
/// treating a fetch failure as a reason to change what is being browsed.
class OrgUnitPickerSiteSelected extends OrgUnitPickerEvent {
  const OrgUnitPickerSiteSelected(this.siteId);
  final String siteId;
}

/// Open an Org Unit. Its children are requested here and nowhere else — that
/// is what "expanding requests children, and only then" means.
class OrgUnitPickerExpanded extends OrgUnitPickerEvent {
  const OrgUnitPickerExpanded(this.orgUnitId);
  final String orgUnitId;
}

class OrgUnitPickerCollapsed extends OrgUnitPickerEvent {
  const OrgUnitPickerCollapsed(this.orgUnitId);
  final String orgUnitId;
}

/// A deliberate act with a level already chosen — there is no event that adds
/// an Org Unit without one, which is what keeps "a level must be chosen" a
/// property of the state machine rather than of one widget.
class OrgUnitPickerGrantAdded extends OrgUnitPickerEvent {
  const OrgUnitPickerGrantAdded({required this.orgUnitId, required this.level});
  final String orgUnitId;
  final GrantLevel level;
}

class OrgUnitPickerGrantRemoved extends OrgUnitPickerEvent {
  const OrgUnitPickerGrantRemoved(this.orgUnitId);
  final String orgUnitId;
}

enum SitesStatus { loading, ready, failed }

/// One row of the tree as it is drawn: the node, how deep it sits *in this
/// view*, and the names above it that were walked through to reach it.
class OrgUnitRow {
  const OrgUnitRow({
    required this.node,
    required this.depth,
    required this.ancestorNames,
    required this.isExpanded,
    required this.isLoadingChildren,
    required this.childrenLoaded,
    required this.childCount,
    this.failure,
  });

  final OrgUnitNode node;
  final int depth;
  final List<String> ancestorNames;
  final bool isExpanded;
  final bool isLoadingChildren;
  final bool childrenLoaded;
  final int childCount;
  final String? failure;
}

/// One state class, not a sealed family: the tree, the Sites and the Granted
/// set load and fail independently, and a caller with a half-loaded tree and a
/// full Granted set is an ordinary situation rather than a state of its own.
class OrgUnitPickerState {
  const OrgUnitPickerState({
    this.sitesStatus = SitesStatus.loading,
    this.sitesFailure,
    this.sites = const [],
    this.siteId,
    this.rootIds = const [],
    this.rootsLoading = false,
    this.rootsFailure,
    this.nodesById = const {},
    this.childIdsByParent = const {},
    this.expandedIds = const {},
    this.loadingIds = const {},
    this.childFailures = const {},
    this.granted = const [],
  });

  final SitesStatus sitesStatus;
  final String? sitesFailure;
  final List<Site> sites;

  /// The Site being browsed, or null when none is chosen yet.
  final String? siteId;

  /// The ids the *root-level* request answered with, in the order it gave
  /// them. This is the only thing that decides what sits at the top of the
  /// tree — never `parentId == null`. For a non-administrator these are entry
  /// points carrying real parents (ADR-0008); they are top-level here because
  /// the root-level request returned them, and there is nothing above them
  /// this caller was given to nest them under.
  final List<String> rootIds;

  final bool rootsLoading;
  final String? rootsFailure;

  final Map<String, OrgUnitNode> nodesById;

  /// Children by *their parent's id*, filled only by an expansion. A key
  /// present with an empty list means "asked, and there is nothing beneath
  /// this" — distinct from absent, which means "never asked".
  final Map<String, List<String>> childIdsByParent;

  final Set<String> expandedIds;
  final Set<String> loadingIds;
  final Map<String, String> childFailures;

  /// The complete Grant set being submitted, in the order it was assembled.
  final List<GrantedOrgUnit> granted;

  Site? get site {
    for (final candidate in sites) {
      if (candidate.id == siteId) return candidate;
    }
    return null;
  }

  bool isGranted(String orgUnitId) => granted.any((g) => g.orgUnit.id == orgUnitId);

  GrantLevel? levelOf(String orgUnitId) {
    for (final entry in granted) {
      if (entry.orgUnit.id == orgUnitId) return entry.level;
    }
    return null;
  }

  /// The Grant set as the Approval endpoint wants it.
  List<Map<String, Object?>> get grantsPayload => [for (final g in granted) g.toJson()];

  /// The tree flattened for drawing, depth-first from [rootIds] downward
  /// through whatever has been expanded. Structure comes from [rootIds] and
  /// [childIdsByParent] and from nothing else.
  List<OrgUnitRow> get rows {
    final result = <OrgUnitRow>[];
    void walk(List<String> ids, int depth, List<String> ancestors) {
      for (final id in ids) {
        final node = nodesById[id];
        if (node == null) continue;
        final children = childIdsByParent[id];
        final expanded = expandedIds.contains(id);
        result.add(
          OrgUnitRow(
            node: node,
            depth: depth,
            ancestorNames: ancestors,
            isExpanded: expanded,
            isLoadingChildren: loadingIds.contains(id),
            childrenLoaded: children != null,
            childCount: children?.length ?? 0,
            failure: childFailures[id],
          ),
        );
        if (expanded && children != null) {
          walk(children, depth + 1, [...ancestors, node.name]);
        }
      }
    }

    walk(rootIds, 0, const []);
    return result;
  }

  OrgUnitPickerState copyWith({
    SitesStatus? sitesStatus,
    String? sitesFailure,
    bool clearSitesFailure = false,
    List<Site>? sites,
    String? siteId,
    List<String>? rootIds,
    bool? rootsLoading,
    String? rootsFailure,
    bool clearRootsFailure = false,
    Map<String, OrgUnitNode>? nodesById,
    Map<String, List<String>>? childIdsByParent,
    Set<String>? expandedIds,
    Set<String>? loadingIds,
    Map<String, String>? childFailures,
    List<GrantedOrgUnit>? granted,
  }) {
    return OrgUnitPickerState(
      sitesStatus: sitesStatus ?? this.sitesStatus,
      sitesFailure: clearSitesFailure ? null : (sitesFailure ?? this.sitesFailure),
      sites: sites ?? this.sites,
      siteId: siteId ?? this.siteId,
      rootIds: rootIds ?? this.rootIds,
      rootsLoading: rootsLoading ?? this.rootsLoading,
      rootsFailure: clearRootsFailure ? null : (rootsFailure ?? this.rootsFailure),
      nodesById: nodesById ?? this.nodesById,
      childIdsByParent: childIdsByParent ?? this.childIdsByParent,
      expandedIds: expandedIds ?? this.expandedIds,
      loadingIds: loadingIds ?? this.loadingIds,
      childFailures: childFailures ?? this.childFailures,
      granted: granted ?? this.granted,
    );
  }
}

class OrgUnitPickerBloc extends Bloc<OrgUnitPickerEvent, OrgUnitPickerState> {
  /// [initialGranted] is the Grant set this picker opens holding — the Grants
  /// an Account already has, when what is being edited is a correction rather
  /// than a first admission (issue #36). Deliberately a starting state and not
  /// a replay of [OrgUnitPickerGrantAdded]: that event requires the Org Unit to
  /// be a node already on screen, because it captures the breadcrumb the tree
  /// was walked down to reach it, and a pre-filled Grant was never walked to —
  /// it can sit in an unexpanded branch, or in a Site nobody has opened.
  /// Everything downstream still works by id alone: the tree badges a granted
  /// row through `isGranted`, and [OrgUnitPickerGrantRemoved] never looks a
  /// node up.
  /// [initialSiteId] is the Site to open on, when the Screen that mounted this
  /// picker is already looking at one (issue #56's Asset form). Null keeps
  /// today's behaviour exactly: the first Site the caller can see. An id the
  /// caller cannot actually see falls back to that same first Site rather than
  /// leaving the picker on an empty pane.
  OrgUnitPickerBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    List<GrantedOrgUnit> initialGranted = const [],
    String? initialSiteId,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(OrgUnitPickerState(granted: initialGranted, siteId: initialSiteId)) {
    on<OrgUnitPickerStarted>(_onStarted);
    on<OrgUnitPickerSiteSelected>(_onSiteSelected);
    on<OrgUnitPickerExpanded>(_onExpanded);
    on<OrgUnitPickerCollapsed>(_onCollapsed);
    on<OrgUnitPickerGrantAdded>(_onGrantAdded);
    on<OrgUnitPickerGrantRemoved>(_onGrantRemoved);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(OrgUnitPickerStarted event, Emitter<OrgUnitPickerState> emit) async {
    emit(state.copyWith(sitesStatus: SitesStatus.loading, clearSitesFailure: true));
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(sitesStatus: SitesStatus.failed, sitesFailure: signedOutMessage));
      return;
    }
    try {
      final sites = await _api.fetchSites(token);
      emit(state.copyWith(sitesStatus: SitesStatus.ready, sites: sites));
      if (sites.isNotEmpty) {
        // One Site or several, one is browsed straight away: a picker that
        // opens on an empty pane makes the caller do a step the Screen could
        // have done for them. Which Site is still theirs to change.
        final wanted = state.siteId;
        final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
        add(OrgUnitPickerSiteSelected(opensOn));
      }
    } on PeopleApiException catch (error) {
      emit(state.copyWith(sitesStatus: SitesStatus.failed, sitesFailure: error.message));
    }
  }

  Future<void> _onSiteSelected(
    OrgUnitPickerSiteSelected event,
    Emitter<OrgUnitPickerState> emit,
  ) async {
    // The tree is emptied, the Granted set is kept: Grants may span Sites.
    emit(
      state.copyWith(
        siteId: event.siteId,
        rootIds: const [],
        nodesById: const {},
        childIdsByParent: const {},
        expandedIds: const {},
        loadingIds: const {},
        childFailures: const {},
        rootsLoading: true,
        clearRootsFailure: true,
      ),
    );

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(state.copyWith(rootsLoading: false, rootsFailure: signedOutMessage));
      return;
    }
    try {
      final roots = await _api.fetchOrgUnits(token, siteId: event.siteId);
      if (state.siteId != event.siteId) return; // A later choice won.
      emit(
        state.copyWith(
          rootsLoading: false,
          rootIds: [for (final node in roots) node.id],
          nodesById: {...state.nodesById, for (final node in roots) node.id: node},
        ),
      );
    } on PeopleApiException catch (error) {
      if (state.siteId != event.siteId) return;
      emit(state.copyWith(rootsLoading: false, rootsFailure: error.message));
    }
  }

  Future<void> _onExpanded(OrgUnitPickerExpanded event, Emitter<OrgUnitPickerState> emit) async {
    final id = event.orgUnitId;
    emit(state.copyWith(expandedIds: {...state.expandedIds, id}));

    // Children are fetched once. Re-opening a branch already walked costs
    // nothing — "expanding requests children, and only then" is about never
    // fetching ahead, not about refetching what is already here.
    if (state.childIdsByParent.containsKey(id) || state.loadingIds.contains(id)) return;

    final siteId = state.siteId;
    final token = _auth.currentAccessToken;
    if (siteId == null) return;
    if (token == null) {
      emit(state.copyWith(childFailures: {...state.childFailures, id: signedOutMessage}));
      return;
    }

    emit(
      state.copyWith(
        loadingIds: {...state.loadingIds, id},
        childFailures: {...state.childFailures}..remove(id),
      ),
    );
    try {
      final children = await _api.fetchOrgUnits(token, siteId: siteId, parentId: id);
      if (state.siteId != siteId) return;
      emit(
        state.copyWith(
          loadingIds: {...state.loadingIds}..remove(id),
          childIdsByParent: {
            ...state.childIdsByParent,
            id: [for (final node in children) node.id],
          },
          nodesById: {...state.nodesById, for (final node in children) node.id: node},
        ),
      );
    } on PeopleApiException catch (error) {
      if (state.siteId != siteId) return;
      emit(
        state.copyWith(
          loadingIds: {...state.loadingIds}..remove(id),
          childFailures: {...state.childFailures, id: error.message},
        ),
      );
    }
  }

  void _onCollapsed(OrgUnitPickerCollapsed event, Emitter<OrgUnitPickerState> emit) {
    emit(state.copyWith(expandedIds: {...state.expandedIds}..remove(event.orgUnitId)));
  }

  void _onGrantAdded(OrgUnitPickerGrantAdded event, Emitter<OrgUnitPickerState> emit) {
    final node = state.nodesById[event.orgUnitId];
    if (node == null || state.isGranted(event.orgUnitId)) return;

    final siteName = state.site?.name;
    var ancestors = const <String>[];
    for (final row in state.rows) {
      if (row.node.id == event.orgUnitId) {
        ancestors = row.ancestorNames;
        break;
      }
    }
    final where = [?siteName, ...ancestors].join(' › ');

    emit(
      state.copyWith(
        granted: [
          ...state.granted,
          GrantedOrgUnit(orgUnit: node, level: event.level, where: where),
        ],
      ),
    );
  }

  void _onGrantRemoved(OrgUnitPickerGrantRemoved event, Emitter<OrgUnitPickerState> emit) {
    emit(
      state.copyWith(
        granted: [
          for (final entry in state.granted)
            if (entry.orgUnit.id != event.orgUnitId) entry,
        ],
      ),
    );
  }
}
