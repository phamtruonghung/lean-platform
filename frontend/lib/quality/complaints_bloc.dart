/// The customer complaint register's own state (issue #214): a Site's
/// complaints, the two filters the ticket names, the three catalogues the
/// record form chooses from, and the recording of a new one.
///
/// Route-scoped and shared by the whole complaint surface, the same shape
/// `NonconformancesBloc` keeps: one `ShellRoute` creates it once and the
/// register, the record form's own address and the detail Screen all read it,
/// so the Site and the filters a caller picked survive opening a complaint and
/// coming back.
///
/// Every filter sends a request rather than hiding rows client-side — that is
/// what the server's own indexes and its ltree walk are for, and a filter that
/// narrowed the client's copy would silently disagree with the count once the
/// list is capped. The chose-not-typed rule (ADR-0023) is what the three
/// catalogues are here for: the Customer, the Product and the Defect code are
/// all chosen from what the server offers.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'customer.dart';
import 'customer_complaint.dart';
import 'defect_code.dart';
import 'product.dart';
import 'quality_api.dart';

sealed class ComplaintsEvent {
  const ComplaintsEvent();
}

/// Load the register: the Sites, the three catalogues the form chooses from,
/// and the Site's complaints. Also the retry a failed load offers.
class ComplaintsStarted extends ComplaintsEvent {
  const ComplaintsStarted();
}

/// Re-read the list whenever the register is entered (issue #183's own
/// reasoning): the `ShellRoute` keeps this Bloc alive while a caller reads a
/// complaint and comes back, so a Screen that only read on `ComplaintsStarted`
/// would paint the list as it was when they left.
class ComplaintsRefreshed extends ComplaintsEvent {
  const ComplaintsRefreshed();
}

/// A different Site.
class ComplaintsSiteSelected extends ComplaintsEvent {
  const ComplaintsSiteSelected(this.siteId);

  final String siteId;
}

/// Narrow to one Org Unit and everything beneath it. The name rides along so
/// the button can say which area is on screen without a second read.
class ComplaintsOrgUnitFilterSet extends ComplaintsEvent {
  const ComplaintsOrgUnitFilterSet({required this.orgUnitId, required this.name});

  final String orgUnitId;
  final String name;
}

class ComplaintsStatusFilterChanged extends ComplaintsEvent {
  const ComplaintsStatusFilterChanged(this.status);

  final String? status;
}

class ComplaintsFiltersCleared extends ComplaintsEvent {
  const ComplaintsFiltersCleared();
}

/// The record form has decided: a whole new complaint. Same contract as
/// `NonconformanceRecordConfirmed` — the dialog decides, the Bloc only ever
/// sees a decision already made, and the refusal comes back as `recordFailure`
/// so the dialog stays open with its values.
class ComplaintRecordConfirmed extends ComplaintsEvent {
  const ComplaintRecordConfirmed({
    required this.orgUnitId,
    required this.customerId,
    required this.productId,
    required this.description,
    this.defectCodeId,
    this.quantity,
    this.responseDueDate,
    this.isWarranty = false,
  });

  final String orgUnitId;
  final String customerId;
  final String productId;
  final String description;
  final String? defectCodeId;
  final num? quantity;
  final String? responseDueDate;
  final bool isWarranty;
}

sealed class ComplaintsState {
  const ComplaintsState();
}

class ComplaintsLoading extends ComplaintsState {
  const ComplaintsLoading();
}

class ComplaintsUnavailable extends ComplaintsState {
  const ComplaintsUnavailable({required this.message});

  final String message;
}

class ComplaintsLoaded extends ComplaintsState {
  const ComplaintsLoaded({
    required this.sites,
    required this.siteId,
    required this.filters,
    required this.complaints,
    required this.truncated,
    required this.customers,
    required this.products,
    required this.defectCodes,
    this.isRecording = false,
    this.recordFailure,
  });

  final List<Site> sites;

  /// The Site on screen, or null when the caller can see none — in which case
  /// there is no register to read and the Screen says so.
  final String? siteId;

  final ComplaintFilters filters;
  final List<CustomerComplaint> complaints;
  final bool truncated;

  /// The three catalogues the record form chooses from, read once with the
  /// register rather than per control, so opening the form issues no request
  /// for them at all.
  final List<Customer> customers;
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

  ComplaintsLoaded copyWith({
    String? siteId,
    ComplaintFilters? filters,
    List<CustomerComplaint>? complaints,
    bool? truncated,
    bool? isRecording,
    String? recordFailure,
  }) =>
      ComplaintsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        filters: filters ?? this.filters,
        complaints: complaints ?? this.complaints,
        truncated: truncated ?? this.truncated,
        customers: customers,
        products: products,
        defectCodes: defectCodes,
        isRecording: isRecording ?? this.isRecording,
        // Always overwritten, never carried forward — the same rule
        // `NonconformancesLoaded.copyWith` gives its own failure.
        recordFailure: recordFailure,
      );
}

