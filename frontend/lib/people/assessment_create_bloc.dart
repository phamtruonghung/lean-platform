/// The create form's own state (issue #588, ADR-0068, slice 3): the Sites, the
/// process whose bank a paper is drawn from and that process's active count, the
/// assign group as it is built, the reach the server says that group has, and
/// the one submit.
///
/// **The six facts themselves stay in the widget.** A title, a paper size, a
/// minute count, a pass mark and a due date are text in controllers, exactly as
/// in `AssessmentQuestionFormDialog`: routing every keystroke through an event
/// would make the form's own undo/selection behaviour the Bloc's problem for no
/// gain. What belongs here is everything the server has to answer: which Sites
/// exist, how many active Questions a process holds, how many Employees a group
/// reaches (`GET /assessments/assign-preview`) and what the create-and-assign
/// answered.
///
/// **The reach is the server's number, not a guess.** This client cannot
/// resolve `employee_today()` or the crew fallback rule, so it does not try: it
/// asks the preview and shows what came back, and a refusal is shown as the
/// server's sentence.
///
/// **Create, then assign.** One submit does the two writes in the order the
/// server requires: `POST /assessments` (a draft) and then
/// `POST /assessments/:id/assign` when the group is not empty. A failure at
/// either step stops there and is shown as it came — an Assessment left as a
/// draft is a fact the register will show, never something this Bloc hides.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people/employee.dart';
import '../people/org_unit.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment.dart';

sealed class AssessmentCreateEvent {
  const AssessmentCreateEvent();
}

class AssessmentCreateStarted extends AssessmentCreateEvent {
  const AssessmentCreateStarted();
}

class AssessmentCreateSiteChosen extends AssessmentCreateEvent {
  const AssessmentCreateSiteChosen(this.siteId);

  final String siteId;
}

class AssessmentCreateProcessChosen extends AssessmentCreateEvent {
  const AssessmentCreateProcessChosen(this.process);

  final OrgUnitNode? process;
}

/// The group as it now stands. Sent after every add and every chip removed.
class AssessmentCreateGroupChanged extends AssessmentCreateEvent {
  const AssessmentCreateGroupChanged({this.orgUnits = const [], this.employees = const []});

  final List<OrgUnitNode> orgUnits;
  final List<Employee> employees;
}

/// The six facts, ready for the wire, plus the group they are assigned to.
class AssessmentCreateSubmitted extends AssessmentCreateEvent {
  const AssessmentCreateSubmitted({required this.body, required this.group});

  final Map<String, Object?> body;
  final AssessmentCreateGroupChanged group;
}

sealed class AssessmentCreateState {
  const AssessmentCreateState();
}

class AssessmentCreateLoading extends AssessmentCreateState {
  const AssessmentCreateLoading();
}

class AssessmentCreateUnavailable extends AssessmentCreateState {
  const AssessmentCreateUnavailable({required this.message});

  final String message;
}

class AssessmentCreateLoaded extends AssessmentCreateState {
  const AssessmentCreateLoaded({
    required this.sites,
    required this.process,
    required this.activeCount,
    required this.group,
    this.siteId,
    this.preview,
    this.previewing = false,
    this.previewFailure,
    this.submitting = false,
    this.failure,
    this.created,
  });

  final List<Site> sites;
  final OrgUnitNode? process;

  /// The process's own active Questions — the number the paper size is checked
  /// against, and never the subtree's.
  final int? activeCount;
  final AssessmentCreateGroupChanged group;
  final String? siteId;

  /// How many Employees the group reaches, as the server answered.
  final AssignPreview? preview;
  final bool previewing;
  final String? previewFailure;

  final bool submitting;
  final String? failure;

  /// The Assessment the submit created, once it did.
  final Assessment? created;

  AssessmentCreateLoaded copyWith({
    String? siteId,
    OrgUnitNode? process,
    bool clearProcess = false,
    int? activeCount,
    bool clearActiveCount = false,
    AssessmentCreateGroupChanged? group,
    AssignPreview? preview,
    bool clearPreview = false,
    bool? previewing,
    String? previewFailure,
    bool clearPreviewFailure = false,
    bool? submitting,
    String? failure,
    bool clearFailure = false,
    Assessment? created,
  }) {
    return AssessmentCreateLoaded(
      sites: sites,
      process: clearProcess ? null : (process ?? this.process),
      activeCount: clearActiveCount ? null : (activeCount ?? this.activeCount),
      group: group ?? this.group,
      siteId: siteId ?? this.siteId,
      preview: clearPreview ? null : (preview ?? this.preview),
      previewing: previewing ?? this.previewing,
      previewFailure: clearPreviewFailure ? null : (previewFailure ?? this.previewFailure),
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      created: created ?? this.created,
    );
  }
}

