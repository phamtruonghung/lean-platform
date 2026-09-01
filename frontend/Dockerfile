# syntax=docker/dockerfile:1

# ------------------------------------------------------------------------------
# Build the Flutter web bundle.
# ------------------------------------------------------------------------------
# Pinned to a specific Flutter release rather than `stable`. A floating tag means
# the same commit can produce different output on different days, which makes a
# failed build impossible to reproduce and a rollback unreliable.
#
# This version must satisfy the Dart constraint in pubspec.yaml and must match
# the version CI builds with, or the image is built from a different toolchain
# than the one the tests ran against.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app

# Resolve dependencies first so this layer is reused until the manifests change.
# pubspec.lock is optional on the first build only: once it exists it is
# committed, and every build after that resolves to exactly what it pins.
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .

# Supabase project config (ADR-0002), baked into the bundle at build time —
# see lib/supabase_config.dart for why this is --dart-define rather than a
# file read at runtime. Both default to empty, matching
# String.fromEnvironment's own default when a define is omitted, so a build
# with neither ARG supplied still succeeds — that is what lets CI keep
# building this image on every push without needing the real project's
# secrets (see the frontend CI job). Deploying against a real Supabase
# project means passing both as --build-arg.
ARG SUPABASE_URL=""
ARG SUPABASE_ANON_KEY=""

# --no-web-resources-cdn makes the app load CanvasKit from its own origin
# instead of www.gstatic.com. The engine bundles CanvasKit into the build either
# way; without this flag the copy in the image is never used, and the app cannot
# start without reaching a public CDN.
RUN flutter build web --release --no-web-resources-cdn \
      --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
      --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

# ------------------------------------------------------------------------------
# Serve the built files.
# ------------------------------------------------------------------------------
# The unprivileged variant runs as a non-root user out of the box and listens on
# 8080, which is what lets the container run without root.
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

USER 10001

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
