/// One Employee's record, as the detail Screen needs it (issue #86, AC5) —
/// reached either from a Directory row (`GET /api/people/employees/:id`) or
/// from "My record" (`GET /api/people/employees/me`), the same shape both
/// ways: [EmployeeDetailRequested.employeeId] null means "me".
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'employee.dart';

sealed class EmployeeDetailEvent {
  const EmployeeDetailEvent();
}

/// Load one Employee's record — the Screen's first build, and the retry a
/// failed load offers.
class EmployeeDetailRequested extends EmployeeDetailEvent {
  const EmployeeDetailRequested({this.employeeId});

  /// Null means "the caller's own record" (`GET /employees/me`).
  final String? employeeId;
}

sealed class EmployeeDetailState {
  const EmployeeDetailState();
}

class EmployeeDetailLoading extends EmployeeDetailState {
  const EmployeeDetailLoading();
}

class EmployeeDetailLoaded extends EmployeeDetailState {
  const EmployeeDetailLoaded({required this.employee});
  final EmployeeDetail employee;
}

class EmployeeDetailUnavailable extends EmployeeDetailState {
  const EmployeeDetailUnavailable({required this.message});
  final String message;
}

/// Route-scoped, like `DirectoryBloc`: one Screen's own reading of the
/// server, re-read on arrival rather than restored stale.
class EmployeeDetailBloc extends Bloc<EmployeeDetailEvent, EmployeeDetailState> {
  EmployeeDetailBloc({required PeopleApi peopleApi, required AuthGateway authGateway})
      : _api = peopleApi,
        _auth = authGateway,
        super(const EmployeeDetailLoading()) {
    on<EmployeeDetailRequested>(_onRequested);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  Future<void> _onRequested(
    EmployeeDetailRequested event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    emit(const EmployeeDetailLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const EmployeeDetailUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final employee = event.employeeId == null
          ? await _api.fetchMyEmployeeRecord(token)
          : await _api.fetchEmployeeDetail(token, event.employeeId!);
      emit(EmployeeDetailLoaded(employee: employee));
    } on PeopleApiException catch (error) {
      emit(EmployeeDetailUnavailable(message: error.message));
    }
  }
}
