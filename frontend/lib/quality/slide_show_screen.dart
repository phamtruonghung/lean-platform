/// The Quality slide show (issue #419): one Site's chosen issues, one picture
/// at a time, on a loop.
///
/// **It is a Screen, not a kiosk mode.** It has an address, it sits under the
/// Quality group in the Shell, and the Site, the running order and the
/// play/pause are its own controls — a supervisor opens it, sets it going and
/// leaves it on the wall. Nothing about it is modal and nothing about it hides
/// the rest of the Platform.
///
/// **What a slide shows**: the picture, filling the box; and over it, in the
/// plant's own words, the issue's number and type, the Customer or the Org Unit
/// it belongs to, its state, its age and the picture's caption. That is the set
/// the card names, and each is a fact a person standing in front of the screen
/// asks in that order.
///
/// **Controls, and why they are where they are.** Play/pause and "Choose the
/// order" live in the page header, above the show; next/previous are keyboard
/// (`←`/`→`, and `Space` to play or pause) and two buttons beside the overlay
/// for a touch screen. Any manual step pauses — see `slide_show_bloc.dart`'s own
/// header for that decision.
///
/// **Motion is optional and short.** The slide change is a 200 ms cross-fade,
/// and under `MediaQuery.disableAnimationsOf` it is `Duration.zero`, so a
/// reader who asked their system not to animate gets a cut rather than a fade
/// (design-language §8). The image itself never animates.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_banner.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_filter_row.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'issue_image.dart';
import 'slide_show_bloc.dart';

class SlideShowScreen extends StatelessWidget {
  const SlideShowScreen({super.key});

  static const double maxWidth = 1400;

  /// Below this box width, at the reader's text scale, the overlay becomes a
  /// plain block under the picture rather than a card laid over it: on a narrow
  /// box an overlay covers the part of the picture the reader is looking at.
  static const double overlayBreakpoint = 700;

