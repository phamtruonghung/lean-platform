/// The daily KPI Review of one Site (ADR-0055): one row per KPI for a day, with
/// the Daily Target that day had and the judgement saved so far.
///
/// "Today" is the server's. The first read carries no `date`, so `review_date`
/// in the answer is the Site's last working day and `site_today` is the Site's
/// own today; the date picker passes `?date=`. `review_date` is the heading's
/// day and `site_today` is the picker's last day.
///
/// Saving posts every changed row in one request and then reads the day on
/// screen again (never an omitted date, which would be the last working day), so
/// the `app_user` and `entered_at` shown are the server's.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart' show Site;
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'kpi_api.dart';
import 'kpi_catalogue.dart';

sealed class KpiReviewEvent {
  const KpiReviewEvent();
}

/// Load the Sites, then the Review at the first of them, for [date] or, when
/// null, the Site's last working day. Also the retry a failed load offers.
class KpiReviewStarted extends KpiReviewEvent {
  const KpiReviewStarted({this.date});
  final String? date;
}

class KpiReviewSiteSelected extends KpiReviewEvent {
  const KpiReviewSiteSelected(this.siteId);
  final String siteId;
}

class ReviewDateSelected extends KpiReviewEvent {
  const ReviewDateSelected(this.date);
  final String date;
}

class ReviewSaveRequested extends KpiReviewEvent {
  const ReviewSaveRequested(this.entries);
  final List<ReviewEntryInput> entries;
}

sealed class KpiReviewState {
  const KpiReviewState();
}

class KpiReviewLoading extends KpiReviewState {
  const KpiReviewLoading();
}

class KpiReviewUnavailable extends KpiReviewState {
  const KpiReviewUnavailable({required this.message});
  final String message;
}

class KpiReviewLoaded extends KpiReviewState {
  const KpiReviewLoaded({
    required this.sites,
    required this.siteId,
    this.review,
    this.siteToday,
    this.isLoadingReview = false,
    this.isMutating = false,
    this.mutationFailure,
    this.savedCount,
  });

  final List<Site> sites;
  final String siteId;

  /// Null while a Site or day switch is still reading.
  final KpiReview? review;

  /// The Site's own today (`site_today`), taken from the last read that asked
  /// for no `date`; that read answers the last working day as `review_date`.
  /// It is the date picker's last day: the day on screen cannot be, or a past
  /// day once picked would shut the way forward again. Null when the Screen
  /// was opened on a given day and today is not yet known.
  final String? siteToday;
  final bool isLoadingReview;
  final bool isMutating;

  /// Why the last save did not land; the entries on screen are kept.
  final String? mutationFailure;

  /// How many entries the last save wrote, until the next read.
  final int? savedCount;

  KpiReviewLoaded copyWith({
    String? siteId,
    KpiReview? review,
    bool clearReview = false,
    String? siteToday,
    bool clearSiteToday = false,
    bool? isLoadingReview,
    bool? isMutating,
    String? mutationFailure,
    int? savedCount,
  }) =>
      KpiReviewLoaded(
        sites: sites,
        siteId: siteId ?? this.siteId,
        review: clearReview ? null : (review ?? this.review),
        siteToday: clearSiteToday ? null : (siteToday ?? this.siteToday),
        isLoadingReview: isLoadingReview ?? this.isLoadingReview,
        isMutating: isMutating ?? this.isMutating,
        mutationFailure: mutationFailure,
        savedCount: savedCount,
      );
}

class KpiReviewBloc extends Bloc<KpiReviewEvent, KpiReviewState> {
  KpiReviewBloc({required PeopleApi peopleApi, required KpiApi kpiApi, required AuthGateway authGateway})
      : _people = peopleApi,
        _api = kpiApi,
        _auth = authGateway,
        super(const KpiReviewLoading()) {
    on<KpiReviewStarted>(_onStarted);
    on<KpiReviewSiteSelected>(_onSiteSelected);
    on<ReviewDateSelected>(_onDateSelected);
    on<ReviewSaveRequested>(_onSaveRequested);
  }

