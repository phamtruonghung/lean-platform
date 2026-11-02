/// The Quality slide show's own state (issue #418): one Site's chosen issues,
/// flattened into the slides the wall plays, and which slide is up.
///
/// **A slide is one picture.** The API sends one entry per chosen issue with all
/// of that issue's pictures; this Bloc flattens the two so an issue with three
/// pictures is three consecutive slides with the same overlay. The flattening
/// lives here rather than in the Screen because the *timer* has to know how many
/// slides there are — a Screen that flattened would need the same count twice.
///
/// **The pictures are preloaded.** Every slide's bytes are fetched when the
/// show is read, not when the slide comes up: a wall that fetched its next
/// picture while the previous one was still showing would go blank on the frame
/// it advanced to, which is the one thing a shop-floor screen must never do.
///
/// **The timer is the Bloc's, not the widget's.** [advanceInterval] is ten
/// seconds, the card's own default and the number written in the PR; the timer
/// is started when the show is playing and there is more than one slide, and
/// cancelled on every pause, on every reload, and on close. A widget that owned
/// it would restart it on every rebuild and never finish a slide.
///
/// **Playing stops on a person's own step.** Advancing by hand (a keyboard
/// press, the next/previous control) pauses the show, so the wall does not slide
/// out from under someone who is reading that picture; the play control starts
/// it again. That is the card's own sentence and the reason it is not "resume
/// after five seconds of quiet": a half-read slide is worse than a stopped show.
///
/// **Which Site.** The show is one Site's, exactly like a register, so the state
/// carries the Site list and the Site on screen, and changing the Site re-reads
/// the show rather than filtering the old one.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../people/people.dart';
import '../people_api.dart';
import '../platform/auth_gateway.dart';
import 'issue_image.dart';
import 'quality_api.dart';

/// One picture and the issue it belongs to: what the wall actually draws.
class Slide {
  const Slide({required this.issue, required this.image});

  final SlideIssue issue;
  final IssueImage image;

  /// A stable identity across a reload, for the animated switch, the preloaded
  /// bytes and a test that wants to name the slide on screen.
  String get id => '${issue.kind}:${issue.id}:${image.id}';
}

sealed class SlideShowEvent {
  const SlideShowEvent();
}

/// Read the Sites and the first Site's show. Also the retry a failure offers.
class SlideShowStarted extends SlideShowEvent {
  const SlideShowStarted();
}

/// Re-read the show on entering the Screen, keeping the Site and the slide.
class SlideShowRefreshed extends SlideShowEvent {
  const SlideShowRefreshed();
}

class SlideShowSiteSelected extends SlideShowEvent {
  const SlideShowSiteSelected(this.siteId);

  final String siteId;
}

/// The timer's own step. Does not pause the show.
class SlideShowTicked extends SlideShowEvent {
  const SlideShowTicked();
}

/// A person asked for the next slide: pauses the show.
class SlideShowNextRequested extends SlideShowEvent {
  const SlideShowNextRequested();
}

/// A person asked for the previous slide: pauses the show.
class SlideShowPreviousRequested extends SlideShowEvent {
  const SlideShowPreviousRequested();
}

class SlideShowPlayToggled extends SlideShowEvent {
  const SlideShowPlayToggled();
}

/// One issue moved [delta] places in the running order.
class SlideShowIssueMoved extends SlideShowEvent {
  const SlideShowIssueMoved({required this.kind, required this.id, required this.delta});

  final String kind;
  final String id;
  final int delta;
}

/// One issue taken off the wall.
class SlideShowIssueRemoved extends SlideShowEvent {
  const SlideShowIssueRemoved({required this.kind, required this.id});

  final String kind;
  final String id;
}

class SlideShowFailureDismissed extends SlideShowEvent {
  const SlideShowFailureDismissed();
}

sealed class SlideShowState {
  const SlideShowState();
}

class SlideShowLoading extends SlideShowState {
  const SlideShowLoading();
}

class SlideShowUnavailable extends SlideShowState {
  const SlideShowUnavailable({required this.message});

  final String message;
}

class SlideShowLoaded extends SlideShowState {
  const SlideShowLoaded({
    required this.sites,
    required this.siteId,
    required this.issues,
    this.bytes = const {},
    this.index = 0,
    this.playing = true,
    this.isSaving = false,
    this.failure,
  });

  final List<Site> sites;

  /// The Site on screen, or null when the caller can see none.
  final String? siteId;

  /// The chosen issues in the show's own order. An issue with no picture is
  /// here too — it is chosen — but it contributes no slide.
  final List<SlideIssue> issues;

  /// Every slide's picture, by [Slide.id] — see this file's own header on why
  /// they are all read up front.
  final Map<String, Uint8List> bytes;

  /// Which slide is up.
  final int index;

  final bool playing;

  /// A re-order or a removal is in flight.
  final bool isSaving;

  final String? failure;

  /// The wall's slides: every picture of every chosen issue that has one.
  List<Slide> get slides => [
        for (final issue in issues)
          if (issue.hasPicture)
            for (final image in issue.images) Slide(issue: issue, image: image),
      ];

