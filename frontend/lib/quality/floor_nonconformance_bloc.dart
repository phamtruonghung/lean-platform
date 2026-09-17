/// Recording a Non-conformance at a shared floor device (issue #207,
/// ADR-0016) — the state behind the one flow the floor surface offers that is
/// not about work orders.
///
/// Like [FloorBloc] this Bloc is driven by [FloorDeviceGateway] and holds no
/// `AccountBloc` anywhere: a device is not a person and the surface has to
/// work where nobody can sign in. Unlike [FloorBloc] it also takes
/// [QualityApi], because the record being written is Quality's — the client
/// mirrors the Module seam (ADR-0012), and
/// `POST /api/quality/floor/nonconformances` is Quality's address.
///
/// The individual identification is deliberately absent from every state
/// object, exactly as [FloorBloc] keeps it: the employee number and PIN arrive
/// on the submit event, the handler exchanges them for a token in a local
/// variable, uses that token for the one request, and drops it. A Screen that
/// keeps the last person's identification is the drift ADR-0016 exists to
/// prevent.
///
/// The identification exchange itself is Maintenance's, and that is not an
/// accident of history: `POST /api/maintenance/floor/identify` is the frozen
/// floor address the people Module's route answers at (issue #201 kept the
/// URL where deployed devices were pointed), and [MaintenanceApi] is the
/// client that reaches it. This Bloc therefore asks that client for the token
/// and Quality's for the record — one HAT per Module rather than a second copy
/// of the identify call under a Quality name.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance_api.dart';
import '../platform/floor_device_gateway.dart';
import 'defect_code.dart';
import 'product.dart';
import 'quality_api.dart';

sealed class FloorNonconformanceEvent {
  const FloorNonconformanceEvent();
}

/// Read the two catalogues the operator chooses from, and the retry a failed
/// read offers.
class FloorNonconformanceStarted extends FloorNonconformanceEvent {
  const FloorNonconformanceStarted();
}

/// The operator has chosen what was found and confirmed who they are. The PIN
/// is used for this one action and never stored.
class FloorNonconformanceSubmitted extends FloorNonconformanceEvent {
  const FloorNonconformanceSubmitted({
    required this.productId,
    required this.defectCodeId,
    required this.detectionPoint,
    required this.quantity,
    required this.employeeNo,
    required this.pin,
    this.lotRef,
    this.description,
    this.immediateContainment,
  });

  final String productId;
  final String defectCodeId;
  final String detectionPoint;
  final String quantity;
  final String employeeNo;
  final String pin;
  final String? lotRef;
  final String? description;
  final String? immediateContainment;
}

sealed class FloorNonconformanceState {
  const FloorNonconformanceState();
}

/// The two catalogues are in flight and the form cannot be filled in yet.
class FloorNonconformanceLoading extends FloorNonconformanceState {
  const FloorNonconformanceLoading();
}

class FloorNonconformanceReady extends FloorNonconformanceState {
  const FloorNonconformanceReady({
    required this.products,
    required this.defectCodes,
    this.isSubmitting = false,
    this.failure,
    this.notice,
  });

  /// What the operator may choose from — active Products and Defect codes
  /// only, which is what the floor read offers: a retired one cannot be
  /// recorded against at all.
  final List<Product> products;
  final List<DefectCode> defectCodes;

  /// A submit is in flight; the form's controls are disabled while it settles.
  final bool isSubmitting;

  /// Why the last submit did not land, for the dialog to report.
  final String? failure;

  /// What a landed record has to say for itself — the number the Platform
  /// issued it. The dialog closes on this and the floor Screen shows it.
  final String? notice;

  FloorNonconformanceReady copyWith({
    bool? isSubmitting,
    String? failure,
    String? notice,
  }) =>
      FloorNonconformanceReady(
        products: products,
        defectCodes: defectCodes,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        // Cleared on every emit that does not set them, deliberately: a stale
        // refusal from a previous attempt must not linger onto a later one.
        failure: failure,
        notice: notice,
      );
}

class FloorNonconformanceUnavailable extends FloorNonconformanceState {
  const FloorNonconformanceUnavailable({required this.message});
  final String message;
}

class FloorNonconformanceBloc
    extends Bloc<FloorNonconformanceEvent, FloorNonconformanceState> {
  FloorNonconformanceBloc({
    required QualityApi qualityApi,
    required MaintenanceApi maintenanceApi,
    required FloorDeviceGateway floorDeviceGateway,
    required this.orgUnitId,
  })  : _quality = qualityApi,
        _maintenance = maintenanceApi,
        _device = floorDeviceGateway,
        super(const FloorNonconformanceLoading()) {
    on<FloorNonconformanceStarted>(_onStarted);
    on<FloorNonconformanceSubmitted>(_onSubmitted);
  }

  final QualityApi _quality;
  final MaintenanceApi _maintenance;
  final FloorDeviceGateway _device;

  /// The Org Unit the device is registered at — where the record is filed by
  /// default, and the top of everything the device may file one against. It
  /// comes from the floor read's own context rather than from the operator, so
  /// a device can never be talked into recording somewhere else.
  final String orgUnitId;

  static const String notRegisteredMessage =
      'This device is not registered. Ask an administrator to register it against an Org Unit.';

  Future<void> _onStarted(
    FloorNonconformanceStarted event,
    Emitter<FloorNonconformanceState> emit,
  ) async {
    emit(const FloorNonconformanceLoading());
    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(const FloorNonconformanceUnavailable(message: notRegisteredMessage));
      return;
    }
    try {
      final products = await _quality.fetchFloorProducts(credential);
      final defectCodes = await _quality.fetchFloorDefectCodes(credential);
      emit(FloorNonconformanceReady(products: products, defectCodes: defectCodes));
    } on QualityApiException catch (error) {
      emit(FloorNonconformanceUnavailable(message: error.message));
    }
  }

  Future<void> _onSubmitted(
    FloorNonconformanceSubmitted event,
    Emitter<FloorNonconformanceState> emit,
  ) async {
    final current = state;
    if (current is! FloorNonconformanceReady || current.isSubmitting) return;

    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(current.copyWith(failure: notRegisteredMessage));
      return;
    }

    emit(current.copyWith(isSubmitting: true));
    try {
      // Identify first, then write: the record is attributed to whoever this
      // exchange resolves to, so a wrong PIN means nothing is written at all.
      final identification = await _maintenance.identifyTechnician(
        credential,
        employeeNo: event.employeeNo,
        pin: event.pin,
      );
      final nonconformance = await _quality.recordFloorNonconformance(
        credential,
        identification.token,
        orgUnitId: orgUnitId,
        productId: event.productId,
        defectCodeId: event.defectCodeId,
        detectionPoint: event.detectionPoint,
        quantity: num.parse(event.quantity.trim()),
        lotRef: event.lotRef,
        description: event.description,
        immediateContainment: event.immediateContainment,
      );
      final settled = state;
      if (settled is! FloorNonconformanceReady) return;
      emit(
        settled.copyWith(
          isSubmitting: false,
          notice: '${nonconformance.issueNo} recorded by ${identification.employeeName}.',
        ),
      );
    } on MaintenanceApiException catch (error) {
      _fail(emit, error.message);
    } on QualityApiException catch (error) {
      _fail(emit, error.message);
    }
  }

  void _fail(Emitter<FloorNonconformanceState> emit, String message) {
    final settled = state;
    if (settled is! FloorNonconformanceReady) return;
    emit(settled.copyWith(isSubmitting: false, failure: message));
  }
}
