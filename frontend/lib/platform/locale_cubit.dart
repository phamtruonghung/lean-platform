import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which language the Platform speaks: English or Vietnamese (issue t_c68dfd6e).
///
/// **A `Cubit`, deliberately**, for the reason [ThemeModeCubit] records: it
/// drives no Screen — it holds one two-valued setting that [PlatformApp] hands
/// to `MaterialApp`, and an explicit event type would be ceremony around a
/// single assignment. `AGENTS.md` §7 asks for a `Bloc` for every
/// Screen-driving state machine; this is not one. The Settings Screen reads it
/// and asks it to change; it owns no state of its own.
///
/// **English is the default, and that is the no-change answer.** Before this
/// cubit existed the client had no localisation at all, so every Account saw
/// the English strings whatever their browser asked for. Defaulting to
/// [english] keeps that exactly true for an Account who has never chosen;
/// Vietnamese is applied only because someone asked for it, and only then is
/// anything written to storage. (The card that asked for this switch expected
/// the shipped default to be Vietnamese. It is not: the shipped UI is English.
/// Flipping [defaultLocale] is the whole change if the plant decides
/// otherwise — see the hand-off comment on the card.)
///
/// **Only an explicit choice is stored.** The key holds `en` or `vi`; an
/// absent or unrecognised value reads as [english] and never throws. A stored
/// preference is never overwritten by anything but a newer choice — a slower
/// read landing after the person has already picked must not undo their pick,
/// which is what [_chosen] guards, the same guard [ThemeModeCubit] keeps.
///
/// **The first frame never waits on storage.** The cubit starts at
/// [defaultLocale] and emits the stored value when the read lands. That read
/// can fail (no storage plugin, a blocked store) and degrades to the default
/// silently; it can land after [close]; none of those is allowed to throw.
class LocaleCubit extends Cubit<Locale> {
  LocaleCubit() : super(defaultLocale) {
    _restore();
  }

  /// The `shared_preferences` key — the same store [ThemeModeCubit] and
  /// `LocalAuthGateway` keep their own values in.
  static const String storageKey = 'platform.locale';

  static const Locale english = Locale('en');
  static const Locale vietnamese = Locale('vi');

  /// The language the Platform speaks for an Account who has never chosen.
  static const Locale defaultLocale = english;

  /// The languages this build carries a catalogue for — the same two
  /// `AppLocalizations.supportedLocales` names, so a `Locale` this cubit hands
  /// out is always one the app can render.
  static const List<Locale> supportedLocales = [english, vietnamese];

  /// Set once the person picks a language in this session, so a slower stored
  /// read cannot overwrite it.
  bool _chosen = false;

  Future<void> _restore() async {
    Locale stored;
    try {
      final prefs = await SharedPreferences.getInstance();
      stored = decode(prefs.getString(storageKey));
    } catch (_) {
      // No storage to read: the default is the shipped language.
      return;
    }
    if (isClosed || _chosen) return;
    emit(stored);
  }

  /// Speaks [locale] from now on, and remembers it.
  ///
  /// Applied even if remembering it fails: the person asked for it now, and a
  /// store that will not write must not make the switch do nothing.
  Future<void> setLocale(Locale locale) async {
    final supported = _supported(locale);
    _chosen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encode(supported));
    } catch (_) {
      // Not remembered across a reload; still applied below.
    }
    if (isClosed) return;
    emit(supported);
  }

  /// The stored value for [locale] — `en` or `vi`.
  static String encode(Locale locale) => _supported(locale).languageCode;

  /// The language [value] names, or [defaultLocale] for a value this build does
  /// not carry — an old key, a hand-edited one, or nothing stored at all.
  static Locale decode(String? value) => switch (value) {
        'vi' => vietnamese,
        _ => defaultLocale,
      };

  /// [locale] narrowed to one this build carries: only the language code
  /// matters (`vi_VN` is Vietnamese), and anything else is the default rather
  /// than a `Locale` no catalogue answers.
  static Locale _supported(Locale locale) =>
      locale.languageCode == vietnamese.languageCode ? vietnamese : english;
}