  /// Chosen issues with nothing to show: the picker says so, because a chosen
  /// issue that never appears is a puzzle on the wall.
  List<SlideIssue> get withoutPicture =>
      [for (final issue in issues) if (!issue.hasPicture) issue];

  Slide? get current {
    final all = slides;
    if (all.isEmpty) return null;
    return all[index.clamp(0, all.length - 1)];
  }

  Uint8List? bytesFor(Slide slide) => bytes[slide.id];

  SlideShowLoaded copyWith({
    List<Site>? sites,
    String? siteId,
    List<SlideIssue>? issues,
    Map<String, Uint8List>? bytes,
    int? index,
    bool? playing,
    bool? isSaving,
    String? failure,
  }) =>
      SlideShowLoaded(
        sites: sites ?? this.sites,
        siteId: siteId ?? this.siteId,
        issues: issues ?? this.issues,
        bytes: bytes ?? this.bytes,
        index: index ?? this.index,
        playing: playing ?? this.playing,
        isSaving: isSaving ?? this.isSaving,
        // Always overwritten, never carried forward — the rule every Loaded
        // state in this Module follows.
        failure: failure,
      );
}

class SlideShowBloc extends Bloc<SlideShowEvent, SlideShowState> {
  SlideShowBloc({
    required QualityApi qualityApi,
    required PeopleApi peopleApi,
    required AuthGateway authGateway,
    this.advanceInterval = const Duration(seconds: 10),
  })  : _api = qualityApi,
        _people = peopleApi,
        _auth = authGateway,
        super(const SlideShowLoading()) {
    on<SlideShowStarted>(_onStarted);
    on<SlideShowRefreshed>(_onRefreshed);
    on<SlideShowSiteSelected>(_onSiteSelected);
    on<SlideShowTicked>(_onTicked);
    on<SlideShowNextRequested>(_onNext);
    on<SlideShowPreviousRequested>(_onPrevious);
    on<SlideShowPlayToggled>(_onPlayToggled);
    on<SlideShowIssueMoved>(_onMoved);
    on<SlideShowIssueRemoved>(_onRemoved);
    on<SlideShowFailureDismissed>(_onFailureDismissed);
  }

  final QualityApi _api;
  final PeopleApi _people;
  final AuthGateway _auth;

  /// How long each slide stays up: ten seconds, the show's own default.
  final Duration advanceInterval;

  Timer? _timer;

