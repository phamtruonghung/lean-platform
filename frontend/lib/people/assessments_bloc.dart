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

/// A tab was chosen. The data is already loaded, so this only moves the view.
class AssessmentsTabSelected extends AssessmentsEvent {
  const AssessmentsTabSelected(this.tab);

  final int tab;
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

  AssessmentsLoaded copyWith({
    List<AssessmentAttempt>? mine,
    List<Assessment>? created,
    List<Assessment>? all,
    int? tab,
    bool? isRefreshing,
    String? notice,
    bool clearNotice = false,
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
    await _read(emit, tab: current is AssessmentsLoaded ? current.tab : assignedToMeTab);
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
  }) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final mine = await _readMine(token);
      final created = await _api.fetchAssessments(token, mine: true);
      final all = await _api.fetchAssessments(token);
      emit(AssessmentsLoaded(
        mayChange: mayChange,
        mayMark: mayMark,
        mine: mine,
        created: created.assessments,
        all: all.assessments,
        tab: tab,
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
}
