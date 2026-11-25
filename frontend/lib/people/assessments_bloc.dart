/// The Assessments register (issue #588, ADR-0068, slice 3): the Assessments a
/// person created, the Assessments of the whole plant, and — the candidate's own
/// side — every Attempt assigned to them.
///
/// **Three tabs, two shapes.** "Assigned to me" reads
/// `GET /assessment-attempts/mine` (an Attempt per row: the Assessment's number
/// and title, the process, its status and the deadline). "I created" and "All"
/// read `GET /assessments` (an Assessment per row: the paper size, the due date
/// and the four sitting counts).
///
/// **An Account with no Employee has no Attempts**, and that is not an error:
/// the candidate's door answers 403 by design (ADR-0045), so this Bloc reads
/// that one refusal as an empty list and the tab says "nothing assigned to
/// you". Every other failure is the server's message, shown as it came.
///
/// **Counts are never hidden.** Whether a tab shows scores is a later slice's
/// decision (spec section 3.12, marking is slice 4); nothing in this state
/// carries one.
///
/// Route-scoped: one Screen's own reading of the server, re-read on arrival.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';

/// The order the three tabs are drawn in, and the index each one answers to.
const int assignedToMeTab = 0;
const int iCreatedTab = 1;
const int allAssessmentsTab = 2;

sealed class AssessmentsEvent {
  const AssessmentsEvent();
}

/// Load everything the register shows. Also the retry a failed load offers.
class AssessmentsStarted extends AssessmentsEvent {
  const AssessmentsStarted();
}

/// Re-read the server without leaving the Screen.
class AssessmentsRefreshed extends AssessmentsEvent {
  const AssessmentsRefreshed();
}

/// The "All" tab's filter changed (slice 6): the register is read again with it.
class AssessmentsFiltered extends AssessmentsEvent {
  const AssessmentsFiltered(this.filter);

  final AssessmentsFilter filter;
}

/// A tab was chosen. The data is already loaded, so this only moves the view.
class AssessmentsTabSelected extends AssessmentsEvent {
  const AssessmentsTabSelected(this.tab);

  final int tab;
}

/// What narrows the "All" tab (slice 6): the process, the status, a date range
/// on the due date (the creation day when there is none) and "below pass mark".
/// Every field is optional; an unset one is not sent.
class AssessmentsFilter {
  const AssessmentsFilter({
    this.orgUnitId,
    this.status,
    this.from,
    this.to,
    this.failed = false,
  });

  final String? orgUnitId;
  final String? status;

  /// `YYYY-MM-DD`, the dates `AppDateField` reports.
  final String? from;
  final String? to;
  final bool failed;

  bool get isEmpty =>
      orgUnitId == null && status == null && from == null && to == null && !failed;

  AssessmentsFilter copyWith({
    String? orgUnitId,
    bool clearOrgUnit = false,
    String? status,
    bool clearStatus = false,
    String? from,
    bool clearFrom = false,
    String? to,
    bool clearTo = false,
    bool? failed,
  }) {
    return AssessmentsFilter(
      orgUnitId: clearOrgUnit ? null : (orgUnitId ?? this.orgUnitId),
      status: clearStatus ? null : (status ?? this.status),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      failed: failed ?? this.failed,
    );
  }
}

/// A process the register can be narrowed to: an Org Unit some Assessment draws
/// its bank from.
class AssessmentProcess {
  const AssessmentProcess({required this.id, required this.name});

  final String id;
  final String name;
}

sealed class AssessmentsState {
  const AssessmentsState();
}

class AssessmentsLoading extends AssessmentsState {
  const AssessmentsLoading();
}

class AssessmentsUnavailable extends AssessmentsState {
  const AssessmentsUnavailable({required this.message});

  final String message;
}

class AssessmentsLoaded extends AssessmentsState {
  const AssessmentsLoaded({
    required this.mayChange,
    this.mayMark = false,
    required this.mine,
    required this.created,
    required this.all,
    this.tab = assignedToMeTab,
    this.isRefreshing = false,
    this.notice,
    this.filter = const AssessmentsFilter(),
    this.processes = const [],
  });

  final bool mayChange;

  /// Whether the caller holds `PPL_ASSESSMENT_MARK`: the marking queue's door.
  final bool mayMark;
  final List<AssessmentAttempt> mine;
  final List<Assessment> created;
  final List<Assessment> all;
  final int tab;
  final bool isRefreshing;

  /// A sentence the Screen shows once, in a banner: a write's outcome, or why a
  /// refresh failed while the rows on screen stayed.
  final String? notice;

  /// What the "All" tab is narrowed by, and the processes it can be narrowed to
  /// (read from the register before any filter was applied, so choosing one
  /// never removes the others from the list).
  final AssessmentsFilter filter;
  final List<AssessmentProcess> processes;