  static const ValueKey<String> siteKey = ValueKey<String>('slide-show-site');
  static const ValueKey<String> playKey = ValueKey<String>('slide-show-play');
  static const ValueKey<String> orderKey = ValueKey<String>('slide-show-order');
  static const ValueKey<String> emptyKey = ValueKey<String>('slide-show-empty');
  static const ValueKey<String> noPictureKey = ValueKey<String>('slide-show-no-picture');
  static const ValueKey<String> failedKey = ValueKey<String>('slide-show-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('slide-show-retry');
  static const ValueKey<String> previousKey = ValueKey<String>('slide-show-previous');
  static const ValueKey<String> nextKey = ValueKey<String>('slide-show-next');
  static const ValueKey<String> slideKey = ValueKey<String>('slide-show-slide');
  static const ValueKey<String> factsKey = ValueKey<String>('slide-show-facts');
  static const ValueKey<String> captionKey = ValueKey<String>('slide-show-caption');
  static const ValueKey<String> orderDialogKey = ValueKey<String>('slide-show-order-dialog');
  static const ValueKey<String> orderSaveFailedKey = ValueKey<String>('slide-show-order-failed');

  static ValueKey<String> orderRowKey(String kind, String id) =>
      ValueKey<String>('slide-show-order-$kind-$id');
  static ValueKey<String> orderUpKey(String kind, String id) =>
      ValueKey<String>('slide-show-order-up-$kind-$id');
  static ValueKey<String> orderDownKey(String kind, String id) =>
      ValueKey<String>('slide-show-order-down-$kind-$id');
  static ValueKey<String> orderRemoveKey(String kind, String id) =>
      ValueKey<String>('slide-show-order-remove-$kind-$id');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<SlideShowBloc>().state;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          // A wall fills the box it is given; a phone scrolls, because a page
          // header, a picture and the facts under it cannot all fit in 500 px
          // at twice the text, and a picture cropped to nothing is worse than
          // one a reader scrolls to.
          final fill = box.maxHeight >= 560;
          final body = switch (state) {
            SlideShowLoading() => const SkeletonList(rows: 3, maxWidth: maxWidth),
            SlideShowUnavailable(message: final message) => Center(
                child: PlatformFailureState(
                  key: failedKey,
                  title: l10n.slideShowTheSlideShowCouldNotBeRead,
                  message: message,
                  retryKey: retryKey,
                  onRetry: () => context.read<SlideShowBloc>().add(const SlideShowStarted()),
                ),
              ),
            SlideShowLoaded() => _Show(state: state, fill: fill),
          };
          final children = <Widget>[
            _Header(state: state),
            if (state is SlideShowLoaded && state.failure != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
                child: Center(
                  child: AppPageFrame(
                    maxWidth: maxWidth,
                    child: AppBanner(
                      tone: StatusTone.danger,
                      message: state.failure!,
                      onDismiss: () =>
                          context.read<SlideShowBloc>().add(const SlideShowFailureDismissed()),
                    ),
                  ),
                ),
              ),
            if (fill) Expanded(child: body) else body,
          ];
          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: children,
          );
          return fill ? column : SingleChildScrollView(child: column);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SlideShowState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = state is SlideShowLoaded ? state as SlideShowLoaded : null;
    return Center(
      child: AppPageFrame(
        maxWidth: SlideShowScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: l10n.titleQualitySlideShow,
            description:
                l10n.slideShowTheQualityIssuesChosenForThisSite,
            actions: [
              if (loaded != null && loaded.slides.length > 1)
                IconButton.filledTonal(
                  key: SlideShowScreen.playKey,
                  tooltip: loaded.playing ? l10n.slideShowPauseTheShow : l10n.slideShowPlayTheShow,
                  onPressed: () =>
                      context.read<SlideShowBloc>().add(const SlideShowPlayToggled()),
                  icon: Icon(loaded.playing ? Icons.pause : Icons.play_arrow),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                ),
              if (loaded != null)
                OutlinedButton.icon(
                  key: SlideShowScreen.orderKey,
                  onPressed: loaded.isSaving ? null : () => _openOrder(context, loaded),
                  icon: const Icon(Icons.format_list_numbered),
                  label: Text(l10n.slideShowChooseTheOrder),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                ),
            ],
            below: loaded == null || loaded.sites.length < 2
                ? null
                : AppFilterRow(
                    children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          key: SlideShowScreen.siteKey,
                          initialValue: loaded.siteId,
                          isDense: true,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.commonSite,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final site in loaded.sites)
                              DropdownMenuItem<String>(
                                value: site.id,
                                child: Text(site.name),
                              ),
                          ],
                          onChanged: (siteId) {
                            if (siteId == null) return;
                            context
                                .read<SlideShowBloc>()
                                .add(SlideShowSiteSelected(siteId));
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _openOrder(BuildContext context, SlideShowLoaded loaded) {
    final bloc = context.read<SlideShowBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<SlideShowBloc>.value(
        value: bloc,
        child: const _OrderDialog(),
      ),
    );
  }
}

class _Show extends StatelessWidget {
  const _Show({required this.state, required this.fill});

  final SlideShowLoaded state;

  /// True when the page fills its box. False means the page scrolls and the
  /// picture is given a height of its own — an `Expanded` inside a scroll view
  /// has nothing to expand into.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = state.slides;
    if (slides.isEmpty) {
      final chosen = state.withoutPicture;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: chosen.isEmpty
                ? PlatformEmptyState.noneExist(
                    key: SlideShowScreen.emptyKey,
                    title: l10n.slideShowNothingIsOnTheWallYet,
                    message:
                        l10n.slideShowChooseACustomerComplaintOrANon,
                    icon: Icons.slideshow_outlined,
                  )
                : PlatformEmptyState.noneExist(
                    key: SlideShowScreen.noPictureKey,
                    title: l10n.slideShowChosenNoneWithAPicture(chosen.length),
                    message:
                        l10n.slideShowASlideNeedsAPictureOpenAnd(chosen.length == 1 ? 'that issue' : 'those issues', chosen.length == 1 ? 'it' : 'they'),
                    icon: Icons.image_not_supported_outlined,
                  ),
        ),
      );
    }

    final slide = state.current;
    final bytes = slide == null ? null : state.bytesFor(slide);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (fill)
          Expanded(
            child: _Slides(state: state, slide: slide, bytes: bytes),
          )
        else
          // 320 of picture at 1x: enough for a phone to show the problem and
          // keep the facts under it visible, and the page scrolls for the rest.
          SizedBox(
            height: 320,
            child: _Slides(state: state, slide: slide, bytes: bytes),
          ),
        _Controls(state: state),
      ],
    );
  }
}

/// The picture and its facts, laid out for the box they are given.
class _Slides extends StatelessWidget {
  const _Slides({required this.state, required this.slide, required this.bytes});

