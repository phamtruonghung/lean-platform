/// What a caller gets at a real address their role does not earn.
///
/// Deliberately not the not-found Screen. The backend already settled this
/// order for itself (`authorization.js`: existence first, scope second) — a
/// 404 there is reserved for a thing that genuinely is not there, and a
/// refusal says so plainly with a 403. The same reasoning holds here: the
/// Approval queue's address is part of the Platform's own published surface,
/// not a secret an id could leak, so pretending it does not exist would only
/// leave a non-administrator debugging a broken link.
///
/// **The composition** is the one issue #396 gave all five platform states: a
/// bounded 460px card at the centre of the canvas, a 40px mark, the title and
/// sentence in the shared `AppPageHeader` rhythm, and the way out at the
/// `AppTouchTarget.min` floor. A refusal is not a fault, so the mark wears the
/// palette's neutral tile rather than a red one — red is reserved for faults,
/// exactly as `StatusTone` reserves it — and the sentence still says who to ask.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import '../widgets/app_page_header.dart';
import 'router.dart';

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  static const ValueKey<String> homeKey = ValueKey<String>('access-denied-home');

  static const double markSize = 40;
  static const double markRadius = 10;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Platform')),
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
                        child: Icon(Icons.lock_outline, color: palette.navSelectedForeground),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    const AppPageHeader(
                      title: 'Not available to you',
                      description: 'This part of the Platform is for administrators. Ask one '
                          'if you need what is here.',
                    ),
                    const SizedBox(height: Spacing.lg),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        key: homeKey,
                        onPressed: () => context.go(Routes.home),
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('Back to Home'),
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
