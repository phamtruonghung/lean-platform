/// The Non-conformance register's own state (issue #205): a Site's
/// Non-conformances, the filters that narrow them, the two catalogues the
/// filters choose from, and the recording of a new one.
///
/// Route-scoped and shared by the whole Non-conformance surface, the same
/// shape `ActionsBloc` keeps: one `ShellRoute` creates it once and the
/// register, the record form's own address and the detail Screen all read it,
/// so the Site and the filters a caller picked survive opening a record and
/// coming back.
///
/// Every filter sends a request rather than hiding rows client-side — that is
/// what the server's own indexes and its ltree walk are for, and a filter that
/// narrowed the client's copy would silently disagree with the count once the
/// list is capped. The chose-not-typed rule (ADR-0023) is what the two
/// catalogues are here for: a Defect code, a Product and a severity are all
/// chosen from what the server offers.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'defect_code.dart';
import 'nonconformance.dart';
import 'product.dart';
import 'quality_api.dart';

sealed class NonconformancesEvent {
  const NonconformancesEvent();
}

/// Load the register: the Sites, the two catalogues the filters choose from,
/// and the Site's Non-conformances. Also the retry a failed load offers.
class NonconformancesStarted extends NonconformancesEvent {
  const NonconformancesStarted();
}

/// Re-read the list whenever the register is entered (issue #183's own
/// reasoning): the `ShellRoute` keeps this Bloc alive while a caller reads a
/// Non-conformance and comes back, so a Screen that only read on
/// `NonconformancesStarted` would paint the list as it was when they left.
class NonconformancesRefreshed extends NonconformancesEvent {
  const NonconformancesRefreshed();
}

/// A different Site.
class NonconformancesSiteSelected extends NonconformancesEvent {
  const NonconformancesSiteSelected(this.siteId);

  final String siteId;
}

/// Narrow to one Org Unit and everything beneath it. The name rides along so
/// the button can say which area is on screen without a second read.
class NonconformancesOrgUnitFilterSet extends NonconformancesEvent {
  const NonconformancesOrgUnitFilterSet({required this.orgUnitId, required this.name});

  final String orgUnitId;
  final String name;
}

class NonconformancesStatusFilterChanged extends NonconformancesEvent {
  const NonconformancesStatusFilterChanged(this.status);

  final String? status;
}

class NonconformancesDefectCodeFilterChanged extends NonconformancesEvent {
  const NonconformancesDefectCodeFilterChanged(this.defectCodeId);

  final String? defectCodeId;
}

class NonconformancesProductFilterChanged extends NonconformancesEvent {
  const NonconformancesProductFilterChanged(this.productId);

  final String? productId;
}

class NonconformancesSeverityFilterChanged extends NonconformancesEvent {
  const NonconformancesSeverityFilterChanged(this.severity);

  final String? severity;
}

/// The production days the register covers, either end optional.
class NonconformancesDateRangeChanged extends NonconformancesEvent {
  const NonconformancesDateRangeChanged({this.from, this.to, this.clearFrom = false, this.clearTo = false});

  final String? from;
  final String? to;
  final bool clearFrom;
  final bool clearTo;
}

class NonconformancesFiltersCleared extends NonconformancesEvent {
  const NonconformancesFiltersCleared();
}

/// The record form has decided: a whole new Non-conformance. Same contract as
/// `ActionsRaiseConfirmed` — the dialog decides, the Bloc only ever sees a
/// decision already made, and the refusal comes back as `recordFailure` so the
/// dialog stays open with its values.
class NonconformanceRecordConfirmed extends NonconformancesEvent {
  const NonconformanceRecordConfirmed({
    required this.orgUnitId,
    required this.productId,
    required this.defectCodeId,
    required this.detectionPoint,
    required this.quantity,
    this.severity,
    this.assetId,
    this.lotRef,
    this.description,
    this.immediateContainment,
    this.detectedAt,
  });

  final String orgUnitId;
  final String productId;
  final String defectCodeId;
  final String detectionPoint;
  final num quantity;
  final String? severity;
  final String? assetId;
  final String? lotRef;
  final String? description;
  final String? immediateContainment;
  final String? detectedAt;
}

sealed class NonconformancesState {
  const NonconformancesState();
}

class NonconformancesLoading extends NonconformancesState {
  const NonconformancesLoading();
}

class NonconformancesUnavailable extends NonconformancesState {
  const NonconformancesUnavailable({required this.message});

  final String message;
}

class NonconformancesLoaded extends NonconformancesState {
  const NonconformancesLoaded({
    required this.sites,
    required this.siteId,
    required this.filters,
    required this.nonconformances,
    required this.truncated,
    required this.products,
    required this.defectCodes,
    this.isRecording = false,
    this.recordFailure,
  });

