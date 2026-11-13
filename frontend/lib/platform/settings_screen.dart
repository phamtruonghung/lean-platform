/// Settings: the personal choices that are not about any one Module
/// (issue t_c68dfd6e).
///
/// **What is here today is the language switch** — English or Vietnamese,
/// applied across the whole Platform at once and remembered on this browser.
/// The palette has its own control in the Shell's footer and the account menu
/// (issues #366, #415), so it is deliberately *not* duplicated here: two
/// controls over one setting is how they drift apart.
///
/// **Reached as a Destination, not a dialog**, because it is a Screen by
/// CONTEXT.md's own definition — it has an address (`/settings`), it can be
/// bookmarked, and a person navigates to it to do one thing. It is offered to
/// every admitted Account (`destinations.dart`), ungrouped beneath Home: which
/// language you read is not an administrative privilege.
///
/// **The switch applies immediately.** The control writes to `LocaleCubit`,
/// which [PlatformApp] hands to `MaterialApp.locale`; the same frame rebuild
/// re-renders the Shell and every Screen with the new catalogue. Nothing here
/// reloads the page, and nothing waits on storage: a store that refuses the
/// write still changes the language on screen (see `LocaleCubit.setLocale`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_list_card.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import 'locale_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const double maxWidth = AppLayout.pageWidth;

  /// The row that owns the language control.
  static const ValueKey<String> languageKey = ValueKey<String>('settings-language');

  /// One option inside that control, keyed by the language code it sets, so a
  /// test taps "Vietnamese" without matching on translated text.
  static ValueKey<String> languageOptionKey(String languageCode) =>
      ValueKey<String>('settings-language-$languageCode');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = context.watch<LocaleCubit>().state;
    final theme = Theme.of(context);
    final palette = AppColors.of(context);

    return Scaffold(
      body: Center(
        child: AppPageFrame(
          maxWidth: maxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
            children: [
              AppPageHeader(title: l10n.settingsTitle, description: l10n.settingsDescription),
              const SizedBox(height: Spacing.md),
              AppListCard(
                rows: [
                  Padding(
                    key: languageKey,
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.settingsLanguage,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: Spacing.xxs),
                        // The help line is `bodySmall`, the Platform's own type
                        // floor, in the muted tone a description takes
                        // everywhere else (`AppPageHeader` does the same).
                        Text(
                          l10n.settingsLanguageHelp,
                          style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                        ),
                        const SizedBox(height: Spacing.md),
                        // Two options, always visible rather than behind a
                        // dropdown: there are exactly two, and a segmented
                        // control says which one is on without being opened.
                        // `showSelectedIcon: false` keeps both labels on one
                        // line at the narrowest window the Shell allows.
                        SegmentedButton<Locale>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment<Locale>(
                              value: LocaleCubit.english,
                              label: Text(
                                l10n.settingsLanguageEnglish,
                                key: languageOptionKey('en'),
                              ),
                            ),
                            ButtonSegment<Locale>(
                              value: LocaleCubit.vietnamese,
                              label: Text(
                                l10n.settingsLanguageVietnamese,
                                key: languageOptionKey('vi'),
                              ),
                            ),
                          ],
                          selected: {locale},
                          onSelectionChanged: (selection) =>
                              context.read<LocaleCubit>().setLocale(selection.single),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
