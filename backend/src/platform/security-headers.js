/*
 * Security headers on every API response.
 *
 * The Flutter app is served by the frontend container, whose nginx.conf sets
 * these same headers on every response — but `/api/...` never passes through
 * that container. The edge (deploy/Caddyfile, and dev/edge.nginx.conf for local
 * compose) sends it straight to this process, so without something here an API
 * response carries none of them: no HSTS, no nosniff, nothing that says what a
 * browser may do with a body it just received. That is the half of the story
 * `frontend/nginx.conf` cannot tell.
 *
 * This is a middleware rather than a dependency, deliberately: the backend
 * carries no runtime dependency beyond pg/express/dotenv, and four setHeader
 * calls do not justify adding one. It sits in src/platform because it is
 * infrastructure every Module's responses go through, not a Module's own
 * concern (ADR-0006).
 *
 * The policy for a JSON API is not the app's policy. There is no script, no
 * style, no image and no frame to allow: `default-src 'none'` says so, and
 * `frame-ancestors 'none'` / `X-Frame-Options: DENY` refuse to be framed at
 * all. `nosniff` is the one that earns its keep on a JSON endpoint: it is what
 * stops a browser from being talked into executing a response that was meant to
 * be data.
 */

// 180 days, matching frontend/nginx.conf. `includeSubDomains` is safe there for
// the same reason it is safe here: the deployment serves one hostname. It is
// not `preload` — that is a submission to a vendor's list, a deploy decision
// rather than something a process can assert about itself.
const STRICT_TRANSPORT_SECURITY = 'max-age=15552000; includeSubDomains';

// Named directives rather than a bag of defaults, because each one is an answer
// to "what could a browser be told to do with this response": nothing
// (`default-src 'none'`), nothing embedded (`frame-ancestors 'none'`), no
// <base> to rewrite (`base-uri 'none'`), no form to submit anywhere
// (`form-action 'none'`).
const CONTENT_SECURITY_POLICY =
  "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";

function securityHeaders(_req, res, next) {
  // Set on the response object before the route runs, so they are present on
  // every outcome — a 200, a 401 from a route's own error mapping, this file's
  // own 500 handler, and Express's 404 for a path no Module claimed. `always`
  // in nginx exists for the same reason; here it is simply "set before
  // anything can end the response".
  res.setHeader('Strict-Transport-Security', STRICT_TRANSPORT_SECURITY);
  res.setHeader('Content-Security-Policy', CONTENT_SECURITY_POLICY);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  next();
}

module.exports = { securityHeaders, STRICT_TRANSPORT_SECURITY, CONTENT_SECURITY_POLICY };