  final List<Site> sites;

  /// The Site on screen, or null when the caller can see none — in which case
  /// there is no register to read and the Screen says so.
  final String? siteId;

  final NonconformanceFilters filters;
  final List<Nonconformance> nonconformances;
  final bool truncated;

  /// The two catalogues the filters and the record form choose from. Read once
  /// with the register rather than per control, so opening a dropdown issues
  /// no request at all.
  final List<Product> products;
  final List<DefectCode> defectCodes;

  /// A recording is in flight.
  final bool isRecording;

  /// Why the last recording did not land. Reported by the form, which stays
  /// open so the caller can fix the one field that was wrong.
  final String? recordFailure;

  Site? get site {
    for (final site in sites) {
      if (site.id == siteId) return site;
    }
    return null;
  }

  NonconformancesLoaded copyWith({
    String? siteId,
    NonconformanceFilters? filters,
    List<Nonconformance>? nonconformances,
    bool? truncated,
    bool? isRecording,
    String? recordFailure,
  }) =>
      NonconformancesLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        filters: filters ?? this.filters,
        nonconformances: nonconformances ?? this.nonconformances,
        truncated: truncated ?? this.truncated,
        products: products,
        defectCodes: defectCodes,
        isRecording: isRecording ?? this.isRecording,
        // Always overwritten, never carried forward — the same rule
        // `ProductsLoaded.copyWith` gives its own failure.
        recordFailure: recordFailure,
      );
}