  AssessmentsLoaded copyWith({
    List<AssessmentAttempt>? mine,
    List<Assessment>? created,
    List<Assessment>? all,
    int? tab,
    bool? isRefreshing,
    String? notice,
    bool clearNotice = false,
    AssessmentsFilter? filter,
  }) {
    return AssessmentsLoaded(
      mayChange: mayChange,
      mayMark: mayMark,
      mine: mine ?? this.mine,
      created: created ?? this.created,
      all: all ?? this.all,
      tab: tab ?? this.tab,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      notice: clearNotice ? null : (notice ?? this.notice),
      filter: filter ?? this.filter,
      processes: processes,
    );
  }
}

class AssessmentsBloc extends Bloc<AssessmentsEvent, AssessmentsState> {
  AssessmentsBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.mayChange,
    this.mayMark = false,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentsLoading()) {
    on<AssessmentsStarted>(_onStarted);
    on<AssessmentsRefreshed>(_onRefreshed);
    on<AssessmentsTabSelected>(_onTabSelected);
    on<AssessmentsFiltered>(_onFiltered);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  /// Whether the caller holds `PPL_ASSESSMENT_CHANGE`; decided by the router and
  /// handed in, and it decides whether "New assessment" exists.
  final bool mayChange;

  /// Whether the caller holds `PPL_ASSESSMENT_MARK`; decided by the router, and
  /// it decides whether the marking queue is offered.
  final bool mayMark;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  Future<void> _onStarted(
    AssessmentsStarted event,
    Emitter<AssessmentsState> emit,
  ) async {
    emit(const AssessmentsLoading());
    await _read(emit);
  }

  Future<void> _onRefreshed(
    AssessmentsRefreshed event,
    Emitter<AssessmentsState> emit,
  ) async {
    final current = state;
    if (current is AssessmentsLoaded) {
      emit(current.copyWith(isRefreshing: true, clearNotice: true));
    }
    await _read(
      emit,
      tab: current is AssessmentsLoaded ? current.tab : assignedToMeTab,
      filter: current is AssessmentsLoaded ? current.filter : const AssessmentsFilter(),
    );
  }

  Future<void> _onFiltered(
    AssessmentsFiltered event,
    Emitter<AssessmentsState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentsLoaded) return;
    emit(current.copyWith(isRefreshing: true, clearNotice: true, filter: event.filter));
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final all = await _api.fetchAssessments(
        token,
        orgUnitId: event.filter.orgUnitId,
        status: event.filter.status,
        from: event.filter.from,
        to: event.filter.to,
        failed: event.filter.failed,
      );
      final now = state;
      if (now is! AssessmentsLoaded || now.filter != event.filter) return;
      emit(AssessmentsLoaded(
        mayChange: now.mayChange,
        mayMark: now.mayMark,
        mine: now.mine,
        created: now.created,
        all: all.assessments,
        tab: now.tab,
        filter: event.filter,
        processes: now.processes,
      ));
    } on PeopleApiException catch (error) {
      final now = state;
      if (now is! AssessmentsLoaded) return;
      emit(now.copyWith(isRefreshing: false, notice: error.message));
    }
  }

  void _onTabSelected(
    AssessmentsTabSelected event,
    Emitter<AssessmentsState> emit,
  ) {
    final current = state;
    if (current is! AssessmentsLoaded) return;
    if (event.tab == current.tab) return;
    emit(current.copyWith(tab: event.tab, clearNotice: true));
  }

  Future<void> _read(
    Emitter<AssessmentsState> emit, {
    int tab = assignedToMeTab,
    AssessmentsFilter filter = const AssessmentsFilter(),
  }) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final mine = await _readMine(token);
      final created = await _api.fetchAssessments(token, mine: true);
      // The unfiltered register is read as well as the narrowed one whenever a
      // filter is on, because the process list is the processes the whole
      // register holds, not the ones the filter happens to leave.
      final everything = await _api.fetchAssessments(token);
      final all = filter.isEmpty
          ? everything
          : await _api.fetchAssessments(
              token,
              orgUnitId: filter.orgUnitId,
              status: filter.status,
              from: filter.from,
              to: filter.to,
              failed: filter.failed,
            );
      emit(AssessmentsLoaded(
        mayChange: mayChange,
        mayMark: mayMark,
        mine: mine,
        created: created.assessments,
        all: all.assessments,
        tab: tab,
        filter: filter,
        processes: _processesOf(everything.assessments),
      ));
    } on PeopleApiException catch (error) {
      emit(AssessmentsUnavailable(message: error.message));
    }
  }

  /// The candidate's own list, with the one refusal that is not a failure: an
  /// Account linked to no Employee has no Attempts (ADR-0045's own 403).
  Future<List<AssessmentAttempt>> _readMine(String token) async {
    try {
      return await _api.fetchMyAssessmentAttempts(token);
    } on PeopleApiException catch (error) {
      if (error.statusCode == 403) return const [];
      rethrow;
    }
  }

  /// The distinct processes the register's Assessments draw from, by name.
  static List<AssessmentProcess> _processesOf(List<Assessment> assessments) {
    final seen = <String, AssessmentProcess>{};
    for (final assessment in assessments) {
      seen.putIfAbsent(
        assessment.orgUnitId,
        () => AssessmentProcess(
          id: assessment.orgUnitId,
          name: assessment.orgUnitName ?? assessment.orgUnitId,
        ),
      );
    }
    return seen.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
