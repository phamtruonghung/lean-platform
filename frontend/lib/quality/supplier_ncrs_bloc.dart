/// The supplier NCR register's own state (issue #215): a Site's NCRs, the
/// filters the ticket names, the four catalogues the record form chooses from,
/// and the recording of a new one.
///
/// Route-scoped and shared by the whole supplier NCR surface, the same shape
/// `SupplierNcrsBloc`'s complaint counterpart keeps: one `ShellRoute` creates it
/// once and the register, the record form's own address and the detail Screen
/// all read it, so the Site and the filters a caller picked survive opening an
/// NCR and coming back.
///
/// Every filter sends a request rather than hiding rows client-side — that is
/// what the server's own indexes and its ltree walk are for, and a filter that
/// narrowed the client's copy would silently disagree with the count once the
/// list is capped. The chose-not-typed rule (ADR-0023) is what the catalogues
/// are here for: the Supplier, the Product and the Defect code are all chosen
/// from what the server offers, and the unit of measure comes from Maintenance's
/// own address because a quantity must be in a unit the plant uses.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance.dart';
import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'defect_code.dart';
import 'product.dart';
import 'quality_api.dart';
import 'supplier.dart';
import 'supplier_ncr.dart';

sealed class SupplierNcrsEvent {
  const SupplierNcrsEvent();
}

/// Load the register: the Sites, the catalogues the form chooses from, and the
/// Site's supplier NCRs. Also the retry a failed load offers.
class SupplierNcrsStarted extends SupplierNcrsEvent {
  const SupplierNcrsStarted();
}

/// Re-read the list whenever the register is entered (issue #183's own
/// reasoning): the `ShellRoute` keeps this Bloc alive while a caller reads an
/// NCR and comes back, so a Screen that only read on `SupplierNcrsStarted` would
/// paint the list as it was when they left.
class SupplierNcrsRefreshed extends SupplierNcrsEvent {
  const SupplierNcrsRefreshed();
}

/// A different Site.
class SupplierNcrsSiteSelected extends SupplierNcrsEvent {
  const SupplierNcrsSiteSelected(this.siteId);

  final String siteId;
}

/// Narrow to one Org Unit and everything beneath it. The name rides along so
/// the button can say which area is on screen without a second read.
class SupplierNcrsOrgUnitFilterSet extends SupplierNcrsEvent {
  const SupplierNcrsOrgUnitFilterSet({required this.orgUnitId, required this.name});

  final String orgUnitId;
  final String name;
}

/// Narrow to one Supplier's NCRs — the ticket's own first filter. The name rides
/// along for the same reason the Org Unit's does.
class SupplierNcrsSupplierFilterSet extends SupplierNcrsEvent {
  const SupplierNcrsSupplierFilterSet({required this.supplierId, required this.name});

  final String supplierId;
  final String name;
}

class SupplierNcrsStatusFilterChanged extends SupplierNcrsEvent {
  const SupplierNcrsStatusFilterChanged(this.status);

  final String? status;
}

class SupplierNcrsFiltersCleared extends SupplierNcrsEvent {
  const SupplierNcrsFiltersCleared();
}

/// The record form has decided: a whole new supplier NCR. Same contract as
/// `SupplierNcrRecordConfirmed`'s complaint counterpart — the dialog decides,
/// the Bloc only ever sees a decision already made, and the refusal comes back
/// as `recordFailure` so the dialog stays open with its values.
class SupplierNcrRecordConfirmed extends SupplierNcrsEvent {
  const SupplierNcrRecordConfirmed({
    required this.orgUnitId,
    required this.supplierId,
    required this.quantity,
    required this.uomCode,
    this.productId,
    this.defectCodeId,
    this.incomingLotRef,
    this.purchaseRef,
    this.description,
    this.responseDueDate,
  });

  final String orgUnitId;
  final String supplierId;
  final num quantity;

  /// The unit the quantity is counted in. The form always names one, taken from
  /// the chosen Product or chosen by the caller for a lot with no Product yet —
  /// the server takes the Product's own when both are sent, and needs one when
  /// only the caller's is.
  final String uomCode;

  final String? productId;
  final String? defectCodeId;
  final String? incomingLotRef;
  final String? purchaseRef;
  final String? description;
  final String? responseDueDate;
}

sealed class SupplierNcrsState {
  const SupplierNcrsState();
}

class SupplierNcrsLoading extends SupplierNcrsState {
  const SupplierNcrsLoading();
}

class SupplierNcrsUnavailable extends SupplierNcrsState {
  const SupplierNcrsUnavailable({required this.message});

