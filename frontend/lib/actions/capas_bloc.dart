/// The CAPA list's own state (issue #211): every investigation on the Platform,
/// the three ways to narrow them, and whether the read is still in flight.
///
/// Route-scoped and shared by the whole CAPA-list surface, the same shape
/// `ActionsBloc` and `NonconformancesBloc` keep: the Screen that lists the
/// investigations and the Org Unit filter dialog over it read this one state,
/// so the filter a caller picked is still there when the dialog closes.
///
/// It holds `ActionsApi` and nothing else, and that is the difference from the
/// two registers above it: a CAPA list is not a Site's, so there is no Site
/// chooser to read People for and no second API to hold. Which Org Unit is
/// *chosen* is People's tree — the filter dialog mounts People's own picker the
/// way every other chooser in this client does, through
/// `lib/people/people.dart`.
///
/// Every filter sends a request rather than hiding rows client-side, which is
/// what the server's ltree walk and its own indexes are for: a filter that
/// narrowed the client's own copy would silently disagree with the count the
/// moment the list is capped.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../platform/auth_gateway.dart';
import 'actions_api.dart';
import 'capa.dart';

sealed class CapasEvent {
  const CapasEvent();
}

/// Load the list. Also the retry a failed read offers, so a retry re-opens on
/// the filters the caller had settled on rather than silently resetting them.
class CapasStarted extends CapasEvent {
  const CapasStarted();
}

/// Re-read the list whenever the Screen is entered (ADR-0012's own lesson,
/// issue #183): the `ShellRoute` creates this Bloc once and keeps it alive
/// while a caller reads one investigation and comes back, so a Screen that only
/// read on `CapasStarted` would paint the list as it was when they left — a
/// check recorded elsewhere, an investigation closed, a due date passed, none
/// of it visible. The Bloc ignores the ask while its first read is in flight.
class CapasRefreshed extends CapasEvent {
  const CapasRefreshed();
}

/// Narrow the list to one Org Unit and everything beneath it, the same ltree
/// walk the Action register's and the Non-conformance register's own Org Unit
/// filters make. The name rides along so the button can say which area is on
/// screen without a second read.
class CapasOrgUnitFilterSelected extends CapasEvent {
  const CapasOrgUnitFilterSelected({required this.orgUnitId, required this.orgUnitName});

  final String orgUnitId;
  final String orgUnitName;
}

class CapasOrgUnitFilterCleared extends CapasEvent {
  const CapasOrgUnitFilterCleared();
}

/// Narrow to the investigations in one of the seven states.
class CapasStatusFilterChanged extends CapasEvent {
  const CapasStatusFilterChanged(this.status);

  final String? status;
}

/// Narrow to the checks that have fallen due and not been recorded — the list
/// this ticket exists to make readable.
class CapasOverdueToggled extends CapasEvent {
  const CapasOverdueToggled(this.overdue);

  final bool overdue;
}

/// Every filter back to "every investigation".
class CapasFiltersCleared extends CapasEvent {
  const CapasFiltersCleared();
}

sealed class CapasState {
  const CapasState();
}

class CapasLoading extends CapasState {
  const CapasLoading();
}

class CapasLoaded extends CapasState {
  const CapasLoaded({
    this.capas = const [],
    this.truncated = false,
    this.isLoadingCapas = false,
    this.orgUnitFilterId,
    this.orgUnitFilterName,
    this.statusFilter,
    this.overdueFilter = false,
    this.notice,
  });

  final List<Capa> capas;

  /// Whether the server had more than it was willing to send. Rendered, never
  /// swallowed: a capped list must not read as the whole Platform.
  final bool truncated;

  /// A filter change re-reads the list while the header stays on screen — the
  /// placeholders belong to the rows, not to the Screen.
  final bool isLoadingCapas;

  final String? orgUnitFilterId;
  final String? orgUnitFilterName;
  final String? statusFilter;
  final bool overdueFilter;

  /// What the last act had to say for itself. Never the failure of a read: that
  /// is [CapasUnavailable].
  final String? notice;

  /// Whether anything is narrowing the list — which decides which of the two
  /// empty stories the Screen tells (issue #103): a Plant with no investigations
  /// at all is not the same as a filter that matched none of them.
  bool get isFiltered => orgUnitFilterId != null || statusFilter != null || overdueFilter;

  CapasLoaded copyWith({
    List<Capa>? capas,
    bool? truncated,
    bool? isLoadingCapas,
    String? orgUnitFilterId,
    String? orgUnitFilterName,
    bool clearOrgUnitFilter = false,
    String? statusFilter,
    bool clearStatusFilter = false,
    bool? overdueFilter,
    String? notice,
  }) =>
      CapasLoaded(
        capas: capas ?? this.capas,
        truncated: truncated ?? this.truncated,
        isLoadingCapas: isLoadingCapas ?? this.isLoadingCapas,
        // `clearX` flags rather than `copyWith(x: null)`, exactly as
        // `ActionsLoaded` does: every re-read emits another `copyWith`, and a
        // plain `?? this.x` with a null default would clear a filter the caller
        // set one event earlier.
        orgUnitFilterId: clearOrgUnitFilter ? null : (orgUnitFilterId ?? this.orgUnitFilterId),
        orgUnitFilterName:
            clearOrgUnitFilter ? null : (orgUnitFilterName ?? this.orgUnitFilterName),
        statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
        overdueFilter: overdueFilter ?? this.overdueFilter,
        notice: notice,
      );
}

class CapasUnavailable extends CapasState {
  const CapasUnavailable({required this.message});

