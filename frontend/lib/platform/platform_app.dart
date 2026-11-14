import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../kpi/kpi_api.dart';
import '../l10n/app_localizations.dart';
import '../maintenance/maintenance_api.dart';
import '../actions/actions_api.dart';
import '../people_api.dart';
import '../production/production_api.dart';
import '../quality/quality_api.dart';
import '../quality/quality_photo_picker.dart';
import '../safety/safety_api.dart';
import '../theme.dart';
import '../widgets/signature_file_picker.dart';
import 'account_bloc.dart';
import 'auth_gateway.dart';
import 'document_chrome.dart';
import 'floor_device_gateway.dart';
import 'locale_cubit.dart';
import 'router.dart';
import 'session_error_screen.dart';
import 'theme_mode_cubit.dart';

class PlatformApp extends StatefulWidget {
  const PlatformApp({
    super.key,
    required this.authGateway,
    required this.peopleApi,
    required this.maintenanceApi,
    required this.actionsApi,
    required this.qualityApi,
    required this.safetyApi,
    required this.productionApi,
    required this.kpiApi,
    this.floorDeviceGateway = const ConfiguredFloorDeviceGateway(),
    this.signatureFilePicker,
    this.qualityPhotoPicker,
    this.documentChrome,
    this.initialLocation,
  });

  final AuthGateway authGateway;
  final PeopleApi peopleApi;
  final MaintenanceApi maintenanceApi;
  final ActionsApi actionsApi;

  /// The Quality Module's own client (issue #203) — a Module of its own rather
  /// than a corner of one of the three above, the same seam ADR-0012 draws on
  /// the server (ADR-0006).
  final QualityApi qualityApi;

  /// The Safety Module's own client (issue #226) — a Module of its own for
  /// the same reason [qualityApi] is.
  final SafetyApi safetyApi;

  /// The Production Module's own client (issue #339) — the Shift handover —
  /// a Module of its own for the same reason [qualityApi] is.
  final ProductionApi productionApi;

  /// The KPI Module's own client (ADR-0055) — the MTU catalogue, its Targets
  /// and the daily KPI Review — a Module of its own for the same reason
  /// [qualityApi] is.
  final KpiApi kpiApi;

  /// The shared floor device's own credential, if this build was provisioned
  /// with one (issue #77). A build with none still serves the surface; it shows
  /// the not-registered state rather than pretending to be a device.
  final FloorDeviceGateway floorDeviceGateway;

  /// How a person chooses a picture of their Signature (issue #317). Left
  /// null, the platform's own picker is used (the browser's file input on the
  /// web); a widget test supplies one that answers without a browser.
  final SignatureFilePicker? signatureFilePicker;

  /// How a person chooses a picture of a Quality issue (issue #419) — the same
  /// seam as [signatureFilePicker], and supplied by a test for the same reason.
  final QualityPhotoPicker? qualityPhotoPicker;

  /// The document around the app — the tab's title and the browser's own
  /// chrome colour (issue #399). Left null, the browser's document is used; a
  /// widget test supplies one that records what it was told, because there is
  /// no document on the VM it runs on.
  final DocumentChrome? documentChrome;

  /// Supplied only by tests; always null in production.
  final String? initialLocation;

  @override
  State<PlatformApp> createState() => _PlatformAppState();
}

class _PlatformAppState extends State<PlatformApp> {
  late final AccountBloc _accountBloc;
  late final GoRouter _router;
  late final SignatureFilePicker _signatureFilePicker;
  late final QualityPhotoPicker _qualityPhotoPicker;
  late final ThemeModeCubit _themeModeCubit;
  late final LocaleCubit _localeCubit;

  /// Re-titles the tab when the language changes (see [_applyDocumentTitle]).
  late final StreamSubscription<Locale> _localeSubscription;
  late final DocumentChrome _documentChrome;

