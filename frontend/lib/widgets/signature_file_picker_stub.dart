/// The picker everywhere `package:web` is unavailable (the Dart VM a widget
/// test runs on): it never chooses a file. See `signature_file_picker.dart`.
library;

import 'dart:typed_data';

import 'signature_file_picker.dart';

class _NoFilePicker implements SignatureFilePicker {
  const _NoFilePicker();

  @override
  Future<Uint8List?> pickSignatureImage() async => null;
}

SignatureFilePicker createSignatureFilePicker() => const _NoFilePicker();
