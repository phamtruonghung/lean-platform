/// The platform's own "there is nothing here" state (issue #396's design pass).
///
/// **What a centred state owes.** This is one of the five Screens a person sees
/// when something is wrong, and the design pass gave all five the same
/// composition rather than five hand-rolled ones: a bounded 460px card at the
/// centre of the canvas, a 40px mark, the Screen's title and its sentence in
/// the shared `AppPageHeader` rhythm every other page uses, and one row of
/// actions at the `AppTouchTarget.min` floor. Nothing is invented to fill the
/// card — no illustration, no second paragraph — because a state a person meets
/// in passing should cost them one read, and the action that resolves it should
/// be the second thing they see.
///
/// **The way out.** A missing address has no fix of its own, so the one action
/// offered is the way back into the product: `Back to Home`. The sentence
/// naming the address is unchanged. `page_alignment_test.dart` records why
/// these five are centred blocks rather than one-left-edge pages.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_page_header.dart';
import 'router.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  final String location;

  static const ValueKey<String> homeKey = ValueKey<String>('not-found-home');

  /// The mark's own square: `AppStatTile`'s icon tile is the same 40 at the
  /// same 10 radius, so a state and a tile read as the same kind of thing.
  static const double markSize = 40;
  static const double markRadius = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shellBrand)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Card(
              // A `Card`'s own 4px margin would inset the block off the bound
              // it was given; the padding is the block's, and the margin is
              // zero (issue #396).
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: markSize,
                        height: markSize,
                        decoration: BoxDecoration(
                          color: palette.navSelectedBackground,
                          borderRadius: BorderRadius.circular(markRadius),
                        ),
                        child: Icon(Icons.help_outline, color: palette.navSelectedForeground),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    AppPageHeader(
                      title: l10n.notFoundScreenNotFound,
                      description: l10n.notFoundThereIsNothingAt(location),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        key: homeKey,
                        onPressed: () => context.go(Routes.home),
                        icon: const Icon(Icons.home_outlined),
                        label: Text(l10n.commonBackToHome),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