  // Built once, not per rebuild: a mode change rebuilds `MaterialApp.router`,
  // and rebuilding two `ThemeData`s each time would be work for no change.
  late final ThemeData _lightTheme;
  late final ThemeData _darkTheme;

  @override
  void initState() {
    super.initState();
    // Built exactly once: building either in build() would recreate the
    // router on every rebuild and destroy navigation history.
    _signatureFilePicker = widget.signatureFilePicker ?? createSignatureFilePicker();
    _qualityPhotoPicker = widget.qualityPhotoPicker ?? createQualityPhotoPicker();
    _accountBloc = AccountBloc(authGateway: widget.authGateway, peopleApi: widget.peopleApi);
    _themeModeCubit = ThemeModeCubit();
    // Which language the Platform speaks (issue t_c68dfd6e). Restored from
    // `shared_preferences` asynchronously, so the first frame is the shipped
    // default and a stored choice lands a frame or two later — never a blank
    // app waiting on a disk read.
    _localeCubit = LocaleCubit();
    _lightTheme = buildAppTheme();
    _darkTheme = buildAppTheme(Brightness.dark);
    _router = buildRouter(accountBloc: _accountBloc, initialLocation: widget.initialLocation);
    _documentChrome = widget.documentChrome ?? createDocumentChrome();
    // **The tab's title is the router's, not a Screen's** (issue #399). The
    // delegate notifies on every configuration change — a push, a pop, a
    // `go`, a redirect the Account Bloc's own state caused — so one listener
    // covers every way an address can change, including the dialog addresses
    // ADR-0021 gives their own page. Written once here for the address the app
    // opened on, so a reload of `/work-orders/42` is titled before anything
    // else touches it.
    _router.routerDelegate.addListener(_applyDocumentTitle);
    // Choosing a language re-titles the tab too: the address did not change, so
    // the router's own listener would never fire.
    _localeSubscription = _localeCubit.stream.listen((_) => _applyDocumentTitle());
    _applyDocumentTitle();
  }

  /// The address on top of the stack, as the title table names it (see
  /// [documentTitle] in `router.dart`), in the language the Platform is
  /// speaking.
  ///
  /// The catalogue is taken from the locale cubit rather than from a
  /// `BuildContext`: the `MaterialApp` that *has* one is built by this widget,
  /// below it, so there is no ancestor `Localizations` to ask here — and the
  /// tab is written from this State, not from a Screen.
  void _applyDocumentTitle() => _documentChrome.setTitle(
        documentTitle(
          _router.routerDelegate.currentConfiguration.fullPath,
          l10n: lookupAppLocalizations(_localeCubit.state),
        ),
      );