class AssessmentCreateBloc extends Bloc<AssessmentCreateEvent, AssessmentCreateState> {
  AssessmentCreateBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentCreateLoading()) {
    on<AssessmentCreateStarted>(_onStarted);
    on<AssessmentCreateSiteChosen>(_onSiteChosen);
    on<AssessmentCreateProcessChosen>(_onProcessChosen);
    on<AssessmentCreateGroupChanged>(_onGroupChanged);
    on<AssessmentCreateSubmitted>(_onSubmitted);
  }

  final PeopleApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  /// Bumped by every group change, so a slow preview answer cannot overwrite the
  /// number for a group the person has already changed.
  int _previewGeneration = 0;

  Future<void> _onStarted(
    AssessmentCreateStarted event,
    Emitter<AssessmentCreateState> emit,
  ) async {
    emit(const AssessmentCreateLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentCreateUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _api.fetchSites(token);
      emit(AssessmentCreateLoaded(
        sites: sites,
        siteId: sites.isEmpty ? null : sites.first.id,
        process: null,
        activeCount: null,
        group: const AssessmentCreateGroupChanged(),
      ));
    } on PeopleApiException catch (error) {
      emit(AssessmentCreateUnavailable(message: error.message));
    }
  }

  void _onSiteChosen(
    AssessmentCreateSiteChosen event,
    Emitter<AssessmentCreateState> emit,
  ) {
    final current = state;
    if (current is! AssessmentCreateLoaded) return;
    emit(current.copyWith(
      siteId: event.siteId,
      clearProcess: true,
      clearActiveCount: true,
      group: const AssessmentCreateGroupChanged(),
      clearPreview: true,
    ));
  }

  Future<void> _onProcessChosen(
    AssessmentCreateProcessChosen event,
    Emitter<AssessmentCreateState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentCreateLoaded) return;
    final process = event.process;
    if (process == null) {
      emit(current.copyWith(clearProcess: true, clearActiveCount: true));
      return;
    }
    emit(current.copyWith(process: process, clearActiveCount: true, clearFailure: true));
    final token = _auth.currentAccessToken;
    if (token == null) return;
    try {
      final page = await _api.fetchAssessmentQuestions(token, orgUnitId: process.id, limit: 1);
      final now = state;
      if (now is! AssessmentCreateLoaded || now.process?.id != process.id) return;
      emit(now.copyWith(activeCount: page.activeCount));
    } on PeopleApiException catch (error) {
      final now = state;
      if (now is! AssessmentCreateLoaded) return;
      emit(now.copyWith(failure: error.message));
    }
  }

  Future<void> _onGroupChanged(
    AssessmentCreateGroupChanged event,
    Emitter<AssessmentCreateState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentCreateLoaded) return;
    emit(current.copyWith(
      group: event,
      clearPreview: true,
      clearPreviewFailure: true,
      previewing: event.orgUnits.isNotEmpty || event.employees.isNotEmpty,
    ));
    if (event.orgUnits.isEmpty && event.employees.isEmpty) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(previewing: false, previewFailure: signedOutMessage));
      return;
    }
    final generation = ++_previewGeneration;
    try {
      final preview = await _api.previewAssessmentAssignment(
        token,
        orgUnitIds: [for (final unit in event.orgUnits) unit.id],
        employeeIds: [for (final employee in event.employees) employee.id],
      );
      if (generation != _previewGeneration) return;
      final now = state;
      if (now is! AssessmentCreateLoaded) return;
      emit(now.copyWith(preview: preview, previewing: false));
    } on PeopleApiException catch (error) {
      if (generation != _previewGeneration) return;
      final now = state;
      if (now is! AssessmentCreateLoaded) return;
      emit(now.copyWith(previewing: false, previewFailure: error.message));
    }
  }

  Future<void> _onSubmitted(
    AssessmentCreateSubmitted event,
    Emitter<AssessmentCreateState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentCreateLoaded) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(failure: signedOutMessage));
      return;
    }
    emit(current.copyWith(submitting: true, clearFailure: true));
    try {
      final created = await _api.createAssessment(token, event.body);
      final group = event.group;
      if (group.orgUnits.isNotEmpty || group.employees.isNotEmpty) {
        await _api.assignAssessment(
          token,
          created.id,
          orgUnitIds: [for (final unit in group.orgUnits) unit.id],
          employeeIds: [for (final employee in group.employees) employee.id],
        );
      }
      emit(current.copyWith(submitting: false, created: created));
    } on PeopleApiException catch (error) {
      emit(current.copyWith(submitting: false, failure: error.message));
    }
  }
}
