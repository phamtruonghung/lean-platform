/// `AppCameraScan`: a phone's own camera as one of the Platform's readers.
///
/// A dedicated shop-floor reader is a keyboard — it needs no library, only a
/// field willing to take a burst and its closing `Enter` (`AppScanField`). A
/// phone is a camera, and a camera needs a decoder. This file is that decoder's
/// one door: a button a code field or a picker carries, a dialog that shows the
/// camera, and the first code the camera recognises handed back as text.
///
/// **Why a package rather than the browser's own `BarcodeDetector`.** The
/// Platform ships as a web bundle, so a browser API would be the cheapest
/// decoder — but `BarcodeDetector` is the engine's, not the Platform's: it is
/// absent wherever the browser does not implement it, which is a failure a
/// person discovers only after opening the dialog. `mobile_scanner` puts one
/// widget over three decoders (ML Kit and Apple Vision on the native builds,
/// the browser's own API on web) and lets a caller pick which one, so the same
/// button can serve a phone, a tablet and a desk camera without the app knowing
/// which it is on.
///
/// **The web decoder is forced to the browser's own, and that is deliberate.**
/// Left to itself the package falls back to a decoder script it fetches from
/// jsDelivr, and its other web reader fetches from unpkg. This Platform is
/// deployed on the plant's own network (`frontend/Dockerfile` already bundles
/// CanvasKit and Roboto rather than reach a CDN), so a reader that needs the
/// public internet is a reader that works in the office and not on the floor.
/// `MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.
/// barcodeDetector)` therefore pins the browser's own decoder: on any browser
/// that has it the camera works with no network fetch at all, and on one that
/// does not the dialog says so in words instead of quietly trying the internet.
/// The cost is honest and named: Firefox has no `BarcodeDetector`, so a code is
/// typed or read there, as it was before this file existed.
///
/// **What is scanned is a code, not an intent.** A QR code can carry a URL, a
/// contact card or a Wi-Fi credential — `mobile_scanner` decodes all of them —
/// but the Platform's fields take codes, so this widget reads `rawValue` only
/// and never follows, dials or joins anything it finds inside one. It is the
/// same value the reader's keyboard path produces, cleaned by the same
/// `AppScanField.normalize`, so a scanned code and a typed one are
/// indistinguishable to every caller downstream.
///
/// **`AppCameraScan.reader` is the seam a test replaces.** A widget test has no
/// camera: it substitutes a function returning a code, and asserts what the
/// field did with it. Nothing outside a test ever assigns to it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'app_dialog.dart';
import 'app_scan_field.dart';

/// Reads a code off a camera, or returns `null` when the person closed the
/// dialog without one.
typedef CameraScanReader = Future<String?> Function(BuildContext context);

/// The camera reader, behind a seam a test can replace (see this library's doc
/// comment).
class AppCameraScan {
  const AppCameraScan._();

  /// How a code is read. A test assigns a function that returns a fixed code;
  /// nothing in the app assigns to it.
  static CameraScanReader reader = readWithCamera;

  /// Opens the camera and returns the first code it reads, or `null`.
  static Future<String?> read(BuildContext context) => reader(context);

  /// The real reader: the camera dialog below.
  static Future<String?> readWithCamera(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const CameraScanDialog(),
    );
  }
}

/// The catalogue when the tree provides one — every Screen's `MaterialApp` does
/// — and `null` when it does not, which is the case for the bare `MaterialApp`s
/// the widget tests in this suite build. Those tests are about what a control
/// does, not what it says; the English words below are the fallback for them,
/// and the trait they share with `AppSearchField`'s own strings.
AppLocalizations? _catalogue(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations);

/// The icon control a code field or a picker carries: opens the camera and
/// reports the code it read.
class AppCameraScanButton extends StatelessWidget {
  const AppCameraScanButton({
    super.key,
    required this.name,
    required this.onScanned,
  });

  /// Identifies this button among any others in the same dialog, the same way
  /// `AppSearchField`'s own `name` does — a picker over Assets and a picker over
  /// Parts can sit in one form.
  final String name;