class ComplaintsBloc extends Bloc<ComplaintsEvent, ComplaintsState> {
  ComplaintsBloc({
    required QualityApi qualityApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = qualityApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const ComplaintsLoading()) {
    on<ComplaintsStarted>(_onStarted);
    on<ComplaintsRefreshed>(_onRefreshed);
    on<ComplaintsSiteSelected>(_onSiteSelected);
    on<ComplaintsOrgUnitFilterSet>(_onOrgUnitFilterSet);
    on<ComplaintsStatusFilterChanged>(_onStatusFilterChanged);
    on<ComplaintsFiltersCleared>(_onFiltersCleared);
    on<ComplaintRecordConfirmed>(_onRecordConfirmed);
  }

  final QualityApi _api;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(ComplaintsStarted event, Emitter<ComplaintsState> emit) async {
    emit(const ComplaintsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ComplaintsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _people.fetchSites(token);
      // The catalogue reads are what make every choice in the form a choice
      // rather than a text box (ADR-0023), so a failure here is the page
      // failing rather than a control degrading: an unreadable catalogue must
      // not be replaced by free text.
      final customers = await _api.fetchCustomers(token);
      final products = await _api.fetchProducts(token);
      final defectCodes = await _api.fetchDefectCodes(token);
      if (sites.isEmpty) {
        emit(
          ComplaintsLoaded(
            sites: const [],
            siteId: null,
            filters: const ComplaintFilters(),
            complaints: const [],
            truncated: false,
            customers: customers,
            products: products,
            defectCodes: defectCodes,
          ),
        );
        return;
      }
      await _readSite(
        sites,
        sites.first.id,
        const ComplaintFilters(),
        customers,
        products,
        defectCodes,
        emit,
      );
    } on QualityApiException catch (error) {
      emit(ComplaintsUnavailable(message: error.message));
    }
  }

  // A re-read that keeps the Site and the filters, and paints the stale list
  // until the new one lands: a Screen entered from a detail must not flash a
  // skeleton over rows it is still showing.
  Future<void> _onRefreshed(
    ComplaintsRefreshed event,
    Emitter<ComplaintsState> emit,
  ) async {
    final settled = state;
    if (settled is! ComplaintsLoaded) return;
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _onSiteSelected(
    ComplaintsSiteSelected event,
    Emitter<ComplaintsState> emit,
  ) async {
    final settled = state;
    if (settled is! ComplaintsLoaded) return;
    // A Site change clears the filters: an Org Unit belongs to the Site it was
    // chosen in.
    await _readSite(
      settled.sites,
      event.siteId,
      const ComplaintFilters(),
      settled.customers,
      settled.products,
      settled.defectCodes,
      emit,
    );
  }

  Future<void> _onOrgUnitFilterSet(
    ComplaintsOrgUnitFilterSet event,
    Emitter<ComplaintsState> emit,
  ) async {
    final settled = state;
    if (settled is! ComplaintsLoaded) return;
    await _applyFilters(
      settled,
      settled.filters.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.name),
      emit,
    );
  }

  Future<void> _onStatusFilterChanged(
    ComplaintsStatusFilterChanged event,
    Emitter<ComplaintsState> emit,
  ) async {
    final settled = state;
    if (settled is! ComplaintsLoaded) return;
    await _applyFilters(
      settled,
      event.status == null
          ? settled.filters.copyWith(clearStatus: true)
          : settled.filters.copyWith(status: event.status),
      emit,
    );
  }

  Future<void> _onFiltersCleared(
    ComplaintsFiltersCleared event,
    Emitter<ComplaintsState> emit,
  ) async {
    final settled = state;
    if (settled is! ComplaintsLoaded) return;
    await _applyFilters(settled, const ComplaintFilters(), emit);
  }

  Future<void> _onRecordConfirmed(
    ComplaintRecordConfirmed event,
    Emitter<ComplaintsState> emit,
  ) async {
    final current = state;
    if (current is! ComplaintsLoaded || current.isRecording) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(recordFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRecording: true, recordFailure: null));
    try {
      await _api.recordComplaint(
        token,
        current.siteId!,
        orgUnitId: event.orgUnitId,
        customerId: event.customerId,
        productId: event.productId,
        description: event.description,
        defectCodeId: event.defectCodeId,
        quantity: event.quantity,
        responseDueDate: event.responseDueDate,
        isWarranty: event.isWarranty,
      );
      await _readList(current, current.siteId, emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! ComplaintsLoaded) return;
      emit(settled.copyWith(isRecording: false, recordFailure: error.message));
    }
  }

  Future<void> _applyFilters(
    ComplaintsLoaded settled,
    ComplaintFilters filters,
    Emitter<ComplaintsState> emit,
  ) async {
    // The *new* filters are what the read carries: the state emitted first is
    // the one `_readList` reads them off, so a filter change narrows the request
    // rather than narrowing only what the Screen shows.
    final updated = settled.copyWith(filters: filters, isRecording: false);
    emit(updated);
    await _readList(updated, updated.siteId, emit);
  }

  Future<void> _readSite(
    List<Site> sites,
    String? siteId,
    ComplaintFilters filters,
    List<Customer> customers,
    List<Product> products,
    List<DefectCode> defectCodes,
    Emitter<ComplaintsState> emit,
  ) async {
    // The new Site's state first, with the rows cleared: the old Site's
    // complaints must not be painted under the new Site's chooser while the
    // read is in flight.
    final reading = ComplaintsLoaded(
      sites: sites,
      siteId: siteId,
      filters: filters,
      complaints: const [],
      truncated: false,
      customers: customers,
      products: products,
      defectCodes: defectCodes,
    );
    emit(reading);
    await _readList(reading, siteId, emit);
  }

  Future<void> _readList(
    ComplaintsLoaded settled,
    String? siteId,
    Emitter<ComplaintsState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const ComplaintsUnavailable(message: signedOutMessage));
      return;
    }
    if (siteId == null) return;
    try {
      final register = await _api.fetchComplaints(token, siteId, filters: settled.filters);
      final current = state;
      if (current is! ComplaintsLoaded) return;
      emit(
        current.copyWith(
          complaints: register.complaints,
          truncated: register.truncated,
          isRecording: false,
        ),
      );
    } on QualityApiException catch (error) {
      emit(ComplaintsUnavailable(message: error.message));
    }
  }
}
