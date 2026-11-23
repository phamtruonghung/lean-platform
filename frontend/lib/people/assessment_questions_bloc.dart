/// The assessment Question bank's own state (issue #588, ADR-0068): one
/// process's Questions, read a page at a time, and — for a caller who may
/// change the bank — the writes over it (`GET`/`POST`/`PATCH`/`DELETE
/// /api/people/assessment-questions` and the paste, `.../bulk`).
///
/// The bank is filed on one Org Unit, the process, so the Screen has nothing to
/// show until one is chosen: a Site first (the Org Unit search is per Site),
/// then an Org Unit found by name. Choosing either resets the paging.
///
/// **[mayChange] is decided by the router and handed in**, not read off what the
/// server revealed: it is the caller's `PPL_ASSESSMENT_CHANGE` permission, the
/// same code that opens the write routes (`JobRolesScreen.isAdmin`'s shape, with
/// the permission in place of the role). It decides whether the Add and Paste
/// buttons exist; whether the key is *shown* is the server's answer per row,
/// because the key also needs write reach on this process, which the client
/// cannot judge. A caller with the code and no reach sees the buttons, is
/// refused with the server's scope sentence, and sees dashes where the key
/// would be — each of those is the server's word, not a guess here.
///
/// A write that lands re-reads the current page so the list, [total] and
/// [activeCount] are the server's. A write that is refused leaves the dialog
/// open: [formFailure] for a Question's form, [pasteError] — with the line the
/// server named — for the paste.
///
/// Route-scoped: one Screen's own reading of the server, re-read on arrival.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/notices.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'assessment_question.dart';
import 'org_unit.dart';

sealed class AssessmentQuestionsEvent {
  const AssessmentQuestionsEvent();
}

/// Load the Sites. Also the retry a failed load offers.
class AssessmentQuestionsStarted extends AssessmentQuestionsEvent {
  const AssessmentQuestionsStarted();
}

/// A different Site was chosen for the process search; the process chosen so
/// far belonged to the old one and is cleared.
class AssessmentQuestionsSiteChosen extends AssessmentQuestionsEvent {
  const AssessmentQuestionsSiteChosen(this.siteId);

  final String siteId;
}

/// A process was picked from the Org Unit search.
class AssessmentQuestionsProcessChosen extends AssessmentQuestionsEvent {
  const AssessmentQuestionsProcessChosen(this.orgUnit);

  final OrgUnitNode orgUnit;
}

/// The search over the Questions' text changed. Back to the first page.
class AssessmentQuestionsSearchChanged extends AssessmentQuestionsEvent {
  const AssessmentQuestionsSearchChanged(this.q);

  final String q;
}

/// Retired Questions asked for or put away again.
class AssessmentQuestionsIncludeInactiveToggled extends AssessmentQuestionsEvent {
  const AssessmentQuestionsIncludeInactiveToggled(this.includeInactive);

  final bool includeInactive;
}

/// A page boundary was crossed.
class AssessmentQuestionsPageChanged extends AssessmentQuestionsEvent {
  const AssessmentQuestionsPageChanged(this.offset);

  final int offset;
}

/// The form has decided: one new Question in the chosen process. [body] is the
/// Question's own fields; the Bloc adds the process.
class AssessmentQuestionCreated extends AssessmentQuestionsEvent {
  const AssessmentQuestionCreated({required this.body});

  final Map<String, Object?> body;
}

/// The form has decided: a full restatement of one Question's own fields.
class AssessmentQuestionCorrected extends AssessmentQuestionsEvent {
  const AssessmentQuestionCorrected({required this.id, required this.body});

  final String id;
  final Map<String, Object?> body;
}

/// Take one Question out of future draws. The Screen has already asked.
class AssessmentQuestionRetired extends AssessmentQuestionsEvent {
  const AssessmentQuestionRetired(this.id);

  final String id;
}

/// The paste dialog has decided: [text] goes to the server whole.
class AssessmentQuestionsPasteSubmitted extends AssessmentQuestionsEvent {
  const AssessmentQuestionsPasteSubmitted(this.text);