  final String message;
}

class SupplierNcrsLoaded extends SupplierNcrsState {
  const SupplierNcrsLoaded({
    required this.sites,
    required this.siteId,
    required this.filters,
    required this.supplierNcrs,
    required this.truncated,
    required this.suppliers,
    required this.products,
    required this.defectCodes,
    required this.unitsOfMeasure,
    this.isRecording = false,
    this.recordFailure,
  });

  final List<Site> sites;

  /// The Site on screen, or null when the caller can see none — in which case
  /// there is no register to read and the Screen says so.
  final String? siteId;

  final SupplierNcrFilters filters;
  final List<SupplierNcr> supplierNcrs;
  final bool truncated;

  /// The catalogues the record form chooses from, read once with the register
  /// rather than per control, so opening the form issues no request for them at
  /// all.
  final List<Supplier> suppliers;
  final List<Product> products;
  final List<DefectCode> defectCodes;

  /// The units of measure the plant uses, read from Maintenance's own address —
  /// see quality_api.dart's own header for why it is not republished under
  /// `/api/quality`. Needed because a supplier NCR's quantity must be in a unit
  /// the plant uses, and a lot with no Product named has no unit to inherit.
  final List<UnitOfMeasure> unitsOfMeasure;

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

  SupplierNcrsLoaded copyWith({
    String? siteId,
    SupplierNcrFilters? filters,
    List<SupplierNcr>? supplierNcrs,
    bool? truncated,
    bool? isRecording,
    String? recordFailure,
  }) =>
      SupplierNcrsLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        filters: filters ?? this.filters,
        supplierNcrs: supplierNcrs ?? this.supplierNcrs,
        truncated: truncated ?? this.truncated,
        suppliers: suppliers,
        products: products,
        defectCodes: defectCodes,
        unitsOfMeasure: unitsOfMeasure,
        isRecording: isRecording ?? this.isRecording,
        // Always overwritten, never carried forward — the same rule
        // `SupplierNcrsLoaded`'s complaint counterpart gives its own failure.
        recordFailure: recordFailure,
      );
}