  final String message;
}

class CapasBloc extends Bloc<CapasEvent, CapasState> {
  CapasBloc({required ActionsApi actionsApi, required AuthGateway authGateway})
      : _actions = actionsApi,
        _auth = authGateway,
        super(const CapasLoading()) {
    on<CapasStarted>(_onStarted);
    on<CapasRefreshed>(_onRefreshed);
    on<CapasOrgUnitFilterSelected>(_onOrgUnitFilterSelected);
    on<CapasOrgUnitFilterCleared>(_onOrgUnitFilterCleared);
    on<CapasStatusFilterChanged>(_onStatusFilterChanged);
    on<CapasOverdueToggled>(_onOverdueToggled);
    on<CapasFiltersCleared>(_onFiltersCleared);
  }

  final ActionsApi _actions;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  /// The last filter set the caller settled on. `CapasStarted` is also what
  /// "Try again" on [CapasUnavailable] dispatches, and that retry must re-open
  /// where they were looking rather than silently resetting to everything.
  String? _lastOrgUnitFilterId;
  String? _lastOrgUnitFilterName;
  String? _lastStatusFilter;
  bool _lastOverdueFilter = false;

  Future<void> _onStarted(CapasStarted event, Emitter<CapasState> emit) async {
    emit(const CapasLoading());
    emit(
      CapasLoaded(
        isLoadingCapas: true,
        orgUnitFilterId: _lastOrgUnitFilterId,
        orgUnitFilterName: _lastOrgUnitFilterName,
        statusFilter: _lastStatusFilter,
        overdueFilter: _lastOverdueFilter,
      ),
    );
    await _read(emit);
  }

  Future<void> _onRefreshed(CapasRefreshed event, Emitter<CapasState> emit) async {
    final current = state;
    if (current is! CapasLoaded || current.isLoadingCapas) return;
    emit(current.copyWith(isLoadingCapas: true));
    await _read(emit);
  }

  Future<void> _onOrgUnitFilterSelected(
    CapasOrgUnitFilterSelected event,
    Emitter<CapasState> emit,
  ) async {
    final current = state;
    if (current is! CapasLoaded) return;
    _lastOrgUnitFilterId = event.orgUnitId;
    _lastOrgUnitFilterName = event.orgUnitName;
    emit(
      current.copyWith(
        orgUnitFilterId: event.orgUnitId,
        orgUnitFilterName: event.orgUnitName,
        capas: const [],
        isLoadingCapas: true,
      ),
    );
    await _read(emit);
  }

  Future<void> _onOrgUnitFilterCleared(
    CapasOrgUnitFilterCleared event,
    Emitter<CapasState> emit,
  ) async {
    final current = state;
    if (current is! CapasLoaded) return;
    _lastOrgUnitFilterId = null;
    _lastOrgUnitFilterName = null;
    emit(current.copyWith(clearOrgUnitFilter: true, capas: const [], isLoadingCapas: true));
    await _read(emit);
  }

  Future<void> _onStatusFilterChanged(
    CapasStatusFilterChanged event,
    Emitter<CapasState> emit,
  ) async {
    final current = state;
    if (current is! CapasLoaded) return;
    _lastStatusFilter = event.status;
    emit(
      current.copyWith(
        statusFilter: event.status,
        clearStatusFilter: event.status == null,
        capas: const [],
        isLoadingCapas: true,
      ),
    );
    await _read(emit);
  }

  Future<void> _onOverdueToggled(
    CapasOverdueToggled event,
    Emitter<CapasState> emit,
  ) async {
    final current = state;
    if (current is! CapasLoaded) return;
    _lastOverdueFilter = event.overdue;
    emit(
      current.copyWith(overdueFilter: event.overdue, capas: const [], isLoadingCapas: true),
    );
    await _read(emit);
  }

  Future<void> _onFiltersCleared(CapasFiltersCleared event, Emitter<CapasState> emit) async {
    final current = state;
    if (current is! CapasLoaded) return;
    _lastOrgUnitFilterId = null;
    _lastOrgUnitFilterName = null;
    _lastStatusFilter = null;
    _lastOverdueFilter = false;
    emit(
      current.copyWith(
        clearOrgUnitFilter: true,
        clearStatusFilter: true,
        overdueFilter: false,
        capas: const [],
        isLoadingCapas: true,
      ),
    );
    await _read(emit);
  }

  /// Reads the list with the filters on the state, and keeps the read honest
  /// about which filters produced it: a response that arrives after the caller
  /// has moved on is dropped rather than painted over the newer one.
  Future<void> _read(Emitter<CapasState> emit) async {
    final current = state;
    if (current is! CapasLoaded) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const CapasUnavailable(message: signedOutMessage));
      return;
    }

    // The filters this read was made with, so the answer is only kept when they
    // are still the ones on screen.
    final asked = (
      current.orgUnitFilterId,
      current.statusFilter,
      current.overdueFilter
    );
    try {
      final register = await _actions.fetchCapas(
        token,
        orgUnitId: current.orgUnitFilterId,
        status: current.statusFilter,
        overdue: current.overdueFilter,
      );
      final latest = state;
      if (latest is! CapasLoaded) return;
      if ((latest.orgUnitFilterId, latest.statusFilter, latest.overdueFilter) != asked) return;
      emit(
        latest.copyWith(
          capas: register.capas,
          truncated: register.truncated,
          isLoadingCapas: false,
        ),
      );
    } on ActionsApiException catch (error) {
      if (state is! CapasLoaded) return;
      emit(CapasUnavailable(message: error.message));
    }
  }
}
