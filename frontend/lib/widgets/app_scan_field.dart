/// `AppScanField`: the code-entry `TextField` a shop-floor scanner fills.
///
/// A DataMatrix/QR/barcode reader is, to a browser, a keyboard: it types the
/// code it read in a burst no person can type and finishes with `Enter`. So the
/// Platform does not need a camera, a plugin or a permission prompt to accept a
/// scan — it needs its code fields to be reachable without a tap and to treat
/// that closing `Enter` as "this code is committed", whatever the reader's
/// symbology was. This widget is that field, and it is the one the Platform's
/// code fields are built from, so the behaviour is identical in every dialog
/// rather than re-invented per Screen.
///
/// **Why a `Focus` wrapper and not `TextField.onSubmitted`.** Measured in the
/// pinned image (the same measurement `widgets/app_form_submit.dart` records):
/// a hardware `Enter` key event does not reach `TextField.onSubmitted`, so a
/// scanner's terminating `Enter` would be dropped and a scan would silently
/// become typed text. A `Focus.onKeyEvent` ancestor does see it. This widget
/// therefore installs one — `canRequestFocus: false`, so it adds no Tab stop and
/// no focus ring of its own — and handles `Enter`/`numpadEnter` itself, exactly
/// as `AppFormSubmit` handles the same key for a form's primary action. Both
/// paths are kept: the soft keyboard's own done action still arrives at
/// `onSubmitted` and commits by that route, so a phone and a reader do the same
/// thing.
///
/// **Two things "committed" does.** [AppScanField.normalize] is applied to what
/// the reader typed — its terminator is a control character (`CR`, `LF`, or
/// GS1's group separator `0x1D`), some readers prefix a BOM or a zero-width
/// character, and a code is never meant to carry any of them — and the cleaned
/// code is written back into the controller, so what a person sees (and what the
/// form posts) is the code itself. Then [onScanned] is called with it. The
/// callback cannot tell a scan from a typed code, and does not try: a code typed
/// by hand and finished with `Enter` is committed the same way, which is what a
/// person standing at the machine with a broken reader needs.
///
/// **The caller's `Key` lands on the `TextField`.** This widget is a
/// `StatelessWidget` with a private field-key parameter and a factory
/// constructor that takes `key` and hands it to the field it builds. That is
/// deliberate: every existing test finds a code field by the key its dialog
/// declares (`AssetFormDialog.codeKey`, and `tester.widget<TextField>(…)` over
/// it), and a wrapper holding that key would either break those finders or make
/// one key match two widgets. The key is the field's, so the key stays on the
/// field.
///
/// **`advanceFocusOnScan`** exists for the badge-then-PIN shape the floor's own
/// prompts have (`FloorTechnicianDialog`, `FloorTrainingDialog`): scanning an
/// Employee number should leave the pointer nowhere near the badge field, and
/// `FocusScope.nextFocus()` moves to the PIN in traversal order — the same order
/// `Tab` uses, so no second notion of "the next field" is introduced.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_camera_scan.dart';

class AppScanField extends StatelessWidget {
  const AppScanField._({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.helperText,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onScanned,
    this.advanceFocusOnScan = false,
  });

  /// Builds the field. [key] is the `TextField`'s own key — see this class's
  /// doc comment for why it is not the widget's.
  factory AppScanField({
    Key? key,
    required TextEditingController controller,
    required String label,
    String? helperText,
    bool enabled = true,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onScanned,
    bool advanceFocusOnScan = false,
  }) {
    return AppScanField._(
      fieldKey: key,
      controller: controller,
      label: label,
      helperText: helperText,
      enabled: enabled,
      autofocus: autofocus,
      onChanged: onChanged,
      onScanned: onScanned,
      advanceFocusOnScan: advanceFocusOnScan,
    );
  }

  /// The `Key` the `TextField` carries.
  final Key? fieldKey;

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final bool enabled;

  /// Whether this field takes focus as the dialog opens — what makes a scan
  /// land without the reader first tapping into the field. Set on the first
  /// field of a dialog, never on all of them: two focused fields is no focus.
  final bool autofocus;

  final ValueChanged<String>? onChanged;