  final String text;
}

/// Re-read the current page, as it is.
class AssessmentQuestionsRefreshed extends AssessmentQuestionsEvent {
  const AssessmentQuestionsRefreshed();
}

/// Why a paste was refused: the server's own message and, when it named one,
/// the pasted line. Nothing was written.
class AssessmentPasteRefusal {
  const AssessmentPasteRefusal({required this.message, this.line, this.statusCode});

  final String message;
  final int? line;
  final int? statusCode;
}

sealed class AssessmentQuestionsState {
  const AssessmentQuestionsState();
}

class AssessmentQuestionsLoading extends AssessmentQuestionsState {
  const AssessmentQuestionsLoading();
}

class AssessmentQuestionsUnavailable extends AssessmentQuestionsState {
  const AssessmentQuestionsUnavailable({required this.message});

  final String message;
}

class AssessmentQuestionsLoaded extends AssessmentQuestionsState {
  const AssessmentQuestionsLoaded({
    required this.mayChange,
    this.sites = const [],
    this.siteId,
    this.orgUnit,
    this.questions = const [],
    this.total = 0,
    this.activeCount = 0,
    this.offset = 0,
    this.limit = AssessmentQuestionsBloc.pageSize,
    this.q = '',
    this.includeInactive = false,
    this.isLoadingPage = false,
    this.saving = false,
    this.pageFailure,
    this.pasteError,
    this.formFailure,
  });

  final bool mayChange;
  final List<Site> sites;
  final String? siteId;

  /// The process whose bank is on screen; null until one is chosen.
  final OrgUnitNode? orgUnit;
  final List<AssessmentQuestion> questions;

  /// Rows the filter matches — what paging walks.
  final int total;

  /// Active Questions in the process, whatever the filter.
  final int activeCount;
  final int offset;
  final int limit;
  final String q;
  final bool includeInactive;

  /// A page is being read.
  final bool isLoadingPage;

  /// A write is in flight.
  final bool saving;

  /// Why the page could not be read; the previous rows stay on screen.
  final String? pageFailure;

  /// Why the last paste was refused. Reported by the paste dialog, which stays
  /// open so the caller can fix the line rather than retype the whole paste.
  final AssessmentPasteRefusal? pasteError;

  /// Why the last form write was refused. Reported by the open form.
  final String? formFailure;

  AssessmentQuestionsLoaded copyWith({
    List<Site>? sites,
    String? siteId,
    OrgUnitNode? orgUnit,
    bool clearOrgUnit = false,
    List<AssessmentQuestion>? questions,
    int? total,
    int? activeCount,
    int? offset,
    String? q,
    bool? includeInactive,
    bool? isLoadingPage,
    bool? saving,
    String? pageFailure,
    AssessmentPasteRefusal? pasteError,
    String? formFailure,
  }) =>
      AssessmentQuestionsLoaded(
        mayChange: mayChange,
        sites: sites ?? this.sites,
        siteId: siteId ?? this.siteId,
        orgUnit: clearOrgUnit ? null : (orgUnit ?? this.orgUnit),
        questions: questions ?? this.questions,
        total: total ?? this.total,
        activeCount: activeCount ?? this.activeCount,
        offset: offset ?? this.offset,
        limit: limit,
        q: q ?? this.q,
        includeInactive: includeInactive ?? this.includeInactive,
        isLoadingPage: isLoadingPage ?? this.isLoadingPage,
        saving: saving ?? this.saving,
        // The three failures are always overwritten, never carried forward.
        pageFailure: pageFailure,
        pasteError: pasteError,
        formFailure: formFailure,
      );
}