  final PeopleApi _people;
  final KpiApi _api;
  final AuthGateway _auth;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';
  static const String noSitesMessage = 'There are no Sites you can see, so there is no KPI Review to show.';

  String? _lastSiteId;

  /// The day on screen; null means "the Site's last working day" (no `date` sent).
  String? _date;

  Future<void> _onStarted(KpiReviewStarted event, Emitter<KpiReviewState> emit) async {
    _date = event.date;
    emit(const KpiReviewLoading());
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const KpiReviewUnavailable(message: signedOutMessage));
      return;
    }
    final List<Site> sites;
    try {
      sites = await _people.fetchSites(token);
    } on PeopleApiException catch (error) {
      emit(KpiReviewUnavailable(message: error.message));
      return;
    }
    if (sites.isEmpty) {
      emit(const KpiReviewUnavailable(message: noSitesMessage));
      return;
    }
    final wanted = _lastSiteId;
    final opensOn = sites.any((site) => site.id == wanted) ? wanted! : sites.first.id;
    _lastSiteId = opensOn;
    emit(KpiReviewLoaded(sites: sites, siteId: opensOn, isLoadingReview: true));
    await _readReview(opensOn, emit);
  }

  Future<void> _onSiteSelected(KpiReviewSiteSelected event, Emitter<KpiReviewState> emit) async {
    final current = state;
    if (current is! KpiReviewLoaded) return;
    _lastSiteId = event.siteId;
    // Another Site has its own today, so the day goes back to "today".
    _date = null;
    emit(current.copyWith(siteId: event.siteId, clearReview: true, clearSiteToday: true, isLoadingReview: true));
    await _readReview(event.siteId, emit);
  }

  Future<void> _onDateSelected(ReviewDateSelected event, Emitter<KpiReviewState> emit) async {
    final current = state;
    if (current is! KpiReviewLoaded) return;
    _date = event.date;
    emit(current.copyWith(clearReview: true, isLoadingReview: true));
    await _readReview(current.siteId, emit);
  }

  Future<void> _readReview(String siteId, Emitter<KpiReviewState> emit) async {
    final token = _auth.currentAccessToken;
    if (state is! KpiReviewLoaded) return;
    if (token == null) {
      emit(const KpiReviewUnavailable(message: signedOutMessage));
      return;
    }
    final date = _date;
    try {
      final review = await _api.fetchReview(token, siteId: siteId, date: date);
      final now = state;
      if (now is! KpiReviewLoaded || now.siteId != siteId || _date != date) return;
      // A read that asked for no `date` is a read of the Site's last working
      // day; the Site's today comes back as `site_today`.
      emit(now.copyWith(review: review, siteToday: date == null ? review.siteToday : null, isLoadingReview: false));
    } on KpiApiException catch (error) {
      final now = state;
      if (now is! KpiReviewLoaded || now.siteId != siteId || _date != date) return;
      emit(KpiReviewUnavailable(message: error.message));
    }
  }

  Future<void> _onSaveRequested(ReviewSaveRequested event, Emitter<KpiReviewState> emit) async {
    final current = state;
    final review = current is KpiReviewLoaded ? current.review : null;
    if (current is! KpiReviewLoaded || review == null || current.isMutating || event.entries.isEmpty) return;

    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(mutationFailure: signedOutMessage));
      return;
    }

    emit(current.copyWith(isMutating: true));
    try {
      final saved = await _api.saveReview(
        token,
        siteId: current.siteId,
        date: review.reviewDate,
        entries: event.entries,
      );
      // The day on screen, read again: an omitted date would be the Site's
      // today, which is not necessarily the day being reviewed.
      final fresh = await _api.fetchReview(token, siteId: current.siteId, date: review.reviewDate);
      emit(current.copyWith(review: fresh, isMutating: false, savedCount: saved));
    } on KpiApiException catch (error) {
      emit(current.copyWith(isMutating: false, mutationFailure: error.message));
    }
  }
}