class NonconformancesBloc extends Bloc<NonconformancesEvent, NonconformancesState> {
  NonconformancesBloc({
    required QualityApi qualityApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = qualityApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const NonconformancesLoading()) {
    on<NonconformancesStarted>(_onStarted);
    on<NonconformancesRefreshed>(_onRefreshed);
    on<NonconformancesSiteSelected>(_onSiteSelected);
    on<NonconformancesOrgUnitFilterSet>(_onOrgUnitFilterSet);
    on<NonconformancesStatusFilterChanged>(_onStatusFilterChanged);
    on<NonconformancesDefectCodeFilterChanged>(_onDefectCodeFilterChanged);
    on<NonconformancesProductFilterChanged>(_onProductFilterChanged);
    on<NonconformancesSeverityFilterChanged>(_onSeverityFilterChanged);
    on<NonconformancesDateRangeChanged>(_onDateRangeChanged);
    on<NonconformancesFiltersCleared>(_onFiltersCleared);
    on<NonconformanceRecordConfirmed>(_onRecordConfirmed);
  }

  final QualityApi _api;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(NonconformancesStarted event, Emitter<NonconformancesState> emit) async {
    emit(const NonconformancesLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const NonconformancesUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _people.fetchSites(token);
      // The catalogue reads are what make every filter a choice rather than a
      // text box (ADR-0023), so a failure here is the page failing rather than
      // a control degrading: an unreadable catalogue must not be replaced by
      // free text.
      final products = await _api.fetchProducts(token);
      final defectCodes = await _api.fetchDefectCodes(token);
      if (sites.isEmpty) {
        emit(
          NonconformancesLoaded(
            sites: const [],
            siteId: null,
            filters: const NonconformanceFilters(),
            nonconformances: const [],
            truncated: false,
            products: products,
            defectCodes: defectCodes,
          ),
        );
        return;
      }
      await _readSite(
        sites,
        sites.first.id,
        const NonconformanceFilters(),
        products,
        defectCodes,
        emit,
      );
    } on QualityApiException catch (error) {
      emit(NonconformancesUnavailable(message: error.message));
    }
  }

  // A re-read that keeps the Site and the filters, and paints the stale list
  // until the new one lands: a Screen entered from a detail must not flash a
  // skeleton over rows it is still showing.
  Future<void> _onRefreshed(
    NonconformancesRefreshed event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _onSiteSelected(
    NonconformancesSiteSelected event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    // A Site change clears the filters: an Org Unit belongs to the Site it was
    // chosen in, and a Defect code filter is not wrong elsewhere but the area
    // one certainly is.
    await _readSite(
      settled.sites,
      event.siteId,
      const NonconformanceFilters(),
      settled.products,
      settled.defectCodes,
      emit,
    );
  }

  Future<void> _onOrgUnitFilterSet(
    NonconformancesOrgUnitFilterSet event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    await _applyFilters(
      settled,
      settled.filters.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.name),
      emit,
    );
  }

  Future<void> _onStatusFilterChanged(
    NonconformancesStatusFilterChanged event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    final moved = event.status == null
        ? settled.filters.copyWith(clearStatus: true)
        : settled.filters.copyWith(status: event.status);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onDefectCodeFilterChanged(
    NonconformancesDefectCodeFilterChanged event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    final moved = event.defectCodeId == null
        ? settled.filters.copyWith(clearDefectCode: true)
        : settled.filters.copyWith(defectCodeId: event.defectCodeId);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onProductFilterChanged(
    NonconformancesProductFilterChanged event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    final moved = event.productId == null
        ? settled.filters.copyWith(clearProduct: true)
        : settled.filters.copyWith(productId: event.productId);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onSeverityFilterChanged(
    NonconformancesSeverityFilterChanged event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    final moved = event.severity == null
        ? settled.filters.copyWith(clearSeverity: true)
        : settled.filters.copyWith(severity: event.severity);
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onDateRangeChanged(
    NonconformancesDateRangeChanged event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    var moved = settled.filters;
    if (event.clearFrom) {
      moved = moved.copyWith(clearFrom: true);
    } else if (event.from != null) {
      moved = moved.copyWith(from: event.from);
    }
    if (event.clearTo) {
      moved = moved.copyWith(clearTo: true);
    } else if (event.to != null) {
      moved = moved.copyWith(to: event.to);
    }
    await _applyFilters(settled, moved, emit);
  }

  Future<void> _onFiltersCleared(
    NonconformancesFiltersCleared event,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = state;
    if (settled is! NonconformancesLoaded) return;
    await _applyFilters(settled, const NonconformanceFilters(), emit);
  }

  Future<void> _readSite(
    List<Site> sites,
    String? siteId,
    NonconformanceFilters filters,
    List<Product> products,
    List<DefectCode> defectCodes,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = NonconformancesLoaded(
      sites: sites,
      siteId: siteId,
      filters: filters,
      nonconformances: const [],
      truncated: false,
      products: products,
      defectCodes: defectCodes,
    );
    emit(settled);
    await _readList(settled, siteId, emit);
  }

  /// Puts a filter set in force, then reads with it.
  ///
  /// The emit before the read is what makes the controls show what was chosen
  /// — the Screen's own state carries the filters — and it is also what makes
  /// "this filter matched nothing" and "this Site has nothing" two different
  /// stories, since the second turns on whether any filter is set.
  Future<void> _applyFilters(
    NonconformancesLoaded current,
    NonconformanceFilters filters,
    Emitter<NonconformancesState> emit,
  ) async {
    final settled = current.copyWith(filters: filters);
    emit(settled);
    await _readList(settled, settled.siteId, emit);
  }

  /// Reads a Site's register with the filters [current] carries, and answers
  /// that same state with the rows the server sent — so the filters the
  /// request used and the filters the Screen shows cannot drift apart.
  Future<void> _readList(
    NonconformancesLoaded current,
    String? siteId,
    Emitter<NonconformancesState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const NonconformancesUnavailable(message: signedOutMessage));
      return;
    }
    if (siteId == null) {
      emit(current.copyWith(nonconformances: const [], truncated: false));
      return;
    }
    try {
      final page = await _api.fetchNonconformances(token, siteId, filters: current.filters);
      emit(
        current.copyWith(
          siteId: siteId,
          nonconformances: page.nonconformances,
          truncated: page.truncated,
        ),
      );
    } on QualityApiException catch (error) {
      emit(NonconformancesUnavailable(message: error.message));
    }
  }

  Future<void> _onRecordConfirmed(
    NonconformanceRecordConfirmed event,
    Emitter<NonconformancesState> emit,
  ) async {
    final current = state;
    if (current is! NonconformancesLoaded || current.isRecording) return;
    final siteId = current.siteId;
    if (siteId == null) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(recordFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRecording: true, recordFailure: null));
    try {
      await _api.recordNonconformance(
        token,
        siteId,
        orgUnitId: event.orgUnitId,
        productId: event.productId,
        defectCodeId: event.defectCodeId,
        detectionPoint: event.detectionPoint,
        quantity: event.quantity,
        severity: event.severity,
        assetId: event.assetId,
        lotRef: event.lotRef,
        description: event.description,
        immediateContainment: event.immediateContainment,
        detectedAt: event.detectedAt,
      );
      final settled = state;
      if (settled is! NonconformancesLoaded) return;
      emit(settled.copyWith(isRecording: false));
      final current = state;
      if (current is! NonconformancesLoaded) return;
      await _readList(current, siteId, emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! NonconformancesLoaded) return;
      emit(settled.copyWith(isRecording: false, recordFailure: error.message));
    }
  }
}
