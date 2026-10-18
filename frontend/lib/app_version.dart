/// The identity of the build being served, baked in at build time.
///
/// Read via `--dart-define` for the same reason `supabase_config.dart` is: a
/// Flutter web bundle resolves nothing at runtime. The release workflow passes
/// the image tag (`sha-<short sha>`) as the `APP_VERSION` build arg, the
/// Dockerfile forwards it here and also writes it to `/version.txt`.
///
/// The default is `dev`, never a version number — a hardcoded fallback goes
/// stale and then lies. The `== ''` check is not redundant: the Dockerfile
/// always passes `--dart-define=APP_VERSION=...`, empty when no build arg is
/// given, and a define that is present but empty makes `String.fromEnvironment`
/// return `''` — its `defaultValue` applies only when the define is absent.
///
///     flutter run --dart-define=APP_VERSION=sha-abc1234
library;

const _appVersionDefine = String.fromEnvironment('APP_VERSION');

/// The build's version, or `dev` for a local run and for tests.
const appVersion = _appVersionDefine == '' ? 'dev' : _appVersionDefine;