class AssessmentQuestionsBloc extends Bloc<AssessmentQuestionsEvent, AssessmentQuestionsState> {
  AssessmentQuestionsBloc({
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    required this.mayChange,
  })  : _api = peopleApi,
        _auth = authGateway,
        super(const AssessmentQuestionsLoading()) {
    on<AssessmentQuestionsStarted>(_onStarted);
    on<AssessmentQuestionsSiteChosen>(_onSiteChosen);
    on<AssessmentQuestionsProcessChosen>(_onProcessChosen);
    on<AssessmentQuestionsSearchChanged>(_onSearchChanged);
    on<AssessmentQuestionsIncludeInactiveToggled>(_onIncludeInactiveToggled);
    on<AssessmentQuestionsPageChanged>(_onPageChanged);
    on<AssessmentQuestionCreated>(_onCreated);
    on<AssessmentQuestionCorrected>(_onCorrected);
    on<AssessmentQuestionRetired>(_onRetired);
    on<AssessmentQuestionsPasteSubmitted>(_onPasteSubmitted);
    on<AssessmentQuestionsRefreshed>(_onRefreshed);
  }

  final PeopleApi _api;
  final AuthGateway _auth;
  /// Whether the caller holds the maintain code; see the library header.
  final bool mayChange;

  /// Questions per page: the server's own default, sent explicitly so the two
  /// cannot drift.
  static const int pageSize = 50;

  static const String signedOutMessage = BlocNotice.sessionEnded;

  /// Bumped by every page read so a slow answer to an earlier one (a search
  /// typed over) is dropped rather than painted over the newer rows.
  int _generation = 0;

  Future<void> _onStarted(
    AssessmentQuestionsStarted event,
    Emitter<AssessmentQuestionsState> emit,
  ) async {
    emit(const AssessmentQuestionsLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const AssessmentQuestionsUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final sites = await _api.fetchSites(token);
      emit(AssessmentQuestionsLoaded(
        mayChange: mayChange,
        sites: sites,
        siteId: sites.isEmpty ? null : sites.first.id,
      ));
    } on PeopleApiException catch (error) {
      emit(AssessmentQuestionsUnavailable(message: error.message));
    }
  }

  void _onSiteChosen(
    AssessmentQuestionsSiteChosen event,
    Emitter<AssessmentQuestionsState> emit,
  ) {
    final current = state;
    if (current is! AssessmentQuestionsLoaded || current.siteId == event.siteId) return;
    _generation += 1;
    emit(AssessmentQuestionsLoaded(
      mayChange: mayChange,
      sites: current.sites,
      siteId: event.siteId,
    ));
  }

