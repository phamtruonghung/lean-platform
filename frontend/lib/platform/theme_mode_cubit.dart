import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which palette the Platform wears: the light one, the dark one, or whichever
/// the browser asks for (issue #366, ADR-0056).
///
/// **A `Cubit`, deliberately.** `AGENTS.md` §7 asks for a `Bloc` with an
/// explicit event type for every Screen-driving state machine. This is not
/// one: it drives no Screen, it holds one three-valued setting that
/// [PlatformApp] hands to `MaterialApp`, and an event type here would be
/// ceremony around a single assignment. It is the exception that sentence
/// leaves room for, not a new convention for Screens.
///
/// **Only an explicit choice is stored.** A person who has never chosen has
/// nothing stored and gets [ThemeMode.system], so the Platform keeps following
/// the browser. The key holds `system`, `light` or `dark`; an absent or
/// unrecognised value reads as `system` and never throws.
///
/// **The first frame never waits on storage.** The cubit starts at
/// [ThemeMode.system] and emits the stored value when the read lands. That read
/// can fail (no storage plugin, a blocked store) and degrades to `system`
/// silently; it can land after [close]; and it can land after the person has
/// already chosen — none of those is allowed to throw or to overwrite a newer
/// choice.
class ThemeModeCubit extends Cubit<ThemeMode> {
  ThemeModeCubit() : super(ThemeMode.system) {
    _restore();
  }

  /// The `shared_preferences` key — the same store `LocalAuthGateway` keeps
  /// the session in.
  static const String storageKey = 'platform.theme_mode';

  /// Set once the person picks a mode in this session, so a slower stored read
  /// cannot overwrite it.
  bool _chosen = false;

  Future<void> _restore() async {
    ThemeMode stored;
    try {
      final prefs = await SharedPreferences.getInstance();
      stored = _decode(prefs.getString(storageKey));
    } catch (_) {
      // No storage to read: the default is the system's own.
      return;
    }
    if (isClosed || _chosen) return;
    emit(stored);
  }

  /// Chooses [mode], remembers it, and applies it.
  ///
  /// The mode is applied even if remembering it fails: the person asked for it
  /// now, and a store that will not write must not make the switch do nothing.
  Future<void> setMode(ThemeMode mode) async {
    _chosen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, _encode(mode));
    } catch (_) {
      // Not remembered across a reload; still applied below.
    }
    if (isClosed) return;
    emit(mode);
  }

  /// Switches to the other palette from the one on screen: dark becomes
  /// light, anything else becomes dark. [platformBrightness] is what the
  /// browser asks for, needed because [ThemeMode.system] is not itself either.
  Future<void> toggle(Brightness platformBrightness) {
    final effective = switch (state) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    return setMode(effective == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  static ThemeMode _decode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