  static const String signedOutMessage = 'This session has ended. Sign in again to continue.';

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }

  Future<void> _onStarted(SlideShowStarted event, Emitter<SlideShowState> emit) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SlideShowUnavailable(message: signedOutMessage));
      return;
    }
    if (state is! SlideShowLoaded) emit(const SlideShowLoading());
    try {
      final sites = await _people.fetchSites(token);
      final previous = state is SlideShowLoaded ? state as SlideShowLoaded : null;
      final siteId = previous?.siteId ?? (sites.isEmpty ? null : sites.first.id);
      if (siteId == null) {
        emit(SlideShowLoaded(sites: const [], siteId: null, issues: const []));
        _syncTimer(state);
        return;
      }
      final issues = await _api.fetchSlideShow(token, siteId);
      final bytes = await _pictures(token, issues, previous: previous?.bytes);
      emit(SlideShowLoaded(sites: sites, siteId: siteId, issues: issues, bytes: bytes));
      _syncTimer(state);
    } on QualityApiException catch (error) {
      emit(SlideShowUnavailable(message: error.message));
      _syncTimer(null);
    } on Exception catch (error) {
      // `fetchSites` throws People's own exception type; a Screen that cannot
      // show the Site list has the same failure as one that cannot show slides.
      emit(SlideShowUnavailable(message: error.toString()));
      _syncTimer(null);
    }
  }

  Future<void> _onRefreshed(SlideShowRefreshed event, Emitter<SlideShowState> emit) async {
    final current = state;
    if (current is! SlideShowLoaded || current.siteId == null) {
      return _onStarted(const SlideShowStarted(), emit);
    }
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SlideShowUnavailable(message: signedOutMessage));
      return;
    }
    try {
      final issues = await _api.fetchSlideShow(token, current.siteId!);
      final bytes = await _pictures(token, issues, previous: current.bytes);
      emit(current.copyWith(issues: issues, bytes: bytes, index: current.index));
      _syncTimer(state);
    } on QualityApiException catch (error) {
      emit(current.copyWith(failure: error.message));
    }
  }

  Future<void> _onSiteSelected(SlideShowSiteSelected event, Emitter<SlideShowState> emit) async {
    final current = state;
    if (current is! SlideShowLoaded || current.siteId == event.siteId) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(const SlideShowUnavailable(message: signedOutMessage));
      return;
    }
    emit(current.copyWith(siteId: event.siteId, issues: const [], index: 0));
    _syncTimer(state);
    try {
      final issues = await _api.fetchSlideShow(token, event.siteId);
      final bytes = await _pictures(token, issues);
      final settled = state;
      if (settled is! SlideShowLoaded) return;
      emit(settled.copyWith(issues: issues, bytes: bytes, index: 0));
      _syncTimer(state);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SlideShowLoaded) return;
      emit(settled.copyWith(failure: error.message));
    }
  }

  void _onTicked(SlideShowTicked event, Emitter<SlideShowState> emit) {
    final current = state;
    if (current is! SlideShowLoaded) return;
    final slides = current.slides;
    if (slides.length < 2) return;
    emit(current.copyWith(index: (current.index + 1) % slides.length));
  }

  void _onNext(SlideShowNextRequested event, Emitter<SlideShowState> emit) {
    final current = state;
    if (current is! SlideShowLoaded) return;
    final slides = current.slides;
    if (slides.isEmpty) return;
    emit(current.copyWith(index: (current.index + 1) % slides.length, playing: false));
    _syncTimer(state);
  }

  void _onPrevious(SlideShowPreviousRequested event, Emitter<SlideShowState> emit) {
    final current = state;
    if (current is! SlideShowLoaded) return;
    final slides = current.slides;
    if (slides.isEmpty) return;
    emit(current.copyWith(index: (current.index - 1) % slides.length, playing: false));
    _syncTimer(state);
  }

  void _onPlayToggled(SlideShowPlayToggled event, Emitter<SlideShowState> emit) {
    final current = state;
    if (current is! SlideShowLoaded) return;
    emit(current.copyWith(playing: !current.playing));
    _syncTimer(state);
  }

  void _onFailureDismissed(SlideShowFailureDismissed event, Emitter<SlideShowState> emit) {
    final current = state;
    if (current is! SlideShowLoaded) return;
    emit(current.copyWith());
  }

  Future<void> _onMoved(SlideShowIssueMoved event, Emitter<SlideShowState> emit) async {
    final current = state;
    if (current is! SlideShowLoaded || current.siteId == null || current.isSaving) return;
    final order = [for (final issue in current.issues) (kind: issue.kind, id: issue.id)];
    final from = order.indexWhere((entry) => entry.kind == event.kind && entry.id == event.id);
    if (from < 0) return;
    final to = (from + event.delta).clamp(0, order.length - 1);
    if (to == from) return;
    final moved = order.removeAt(from);
    order.insert(to, moved);
    await _writeOrder(current, order, emit);
  }

  Future<void> _onRemoved(SlideShowIssueRemoved event, Emitter<SlideShowState> emit) async {
    final current = state;
    if (current is! SlideShowLoaded || current.siteId == null || current.isSaving) return;
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(failure: signedOutMessage));
      return;
    }
    emit(current.copyWith(isSaving: true));
    try {
      await _api.setSlideShowChoice(token, event.kind, event.id, false);
      final issues = await _api.fetchSlideShow(token, current.siteId!);
      final bytes = await _pictures(token, issues, previous: current.bytes);
      final settled = state;
      if (settled is! SlideShowLoaded) return;
      emit(settled.copyWith(issues: issues, bytes: bytes, index: 0, isSaving: false));
      _syncTimer(state);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SlideShowLoaded) return;
      emit(settled.copyWith(isSaving: false, failure: error.message));
    }
  }

  Future<void> _writeOrder(
    SlideShowLoaded current,
    List<({String kind, String id})> order,
    Emitter<SlideShowState> emit,
  ) async {
    final token = _auth.currentAccessToken;
    if (token == null) {
      emit(current.copyWith(failure: signedOutMessage));
      return;
    }
    emit(current.copyWith(isSaving: true));
    try {
      final issues = await _api.setSlideShowOrder(token, current.siteId!, order);
      final bytes = await _pictures(token, issues, previous: current.bytes);
      final settled = state;
      if (settled is! SlideShowLoaded) return;
      emit(settled.copyWith(issues: issues, bytes: bytes, isSaving: false, index: 0));
      _syncTimer(state);
    } on QualityApiException catch (error) {
      final settled = state;
      if (settled is! SlideShowLoaded) return;
      emit(settled.copyWith(isSaving: false, failure: error.message));
    }
  }

  /// Every slide's picture, keeping anything already read. One failure does not
  /// sink the wall: that slide draws its overlay without a picture, and the
  /// person can reload.
  Future<Map<String, Uint8List>> _pictures(
    String token,
    List<SlideIssue> issues, {
    Map<String, Uint8List>? previous,
  }) async {
    final bytes = <String, Uint8List>{};
    await Future.wait([
      for (final issue in issues)
        for (final image in issue.images)
          () async {
            final id = '${issue.kind}:${issue.id}:${image.id}';
            final kept = previous?[id];
            if (kept != null) {
              bytes[id] = kept;
              return;
            }
            try {
              bytes[id] = await _api.fetchIssueImageBytes(token, issue.kind, issue.id, image.id);
            } on QualityApiException {
              // Absent rather than empty; the slide says so.
            }
          }(),
    ]);
    return bytes;
  }

  /// Starts or stops the clock to match [state]: playing, on a Site, with more
  /// than one slide to move between.
  void _syncTimer(SlideShowState? state) {
    final loaded = state is SlideShowLoaded ? state : null;
    final wanted = loaded != null && loaded.playing && loaded.slides.length > 1;
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(advanceInterval, (_) => add(const SlideShowTicked()));
  }
}