  final SlideShowLoaded state;
  final Slide? slide;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >
            AppBreakpoints.effective(context, SlideShowScreen.overlayBreakpoint);
        final picture = _Picture(
          key: SlideShowScreen.slideKey,
          slide: slide,
          bytes: bytes,
          animate: !MediaQuery.disableAnimationsOf(context),
        );
        final overlay = _Overlay(state: state, slide: slide, compact: !wide);
        if (!wide) {
          // The overlay never takes more than a little over half the slide's
          // own height: at twice the text in a small box it is taller than the
          // picture it describes, and a Column that lets it take its intrinsic
          // height overflows the box instead of shrinking the picture. Capped,
          // it scrolls within its half and the picture keeps the rest.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: picture),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (constraints.maxHeight * 0.55).clamp(0, double.infinity),
                ),
                child: SingleChildScrollView(child: overlay),
              ),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            picture,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: overlay,
            ),
          ],
        );
      },
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({super.key, required this.slide, required this.bytes, required this.animate});

  final Slide? slide;
  final Uint8List? bytes;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    if (slide == null) return const SizedBox.shrink();

    final image = bytes == null
        ? ColoredBox(
            color: palette.surfaceMuted,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: palette.textMuted,
                semanticLabel: l10n.commonThePictureCouldNotBeLoaded,
              ),
            ),
          )
        : Image.memory(
            bytes!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            semanticLabel: slide!.image.caption ?? l10n.slideShowAPictureOf(slide!.issue.number),
          );

    void onNext() => context.read<SlideShowBloc>().add(const SlideShowNextRequested());
    void onPrevious() =>
        context.read<SlideShowBloc>().add(const SlideShowPreviousRequested());

    final body = Semantics(
      label: '${slide!.issue.number}, ${IssueKind.label(slide!.issue.kind)}',
      child: ColoredBox(color: palette.surfaceMuted, child: Center(child: image)),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onNext,
      onLongPress: onPrevious,
      child: animate
          ? AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey<String>(slide!.id), child: body),
            )
          : body,
    );
  }
}

/// The facts over the picture: what this is, and how old it is.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.state, required this.slide, required this.compact});

  final SlideShowLoaded state;
  final Slide? slide;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppColors.of(context);
    if (slide == null) return const SizedBox.shrink();
    final issue = slide!.issue;

    final chips = Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusChip(label: issue.typeLabel, tone: IssueKind.tone(issue.kind)),
        StatusChip(label: issue.status, tone: StatusTone.neutral),
        Text(
          issueAgeLabel(issue.occurredAt),
          style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          issue.number,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (issue.subject.isNotEmpty) ...[
          const SizedBox(height: Spacing.xxs),
          Text(issue.subject, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Spacing.sm),
        chips,
        if (slide!.image.caption != null) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            slide!.image.caption!,
            key: SlideShowScreen.captionKey,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );

    return Container(
      key: SlideShowScreen.factsKey,
      width: double.infinity,
      color: palette.card,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Spacing.lg : Spacing.xl,
        vertical: Spacing.lg,
      ),
      child: content,
    );
  }
}