  /// Called with the cleaned code when the field's value is committed — by the
  /// reader's closing `Enter`, or by a soft keyboard's done action, or by a
  /// person pressing `Enter` after typing. Never called for an empty field.
  final ValueChanged<String>? onScanned;

  final bool advanceFocusOnScan;

  /// What a reader adds around a code, removed before the code is used.
  ///
  /// Every rune below `0x20` and `0x7F` is a control character — a reader's
  /// terminator (`CR` `LF`), GS1's field separator (`0x1D`) and the rest are
  /// never part of a code. `U+FEFF` (a byte-order mark some readers prefix) and
  /// the zero-width characters `U+200B`–`U+200D`/`U+2060` are invisible and
  /// would otherwise travel into the form and the database. Leading and
  /// trailing whitespace goes too (`String.trim`, which is Unicode
  /// White_Space plus `U+FEFF`), because a reader configured to append a space
  /// is a configuration, not a code. Interior characters are left exactly as
  /// read: a code is the plant's, and `A 12` is not this widget's to rewrite.
  static String normalize(String raw) {
    final kept = StringBuffer();
    for (final rune in raw.runes) {
      if (rune < 0x20 || rune == 0x7F) continue;
      if (rune == 0xFEFF || rune == 0x200B || rune == 0x200C || rune == 0x200D || rune == 0x2060) {
        continue;
      }
      kept.writeCharCode(rune);
    }
    return kept.toString().trim();
  }

  void _commit(BuildContext context) {
    final code = AppScanField.normalize(controller.text);
    if (code.isEmpty) return;
    if (code != controller.text) {
      controller.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
      // The controller write above is not an edit, so `TextField.onChanged`
      // never sees it. A caller whose submit gate watches the text
      // (`onChanged: (_) => setState(() {})`) has to be told, or it would keep
      // a stale gate shut over a value the form would now post.
      onChanged?.call(code);
    }
    onScanned?.call(code);
    if (advanceFocusOnScan) _advanceToNextTextField(context);
  }

  /// Moves focus to the next control that takes text — the badge-then-PIN shape
  /// this is for ends on a field, not on the camera button this field now
  /// carries in its own decoration. A plain `nextFocus` would land on that
  /// button, which would leave the PIN untyped and the reader's next burst
  /// nowhere.
  void _advanceToNextTextField(BuildContext context) {
    final scope = FocusScope.of(context);
    final nodes = scope.traversalDescendants.where((node) => node.canRequestFocus).toList(growable: false);
    final current = FocusManager.instance.primaryFocus;
    final from = current == null ? -1 : nodes.indexOf(current);
    for (final node in nodes.skip(from < 0 ? 0 : from + 1)) {
      if (_holdsTextField(node)) {
        node.requestFocus();
        return;
      }
    }
    scope.nextFocus();
  }

  /// Whether [node] is the focus of a text field rather than of a button: the
  /// field's node sits under an `EditableText`, a button's does not.
  static bool _holdsTextField(FocusNode node) {
    final context = node.context;
    if (context is! Element) return false;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// A code a phone's camera read (see `app_camera_scan.dart`), written into the
  /// field and committed exactly as a reader's burst is: same cleaning already
  /// applied by the button, same [onChanged] so a caller's submit gate sees it,
  /// same [onScanned].
  void _takeScanned(String code) {
    if (!enabled || code.isEmpty) return;
    controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    onChanged?.call(code);
    onScanned?.call(code);
  }

  /// Names the camera button in this field's own `Key` when it carries one, so
  /// two code fields in one dialog do not share a key.
  String get _scanName {
    final key = fieldKey;
    return key is ValueKey<String> ? key.value : 'code';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.enter && key != LogicalKeyboardKey.numpadEnter) {
          return KeyEventResult.ignored;
        }
        if (!enabled) return KeyEventResult.ignored;
        _commit(context);
        // Handled so the reader's `Enter` stops here: it is the field's
        // terminator, not an activation of whatever control comes next.
        return KeyEventResult.handled;
      },
      child: TextField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: enabled ? (_) => _commit(context) : null,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: const OutlineInputBorder(),
          // The second reader, beside the first: a phone's camera. A field that
          // is not taking input has no business offering one.
          suffixIcon: enabled ? AppCameraScanButton(name: _scanName, onScanned: _takeScanned) : null,
        ),
      ),
    );
  }
}
