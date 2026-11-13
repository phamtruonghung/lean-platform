# Vendor: @zxing/library 0.23.0 (UMD build)

`zxing-library-0.23.0.js` is the unmodified UMD bundle unpkg serves for
`@zxing/library@0.23.0` — the exact version `mobile_scanner` pins
(`lib/src/web/web_library_versions.dart`). `LICENSE` is that package's own
Apache-2.0 licence, unmodified.

## Why a copy lives in the repository

`mobile_scanner`'s web implementation loads its decoder with a `<script src>`:
`https://unpkg.com/@zxing/library@0.23.0` for its JS reader, and
`https://cdn.jsdelivr.net/npm/zxing-wasm@…` for its WebAssembly one. The Platform
is served from the plant's own network and already bundles CanvasKit and Roboto
rather than reach a public CDN (`frontend/Dockerfile`, `assets/fonts/README.md`),
so a decoder fetched from the internet is a decoder that works in the office and
not on the floor. Vendoring the file and pointing the package at it
(`MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl`, in
`lib/widgets/app_camera_scan.dart`) keeps every byte the app needs on our own
origin.

The browser's own `BarcodeDetector` was the first choice — no download at all —
but it is absent exactly where a phone matters: Safari on iPhone has it behind an
off-by-default flag, and Firefox and Chrome on Windows/Linux do not implement it.
A scanner that works on one Android phone and refuses on an iPhone is not a
reader the plant can standardise on.

## Updating

Take the new version's UMD build and licence from unpkg, put them here under the
new version's name, change the path in `lib/widgets/app_camera_scan.dart`, and
keep `mobile_scanner`'s own `zxingJsVersion` in step — a mismatch between the
package's expectations and this file's API is the one way this copy can break.