class SupplierNcrsBloc extends Bloc<SupplierNcrsEvent, SupplierNcrsState> {
  SupplierNcrsBloc({
    required QualityApi qualityApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = qualityApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const SupplierNcrsLoading()) {
    on<SupplierNcrsStarted>(_onStarted);
    on<SupplierNcrsRefreshed>(_onRefreshed);
    on<SupplierNcrsSiteSelected>(_onSiteSelected);
    on<SupplierNcrsOrgUnitFilterSet>(_onOrgUnitFilterSet);
    on<SupplierNcrsSupplierFilterSet>(_onSupplierFilterSet);
    on<SupplierNcrsStatusFilterChanged>(_onStatusFilterChanged);
    on<SupplierNcrsFiltersCleared>(_onFiltersCleared);
    on<SupplierNcrRecordConfirmed>(_onRecordConfirmed);
  }

  final QualityApi _api;
  final PeopleApi _people;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onStarted(SupplierNcrsStarted event, Emitter<SupplierNcrsState> emit) async {
    emit(const SupplierNcrsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SupplierNcrsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _people.fetchSites(token);
      // The catalogue reads are what make every choice in the form a choice
      // rather than a text box (ADR-0023), so a failure here is the page
      // failing rather than a control degrading: an unreadable catalogue must
      // not be replaced by free text.
      final suppliers = await _api.fetchSuppliers(token);
      final products = await _api.fetchProducts(token);
      final defectCodes = await _api.fetchDefectCodes(token);
      final unitsOfMeasure = await _api.fetchUnitsOfMeasure(token);
      if (sites.isEmpty) {
        emit(
          SupplierNcrsLoaded(
            sites: const [],
            siteId: null,
            filters: const SupplierNcrFilters(),
            supplierNcrs: const [],
            truncated: false,
            suppliers: suppliers,
            products: products,
            defectCodes: defectCodes,
            unitsOfMeasure: unitsOfMeasure,
          ),
        );
        return;
      }
      await _readSite(
        sites,
        sites.first.id,
        const SupplierNcrFilters(),
        suppliers,
        products,
        defectCodes,
        unitsOfMeasure,
        emit,
      );
    } on QualityApiException catch (error) {
      emit(SupplierNcrsUnavailable(message: error.message));
    }
  }

  // A re-read that keeps the Site and the filters, and paints the stale list
  // until the new one lands: a Screen entered from a detail must not flash a
  // skeleton over rows it is still showing.
  Future<void> _onRefreshed(
    SupplierNcrsRefreshed event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final settled = state;
    if (settled is! SupplierNcrsLoaded) return;
    await _readList(settled, settled.siteId, emit);
  }

  Future<void> _onSiteSelected(
    SupplierNcrsSiteSelected event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final settled = state;
    if (settled is! SupplierNcrsLoaded) return;
    // A Site change clears the filters: an Org Unit belongs to the Site it was
    // chosen in.
    await _readSite(
      settled.sites,
      event.siteId,
      const SupplierNcrFilters(),
      settled.suppliers,
      settled.products,
      settled.defectCodes,
      settled.unitsOfMeasure,
      emit,
    );
  }

  Future<void> _onOrgUnitFilterSet(
    SupplierNcrsOrgUnitFilterSet event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final settled = state;
    if (settled is! SupplierNcrsLoaded) return;
    await _applyFilters(
      settled,
      settled.filters.copyWith(orgUnitId: event.orgUnitId, orgUnitName: event.name),
      emit,
    );
  }

  Future<void> _onSupplierFilterSet(
    SupplierNcrsSupplierFilterSet event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final settled = state;
    if (settled is! SupplierNcrsLoaded) return;
    await _applyFilters(
      settled,
      settled.filters.copyWith(supplierId: event.supplierId, supplierName: event.name),
      emit,
    );
  }

  Future<void> _onStatusFilterChanged(
    SupplierNcrsStatusFilterChanged event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final settled = state;
    if (settled is! SupplierNcrsLoaded) return;
    await _applyFilters(
      settled,
      event.status == null
          ? settled.filters.copyWith(clearStatus: true)
          : settled.filters.copyWith(status: event.status),
      emit,
    );
  }

  Future<void> _onFiltersCleared(
    SupplierNcrsFiltersCleared event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final settled = state;
    if (settled is! SupplierNcrsLoaded) return;
    await _applyFilters(settled, const SupplierNcrFilters(), emit);
  }

  Future<void> _onRecordConfirmed(
    SupplierNcrRecordConfirmed event,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final current = state;
    if (current is! SupplierNcrsLoaded || current.isRecording) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(recordFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isRecording: true, recordFailure: null));
    try {
      await _api.recordSupplierNcr(
        token,
        current.siteId!,
        orgUnitId: event.orgUnitId,
        supplierId: event.supplierId,
        quantity: event.quantity,
        uomCode: event.uomCode,
        productId: event.productId,
        defectCodeId: event.defectCodeId,
        incomingLotRef: event.incomingLotRef,
        purchaseRef: event.purchaseRef,
        description: event.description,
        responseDueDate: event.responseDueDate,
      );
      await _readList(current, current.siteId, emit);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SupplierNcrsLoaded) return;
      emit(settled.copyWith(isRecording: false, recordFailure: error.message));
    }
  }

  Future<void> _applyFilters(
    SupplierNcrsLoaded settled,
    SupplierNcrFilters filters,
    Emitter<SupplierNcrsState> emit,
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
    SupplierNcrFilters filters,
    List<Supplier> suppliers,
    List<Product> products,
    List<DefectCode> defectCodes,
    List<UnitOfMeasure> unitsOfMeasure,
    Emitter<SupplierNcrsState> emit,
  ) async {
    // The new Site's state first, with the rows cleared: the old Site's NCRs
    // must not be painted under the new Site's chooser while the read is in
    // flight.
    final reading = SupplierNcrsLoaded(
      sites: sites,
      siteId: siteId,
      filters: filters,
      supplierNcrs: const [],
      truncated: false,
      suppliers: suppliers,
      products: products,
      defectCodes: defectCodes,
      unitsOfMeasure: unitsOfMeasure,
    );
    emit(reading);
    await _readList(reading, siteId, emit);
  }

  Future<void> _readList(
    SupplierNcrsLoaded settled,
    String? siteId,
    Emitter<SupplierNcrsState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SupplierNcrsUnavailable(message: signedOutMessage));
      return;
    }
    if (siteId == null) return;
    try {
      final register = await _api.fetchSupplierNcrs(token, siteId, filters: settled.filters);
      final current = state;
      if (current is! SupplierNcrsLoaded) return;
      emit(
        current.copyWith(
          supplierNcrs: register.supplierNcrs,
          truncated: register.truncated,
          isRecording: false,
        ),
      );
    } on QualityApiException catch (error) {
      emit(SupplierNcrsUnavailable(message: error.message));
    }
  }
}
