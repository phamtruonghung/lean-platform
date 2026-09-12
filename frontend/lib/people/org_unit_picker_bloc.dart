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

/// Forget what is cached at one level and read it again: the children of
/// [parentId], or the root level when it is null. A re-read, not a write —
/// this Bloc still knows nothing about *what* changed the tree (issue #90's
/// own Screen owns every write against it), only that a level it holds may be
/// stale. The coarse form of this already exists on [OrgUnitPickerSiteSelected]
/// — re-selecting the Site in hand re-reads its root level — this is the same
/// act scoped to one level, so a caller who has walked three levels down does
/// not lose the branch it walked just because one sibling elsewhere changed.
class OrgUnitPickerRefreshed extends OrgUnitPickerEvent {
  const OrgUnitPickerRefreshed({this.parentId});
  final String? parentId;
}

/// A unit found some other way than browsing — today, `OrgUnitsScreen`'s own
/// as-you-type search (issue #130) — should read as if it had been walked to
/// by hand: every ancestor between the root and it expanded, and it selected.
/// [ancestorIds] is the root-first ancestor id chain a search hit's own
/// `ltree` path implies (`OrgUnitNode.ancestorIds`), *not* trimmed to what
/// this caller can see — the handler below is the one place that trims it to
/// [OrgUnitPickerState.rootIds], because only it knows what is actually
/// drawable. Additive, the same shape [OrgUnitPickerRefreshed] already is:
/// one Screen's own need, meaningless to the Grant pickers sharing this Bloc.
class OrgUnitPickerRevealed extends OrgUnitPickerEvent {
  const OrgUnitPickerRevealed({required this.orgUnitId, required this.ancestorIds});
  final String orgUnitId;
  final List<String> ancestorIds;
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
    required this.isSelected,
    this.failure,
  });

  final OrgUnitNode node;
  final int depth;
  final List<String> ancestorNames;
  final bool isExpanded;
  final bool isLoadingChildren;
  final bool childrenLoaded;
  final int childCount;

  /// Whether this is the unit a search hit was last revealed to
  /// ([OrgUnitPickerState.selectedId]) — see [OrgUnitPickerRevealed].
  final bool isSelected;
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
    this.selectedId,
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

  /// The unit a search hit was last revealed to (issue #130,
  /// [OrgUnitPickerRevealed]), or null. Means nothing to the Grant pickers
  /// sharing this Bloc — only `OrgUnitsScreen`'s own tree reads it, the same
  /// "shared state, one caller's own field" shape [granted] already is for
  /// the tree-browsing callers. Cleared whenever the tree itself is —
  /// [_onSiteSelected] — since a selection made in one Site means nothing in
  /// another.
  final String? selectedId;

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

  /// Resolves as many of [orgUnit]'s own ancestor ids ([OrgUnitNode.ancestorIds])
  /// as this Bloc already happens to know the name of, root-first — a search
  /// hit's own breadcrumb (issue #130), built without a request of its own.
  /// An ancestor not yet loaded into [nodesById] (nothing above this caller's
  /// own [rootIds] ever will be, and a deeper one may simply not have been
  /// expanded yet) renders as `'…'` rather than being silently dropped, so
  /// two same-named units under different unloaded parents still read apart.
  List<String> ancestorNamesFor(OrgUnitNode orgUnit) => [
        for (final id in orgUnit.ancestorIds) nodesById[id]?.name ?? '…',
      ];

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
            isSelected: id == selectedId,
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
    String? selectedId,
    bool clearSelectedId = false,
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
      selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
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
    on<OrgUnitPickerRefreshed>(_onRefreshed);
    on<OrgUnitPickerGrantAdded>(_onGrantAdded);
    on<OrgUnitPickerGrantRemoved>(_onGrantRemoved);
    on<OrgUnitPickerRevealed>(_onRevealed);
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
        // A selection made in a different Site means nothing here — see
        // `OrgUnitPickerState.selectedId`'s own doc comment.
        clearSelectedId: true,
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
    if (siteId == null) return;
    await _loadChildren(siteId, id, emit);
  }

  void _onCollapsed(OrgUnitPickerCollapsed event, Emitter<OrgUnitPickerState> emit) {
    emit(state.copyWith(expandedIds: {...state.expandedIds}..remove(event.orgUnitId)));
  }

  /// One level, forced stale and re-read — the write-refresh seam issue #90's
  /// own Screen drives after a create or a retirement lands, since this Bloc
  /// has no other way to learn the tree changed underneath it. Unlike
  /// [_onExpanded], this never checks whether the level is already cached:
  /// that is the entire point of a refresh.
  Future<void> _onRefreshed(OrgUnitPickerRefreshed event, Emitter<OrgUnitPickerState> emit) async {
    final siteId = state.siteId;
    if (siteId == null) return;

    final parentId = event.parentId;
    if (parentId == null) {
      final token = _auth.currentAccessToken;
      if (token == null) {
        emit(state.copyWith(rootsFailure: signedOutMessage));
        return;
      }
      try {
        final roots = await _api.fetchOrgUnits(token, siteId: siteId);
        if (state.siteId != siteId) return;
        emit(
          state.copyWith(
            rootIds: [for (final node in roots) node.id],
            nodesById: {...state.nodesById, for (final node in roots) node.id: node},
            clearRootsFailure: true,
          ),
        );
      } on PeopleApiException catch (error) {
        if (state.siteId != siteId) return;
        emit(state.copyWith(rootsFailure: error.message));
      }
      return;
    }

    emit(
      state.copyWith(
        childIdsByParent: {...state.childIdsByParent}..remove(parentId),
        childFailures: {...state.childFailures}..remove(parentId),
      ),
    );
    await _loadChildren(siteId, parentId, emit);
  }

  /// The body [_onExpanded] and [_onRefreshed] share: read one Org Unit's
  /// direct children and file them under its id, or record why that failed.
  Future<void> _loadChildren(String siteId, String id, Emitter<OrgUnitPickerState> emit) async {
    final token = _auth.currentAccessToken;
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

  /// Walks [event.ancestorIds] top-down, expanding (and, where not already
  /// cached, fetching) each level, then selects [event.orgUnitId] — reading
  /// as if a person had opened every branch between the root and it by hand.
  ///
  /// Trimmed to [OrgUnitPickerState.rootIds] before any of that: [rows] only
  /// ever walks from `rootIds` downward, and for a non-administrator those
  /// are entry points already several levels into the real tree (ADR-0008),
  /// so a search hit's own full `ltree` chain reaches above anything this
  /// caller can actually see. An id above the first one this caller's own
  /// root level contains is neither drawable nor worth a request.
  ///
  /// `state.siteId` is re-read at the top of every iteration, not captured
  /// once: a later Site choice mid-walk must win, the same rule
  /// `_loadChildren`'s own post-fetch check already enforces after each
  /// fetch resolves — this guards the moments *before* a fetch, too, so an id
  /// never gets stuck in `loadingIds` for a Site nobody is looking at any
  /// more.
  Future<void> _onRevealed(OrgUnitPickerRevealed event, Emitter<OrgUnitPickerState> emit) async {
    final siteId = state.siteId;
    if (siteId == null) return;

    final chain = event.ancestorIds;
    final from = chain.indexWhere(state.rootIds.contains);
    if (from != -1) {
      for (final id in chain.sublist(from)) {
        if (state.siteId != siteId) return; // A later Site choice won.
        emit(state.copyWith(expandedIds: {...state.expandedIds, id}));
        if (state.childIdsByParent.containsKey(id) || state.loadingIds.contains(id)) continue;
        await _loadChildren(siteId, id, emit);
      }
    }
    if (state.siteId != siteId) return;
    emit(state.copyWith(selectedId: event.orgUnitId));
  }
}