  /// Called with the code the camera read, already cleaned. Never called with
  /// an empty string, and never when the person simply closed the dialog.
  final ValueChanged<String> onScanned;

  /// The button's own `Key` (AGENTS.md §7).
  static ValueKey<String> keyOf(String name) => ValueKey<String>('app-camera-scan-$name');

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: keyOf(name),
      icon: const Icon(Icons.qr_code_scanner),
      tooltip: _catalogue(context)?.cameraScanButton ?? 'Scan with the camera',
      onPressed: () async {
        final raw = await AppCameraScan.read(context);
        if (raw == null) return;
        final code = AppScanField.normalize(raw);
        if (code.isEmpty) return;
        onScanned(code);
      },
    );
  }
}

/// The camera, filling a dialog until it reads something.
class CameraScanDialog extends StatefulWidget {
  const CameraScanDialog({super.key});

  static const ValueKey<String> previewKey = ValueKey<String>('camera-scan-preview');
  static const ValueKey<String> failureKey = ValueKey<String>('camera-scan-failure');

  /// The one way out that changes nothing.
  static const String closeId = 'camera-scan-close';

  @override
  State<CameraScanDialog> createState() => _CameraScanDialogState();
}

class _CameraScanDialogState extends State<CameraScanDialog> {
  late final MobileScannerController _controller;

  /// Set once a code has been handed back, so the second frame of the same code
  /// (a QR code is read many times a second) cannot pop a second dialog.
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      // One code is all this dialog is for: hold each new value rather than
      // report the same one every frame.
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      autoTorch: false,
    );
    if (kIsWeb) {
      // See this library's doc comment: the browser's own decoder or nothing,
      // never a script fetched from a CDN.
      MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.barcodeDetector);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handOver(BarcodeCapture capture) {
    if (_returned) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = AppScanField.normalize(raw);
      if (code.isEmpty) continue;
      _returned = true;
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _catalogue(context);
    return AppDialog(
      title: l10n?.cameraScanTitle ?? 'Scan a code',
      description: l10n?.cameraScanPointAtCode ??
          'Point the camera at the code — it is read as soon as it is recognised.',
      size: AppDialogSize.picker,
      actions: [
        AppDialogAction(
          id: CameraScanDialog.closeId,
          label: l10n?.cameraScanClose ?? 'Close',
          kind: AppDialogActionKind.dismiss,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: SizedBox(
        height: 280,
        child: Semantics(
          label: l10n?.cameraScanTitle ?? 'Scan a code',
          child: MobileScanner(
            key: CameraScanDialog.previewKey,
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _handOver,
            errorBuilder: (context, error) => _refused(l10n, error),
          ),
        ),
      ),
    );
  }

  /// What a person sees instead of a preview when the camera cannot be used —
  /// and why, in the words for the case that actually happened.
  ///
  /// No retry button: a browser without a decoder has none to offer, a refused
  /// permission is granted in the browser's own chrome rather than here, and the
  /// one thing this dialog can do about either is get out of the way. `Close` is
  /// that way out, and it is always on screen.
  Widget _refused(AppLocalizations? l10n, MobileScannerException error) {
    final (title, message) = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => (
          l10n?.cameraScanRefusedTitle ?? 'The camera could not be opened',
          l10n?.cameraScanRefusedBody ??
              'Allow this site to use the camera in the browser, then try again.',
        ),
      MobileScannerErrorCode.unsupported => (
          l10n?.cameraScanUnsupportedTitle ??
              'This browser cannot read a code with the camera',
          l10n?.cameraScanUnsupportedBody ??
              'Type the code instead, or use the shop-floor reader.',
        ),
      _ => (
          l10n?.cameraScanRefusedTitle ?? 'The camera could not be opened',
          l10n?.cameraScanRefusedBody ??
              'Allow this site to use the camera in the browser, then try again.',
        ),
    };
    final theme = Theme.of(context);
    return Semantics(
      key: CameraScanDialog.failureKey,
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.sm),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
