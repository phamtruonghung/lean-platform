# Bundled fonts

Roboto, copyright the Roboto Project Authors, licensed under the
Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0).

## Why these are committed

Flutter Web's CanvasKit renderer has no system fonts to fall back on, so it
downloads its default font — Roboto — from `fonts.gstatic.com` at runtime. If
that request does not succeed, the app still lays out and paints, but every
glyph is dropped: the page renders as a set of empty boxes with no labels, no
title and no button text.

That makes a third-party CDN a hard dependency for the app being usable at all,
which is not a reasonable thing for a service running on a private cluster. It
breaks if egress is ever restricted by a NetworkPolicy, if the cluster is
offline, or if a user's own network blocks Google.

Shipping the font inside the image removes the dependency: everything the app
needs is served from its own origin.
