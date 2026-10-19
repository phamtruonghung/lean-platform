/// A Trainee with no Account answering at the shared floor device (issue #293,
/// ADR-0016, ADR-0043): identify with an Employee number and PIN, read the
/// trainings waiting on that Employee at this device, and confirm or decline
/// each one.
///
/// Driven by [FloorDeviceGateway] and holding no `AccountBloc` anywhere: a
/// device is not a person, and most of a plant cannot sign in. The two calls
/// are People's own (`PeopleApi`); the identification exchange is the floor
/// surface's (`MaintenanceApi.identifyTechnician`), the one path every floor
/// flow identifies through.
///
/// Unlike the one-action floor flows, this one holds the short-lived
/// identification for as long as the dialog that owns this Bloc is open,
/// because answering means reading a list and then acting on several rows. It
/// is a private field and never on a state object, and the Bloc dies with the
/// dialog, so walking away does not leave the next person acting as the last
/// one: the token expires within minutes and an expired one sends the
/// Employee back to identify again.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../maintenance/maintenance_api.dart';
import '../people_api.dart';
import '../platform/floor_device_gateway.dart';
import 'training_record.dart';

sealed class FloorTrainingEvent {
  const FloorTrainingEvent();
}

/// The Employee has typed who they are. The PIN is used for this one exchange
/// and never stored.
class FloorTrainingIdentified extends FloorTrainingEvent {
  const FloorTrainingIdentified({required this.employeeNo, required this.pin});

  final String employeeNo;
  final String pin;
}

/// The identified Employee's own answer, `confirmed` or `declined`, on one
/// Trainee row.
class FloorTrainingAnswered extends FloorTrainingEvent {
  const FloorTrainingAnswered(this.traineeId, this.answer);

  final String traineeId;
  final String answer;
}

class FloorTrainingState {
  const FloorTrainingState({
    this.employeeName,
    this.entries = const [],
    this.isBusy = false,
    this.failure,
  });

  /// Who is identified; null until the exchange succeeds, and again after the
  /// identification is refused as expired.
  final String? employeeName;
  final List<TrainingToConfirm> entries;

  /// An exchange, a read or an answer is in flight.
  final bool isBusy;

  /// Why the last step did not land, for the dialog to report.
  final String? failure;

  bool get isIdentified => employeeName != null;
}

class FloorTrainingBloc extends Bloc<FloorTrainingEvent, FloorTrainingState> {
  FloorTrainingBloc({
    required PeopleApi peopleApi,
    required MaintenanceApi maintenanceApi,
    required FloorDeviceGateway floorDeviceGateway,
  })  : _people = peopleApi,
        _maintenance = maintenanceApi,
        _device = floorDeviceGateway,
        super(
          floorDeviceGateway.deviceCredential == null
              ? const FloorTrainingState(failure: notRegisteredMessage)
              : const FloorTrainingState(),
        ) {
    on<FloorTrainingIdentified>(_onIdentified);
    on<FloorTrainingAnswered>(_onAnswered);
  }

  final PeopleApi _people;
  final MaintenanceApi _maintenance;
  final FloorDeviceGateway _device;

  /// Held for this Bloc's (the dialog's) lifetime only; never on a state.
  String? _identification;

  static const String notRegisteredMessage =
      'This device is not registered. Ask an administrator to register it against an Org Unit.';

  static const String expiredMessage = 'Your identification has expired. Identify yourself again.';

  Future<void> _onIdentified(FloorTrainingIdentified event, Emitter<FloorTrainingState> emit) async {
    final current = state;
    if (current.isBusy || current.isIdentified) return;
    final credential = _device.deviceCredential;
    if (credential == null) {
      emit(const FloorTrainingState(failure: notRegisteredMessage));
      return;
    }
    emit(const FloorTrainingState(isBusy: true));
    try {
      final identification = await _maintenance.identifyTechnician(
        credential,
        employeeNo: event.employeeNo,
        pin: event.pin,
      );
      final entries = await _people.fetchFloorTrainingToConfirm(credential, identification.token);
      _identification = identification.token;
      emit(FloorTrainingState(employeeName: identification.employeeName, entries: entries));
    } on MaintenanceApiException catch (error) {
      emit(FloorTrainingState(failure: error.message));
    } on PeopleApiException catch (error) {
      emit(FloorTrainingState(failure: error.message));
    }
  }

  Future<void> _onAnswered(FloorTrainingAnswered event, Emitter<FloorTrainingState> emit) async {
    final current = state;
    final credential = _device.deviceCredential;
    final identification = _identification;
    if (current.isBusy || !current.isIdentified || credential == null || identification == null) return;

    emit(FloorTrainingState(employeeName: current.employeeName, entries: current.entries, isBusy: true));
    try {
      await _people.answerFloorTrainee(credential, identification, event.traineeId, event.answer);
      emit(
        FloorTrainingState(
          employeeName: current.employeeName,
          entries: [for (final entry in current.entries) if (entry.traineeId != event.traineeId) entry],
        ),
      );
    } on PeopleApiException catch (error) {
      if (error.statusCode == 401) {
        // The identification lapsed (or was never this device's): the list is
        // no longer this Employee's to act on, so back to identifying.
        _identification = null;
        emit(const FloorTrainingState(failure: expiredMessage));
        return;
      }
      emit(FloorTrainingState(employeeName: current.employeeName, entries: current.entries, failure: error.message));
    }
  }
}