/// Previous, the position, and next — for a touch screen, and the same acts the
/// arrow keys do.
class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final SlideShowLoaded state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final slides = state.slides;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
      child: Center(
        child: Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              key: SlideShowScreen.previousKey,
              tooltip: l10n.slideShowPreviousSlide,
              onPressed: slides.isEmpty
                  ? null
                  : () => context
                      .read<SlideShowBloc>()
                      .add(const SlideShowPreviousRequested()),
              icon: const Icon(Icons.chevron_left),
              style: IconButton.styleFrom(
                minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
              ),
            ),
            Text(
              slides.isEmpty ? l10n.slideShowNoSlides : '${state.index + 1} of ${slides.length}',
              style: theme.textTheme.bodyMedium,
            ),
            IconButton(
              key: SlideShowScreen.nextKey,
              tooltip: l10n.slideShowNextSlide,
              onPressed: slides.isEmpty
                  ? null
                  : () => context.read<SlideShowBloc>().add(const SlideShowNextRequested()),
              icon: const Icon(Icons.chevron_right),
              style: IconButton.styleFrom(
                minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
              ),
            ),
            if (state.withoutPicture.isNotEmpty)
              Text(
                l10n.slideShowChosenWithoutAPicture(state.withoutPicture.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.of(context).textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The running order: move an issue up or down, or take it off the wall.
class _OrderDialog extends StatelessWidget {
  const _OrderDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<SlideShowBloc, SlideShowState>(
      builder: (context, state) {
        if (state is! SlideShowLoaded) {
          return AppDialog(
            key: SlideShowScreen.orderDialogKey,
            title: l10n.slideShowTheOrderTheShowPlaysIn,
            size: AppDialogSize.form,
            actions: [
              AppDialogAction(
                id: 'quality-slide-order-close',
                label: l10n.floorTrainingDone,
                kind: AppDialogActionKind.dismiss,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            child: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          );
        }
        final issues = state.issues;
        return AppDialog(
          key: SlideShowScreen.orderDialogKey,
          title: l10n.slideShowTheOrderTheShowPlaysIn,
          size: AppDialogSize.form,
          actions: [
            AppDialogAction(
              id: 'quality-slide-order-done',
              label: l10n.floorTrainingDone,
              kind: AppDialogActionKind.dismiss,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (issues.isEmpty)
                Text(l10n.slideShowNothingIsChosenYet)
              else
                for (var index = 0; index < issues.length; index++)
                  ListTile(
                    key: SlideShowScreen.orderRowKey(issues[index].kind, issues[index].id),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${index + 1}. ${issues[index].number} '
                      '(${IssueKind.label(issues[index].kind)})',
                    ),
                    subtitle: Text(
                      issues[index].hasPicture
                          ? l10n.slideShowPicture(issues[index].images.length, issues[index].images.length == 1 ? '' : 's')
                          : l10n.slideShowNoPictureYetItWillNotAppear,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: SlideShowScreen.orderUpKey(
                              issues[index].kind, issues[index].id),
                          tooltip: l10n.slideShowMoveEarlier,
                          onPressed: index == 0 || state.isSaving
                              ? null
                              : () => context.read<SlideShowBloc>().add(
                                    SlideShowIssueMoved(
                                      kind: issues[index].kind,
                                      id: issues[index].id,
                                      delta: -1,
                                    ),
                                  ),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          key: SlideShowScreen.orderDownKey(
                              issues[index].kind, issues[index].id),
                          tooltip: l10n.slideShowMoveLater,
                          onPressed: index == issues.length - 1 || state.isSaving
                              ? null
                              : () => context.read<SlideShowBloc>().add(
                                    SlideShowIssueMoved(
                                      kind: issues[index].kind,
                                      id: issues[index].id,
                                      delta: 1,
                                    ),
                                  ),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          key: SlideShowScreen.orderRemoveKey(
                              issues[index].kind, issues[index].id),
                          tooltip: l10n.slideShowTakeOffTheWall,
                          onPressed: state.isSaving
                              ? null
                              : () => context.read<SlideShowBloc>().add(
                                    SlideShowIssueRemoved(
                                      kind: issues[index].kind,
                                      id: issues[index].id,
                                    ),
                                  ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
              if (state.failure != null)
                Padding(
                  key: SlideShowScreen.orderSaveFailedKey,
                  padding: const EdgeInsets.only(top: Spacing.md),
                  child: Text(
                    state.failure!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The keys the show answers, so a supervisor with a keyboard does not have to
/// aim at a button: `→` and `←` step and pause, `Space` plays or pauses, and
/// `Esc` leaves for the Quality register — the same address a Back control
/// would take, because every navigation in this client replaces the location
/// rather than popping a page.
class SlideShowShortcuts extends StatelessWidget {
  const SlideShowShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<SlideShowBloc>();
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousIntent(),
        SingleActivator(LogicalKeyboardKey.space): _PlayIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _LeaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NextIntent: CallbackAction<_NextIntent>(
            onInvoke: (_) => bloc.add(const SlideShowNextRequested()),
          ),
          _PreviousIntent: CallbackAction<_PreviousIntent>(
            onInvoke: (_) => bloc.add(const SlideShowPreviousRequested()),
          ),
          _PlayIntent: CallbackAction<_PlayIntent>(
            onInvoke: (_) => bloc.add(const SlideShowPlayToggled()),
          ),
          _LeaveIntent: CallbackAction<_LeaveIntent>(
            onInvoke: (_) {
              GoRouter.of(context).go(Routes.nonConformances);
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _PreviousIntent extends Intent {
  const _PreviousIntent();
}

class _PlayIntent extends Intent {
  const _PlayIntent();
}

class _LeaveIntent extends Intent {
  const _LeaveIntent();
}
