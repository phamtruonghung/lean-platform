/*
 * Removes the boot surface as soon as the engine has painted.
 *
 * This ran as an inline <script> in index.html until the edge started sending a
 * Content-Security-Policy (frontend/nginx.conf). `script-src 'self'` blocks
 * inline script, and adding 'unsafe-inline' to keep this one function would
 * give up the directive that matters most here — the session token is kept in a
 * script-readable store (lib/platform/local_auth_gateway.dart), so injected
 * script is exactly what the policy is for. A file served from this origin is
 * allowed by 'self', costs one revalidated request and no behaviour change.
 *
 * index.html loads it synchronously, before flutter_bootstrap.js, so the
 * listener is registered before the engine can dispatch `flutter-first-frame`;
 * test/web_assets_test.dart asserts that ordering.
 */
(function () {
  var splash = document.getElementById('boot-splash');
  if (!splash) return;
  window.addEventListener('flutter-first-frame', function () {
    if (splash.parentNode) splash.parentNode.removeChild(splash);
  }, { once: true });
}());