  @override
  void dispose() {
    _localeSubscription.cancel();
    _router.routerDelegate.removeListener(_applyDocumentTitle);
    _router.dispose();
    _accountBloc.close();
    _themeModeCubit.close();
    _localeCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthGateway>.value(value: widget.authGateway),
        // Provided so a Module's own Bloc can be built at its route, with the
        // same faked wire a widget test already substitutes here.
        RepositoryProvider<PeopleApi>.value(value: widget.peopleApi),
        RepositoryProvider<MaintenanceApi>.value(value: widget.maintenanceApi),
        RepositoryProvider<ActionsApi>.value(value: widget.actionsApi),
        RepositoryProvider<QualityApi>.value(value: widget.qualityApi),
        RepositoryProvider<SafetyApi>.value(value: widget.safetyApi),
        RepositoryProvider<ProductionApi>.value(value: widget.productionApi),
        RepositoryProvider<KpiApi>.value(value: widget.kpiApi),
        RepositoryProvider<FloorDeviceGateway>.value(value: widget.floorDeviceGateway),
        RepositoryProvider<SignatureFilePicker>.value(value: _signatureFilePicker),
        RepositoryProvider<QualityPhotoPicker>.value(value: _qualityPhotoPicker),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AccountBloc>.value(value: _accountBloc),
          // Which palette the Platform wears (issue #366, ADR-0056). Provided
          // above `MaterialApp` because the mode is what `MaterialApp` is
          // built from, and the Shell's account menu reads it.
          BlocProvider<ThemeModeCubit>.value(value: _themeModeCubit),
          // Which language the Platform speaks (issue t_c68dfd6e). Provided
          // above `MaterialApp` for the same reason, and read by the Settings
          // Screen's own control — the only control that writes it.
          BlocProvider<LocaleCubit>.value(value: _localeCubit),
        ],
        // Two settings decide what `MaterialApp` is built from, so two
        // builders: the language outermost (a language change re-reads every
        // catalogue) and the palette inside it. Both rebuild only the app
        // widget; `_router` is a field, so navigation history survives either.
        child: BlocBuilder<LocaleCubit, Locale>(
          builder: (context, locale) => BlocBuilder<ThemeModeCubit, ThemeMode>(
            builder: (context, themeMode) => MaterialApp.router(
              // The name the platform switcher shows, and what the document says
              // for the instant before the router titles the address — the same
              // word `index.html` and `manifest.json` carry. Every address's own
              // title is written through `DocumentChrome` (see
              // `_applyDocumentTitle`); issue #399.
              title: l10n.shellBrand,
              debugShowCheckedModeBanner: false,
              theme: _lightTheme,
              darkTheme: _darkTheme,
              themeMode: themeMode,
              // The language the Platform speaks (issue t_c68dfd6e). Always one
              // of `supportedLocales`, so a catalogue is always found: the
              // shipped default is English, exactly the words this client
              // carried before it could speak twice.
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              // A field, so the rebuild a mode change causes keeps navigation
              // history.
              routerConfig: _router,
              builder: (context, child) {
                final account = context.watch<AccountBloc>().state;
                // This overlay — not a `/loading` or `/error` route — is why the
                // redirect table returns null (no redirect) for both of these
                // states: the caller's real URL stays intact underneath while
                // this renders on top, and no protected route ever gets built
                // while the state is unresolved.
                return _PaletteThemeColor(
                  chrome: _documentChrome,
                  child: switch (account) {
                    AccountResolving() =>
                      const Scaffold(body: Center(child: CircularProgressIndicator())),
                    AccountUnavailable(message: final message) =>
                      SessionErrorScreen(message: message),
                    _ => child ?? const SizedBox.shrink(),
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Tells the browser which palette is on screen (issue #399), so an installed
/// instance's own chrome — its address bar, a mobile browser's toolbar tint —
/// is the colour of the page rather than a colour fixed at build time.
///
/// **Read off `Theme.of(context).brightness`, not off the palette extension's
/// own `canvas`.** `MaterialApp` animates between the two themes, and
/// `AppPalette.lerp` interpolates every field, so the extension's canvas during
/// a switch is a colour neither palette names. Brightness picks one of the two
/// palettes, so the document is written once per switch rather than once per
/// frame of it — and the colour is always a token from `theme.dart`.
///
/// **Every way the palette can change arrives here**: the tray toggle, the
/// account menu, a stored choice landing on a later frame, and the browser's
/// own `prefers-color-scheme` while the mode is `system` — all of them rebuild
/// the theme below `MaterialApp`, which is exactly what this widget watches.
class _PaletteThemeColor extends StatefulWidget {
  const _PaletteThemeColor({required this.chrome, required this.child});

  final DocumentChrome chrome;
  final Widget child;

  @override
  State<_PaletteThemeColor> createState() => _PaletteThemeColorState();
}

class _PaletteThemeColorState extends State<_PaletteThemeColor> {
  /// The colour last handed to the document, so a rebuild that changed nothing
  /// about the palette does not write the same attribute again.
  Color? _applied;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final palette =
        Theme.of(context).brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
    if (palette.canvas == _applied) return;
    _applied = palette.canvas;
    widget.chrome.setThemeColor(palette.canvas);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