  Future<void> _onProcessChosen(
    AssessmentQuestionsProcessChosen event,
    Emitter<AssessmentQuestionsState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentQuestionsLoaded) return;
    // A new process starts from its own first page, with no search carried over.
    final fresh = AssessmentQuestionsLoaded(
      mayChange: mayChange,
      sites: current.sites,
      siteId: current.siteId,
      orgUnit: event.orgUnit,
      includeInactive: current.includeInactive,
    );
    emit(fresh);
    await _read(emit, fresh);
  }

  Future<void> _onSearchChanged(
    AssessmentQuestionsSearchChanged event,
    Emitter<AssessmentQuestionsState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentQuestionsLoaded || current.orgUnit == null) return;
    await _read(emit, current.copyWith(q: event.q, offset: 0));
  }

  Future<void> _onIncludeInactiveToggled(
    AssessmentQuestionsIncludeInactiveToggled event,
    Emitter<AssessmentQuestionsState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentQuestionsLoaded) return;
    final next = current.copyWith(includeInactive: event.includeInactive, offset: 0);
    if (current.orgUnit == null) {
      emit(next);
      return;
    }
    await _read(emit, next);
  }

  Future<void> _onPageChanged(
    AssessmentQuestionsPageChanged event,
    Emitter<AssessmentQuestionsState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentQuestionsLoaded || current.orgUnit == null) return;
    await _read(emit, current.copyWith(offset: event.offset < 0 ? 0 : event.offset));
  }

  Future<void> _onRefreshed(
    AssessmentQuestionsRefreshed event,
    Emitter<AssessmentQuestionsState> emit,
  ) async {
    final current = state;
    if (current is! AssessmentQuestionsLoaded || current.orgUnit == null) return;
    await _read(emit, current);
  }

  /// Reads [wanted]'s page from the server and emits the answer on top of it.
  /// A failure keeps the rows already shown and says why.
  Future<void> _read(
    Emitter<AssessmentQuestionsState> emit,
    AssessmentQuestionsLoaded wanted,
  ) async {
    final orgUnit = wanted.orgUnit;
    if (orgUnit == null) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(wanted.copyWith(isLoadingPage: false, pageFailure: signedOutMessage));
      return;
    }
    final generation = ++_generation;
    emit(wanted.copyWith(isLoadingPage: true));
    try {
      final page = await _api.fetchAssessmentQuestions(
        token,
        orgUnitId: orgUnit.id,
        q: wanted.q,
        includeInactive: wanted.includeInactive,
        limit: wanted.limit,
        offset: wanted.offset,
      );
      if (generation != _generation) return;
      emit(wanted.copyWith(
        questions: page.questions,
        total: page.total,
        activeCount: page.activeCount,
        isLoadingPage: false,
        saving: false,
      ));
    } on PeopleApiException catch (error) {
      if (generation != _generation) return;
      emit(wanted.copyWith(isLoadingPage: false, saving: false, pageFailure: error.message));
    }
  }

  /// Every write takes the same steps — refuse if one is in flight or the
  /// session has ended, send, then re-read the page — so they are written once.
  Future<void> _write(
    Emitter<AssessmentQuestionsState> emit,
    Future<void> Function(String token, AssessmentQuestionsLoaded current) send, {
    required AssessmentQuestionsLoaded Function(AssessmentQuestionsLoaded, PeopleApiException)
        refused,
  }) async {
    final current = state;
    if (current is! AssessmentQuestionsLoaded || current.saving || current.orgUnit == null) {
      return;
    }
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(refused(current, PeopleApiException(signedOutMessage)));
      return;
    }
    emit(current.copyWith(saving: true));
    try {
      await send(token, current);
    } on PeopleApiException catch (error) {
      final settled = state;
      if (settled is! AssessmentQuestionsLoaded) return;
      emit(refused(settled.copyWith(saving: false), error));
      return;
    }
    final settled = state;
    if (settled is! AssessmentQuestionsLoaded) return;
    await _read(emit, settled.copyWith(saving: true));
  }

  AssessmentQuestionsLoaded _formRefused(
    AssessmentQuestionsLoaded state,
    PeopleApiException error,
  ) =>
      state.copyWith(saving: false, formFailure: error.message);

  Future<void> _onCreated(
    AssessmentQuestionCreated event,
    Emitter<AssessmentQuestionsState> emit,
  ) =>
      _write(
        emit,
        (token, current) async {
          await _api.createAssessmentQuestion(
            token,
            {'orgUnitId': current.orgUnit!.id, ...event.body},
          );
        },
        refused: _formRefused,
      );

  Future<void> _onCorrected(
    AssessmentQuestionCorrected event,
    Emitter<AssessmentQuestionsState> emit,
  ) =>
      _write(
        emit,
        (token, current) async {
          await _api.correctAssessmentQuestion(token, event.id, event.body);
        },
        refused: _formRefused,
      );

  Future<void> _onRetired(
    AssessmentQuestionRetired event,
    Emitter<AssessmentQuestionsState> emit,
  ) =>
      _write(
        emit,
        (token, current) => _api.retireAssessmentQuestion(token, event.id),
        // A refused retire has no dialog to report in, so it surfaces as the
        // page's own failure line.
        refused: (state, error) =>
            state.copyWith(saving: false, pageFailure: error.message),
      );

  Future<void> _onPasteSubmitted(
    AssessmentQuestionsPasteSubmitted event,
    Emitter<AssessmentQuestionsState> emit,
  ) =>
      _write(
        emit,
        (token, current) async {
          await _api.bulkAssessmentQuestions(
            token,
            orgUnitId: current.orgUnit!.id,
            text: event.text,
          );
        },
        refused: (state, error) => state.copyWith(
          saving: false,
          pasteError: AssessmentPasteRefusal(
            message: error.message,
            line: error.line,
            statusCode: error.statusCode,
          ),
        ),
      );
}
