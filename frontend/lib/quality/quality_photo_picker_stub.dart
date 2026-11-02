/// The picker everywhere `package:web` is unavailable (the Dart VM a widget
/// test runs on): it never chooses a file. See `quality_photo_picker.dart`.
library;

import 'quality_photo.dart';
import 'quality_photo_picker.dart';

class _NoPhotoPicker implements QualityPhotoPicker {
  const _NoPhotoPicker();

  @override
  Future<PickedPhoto?> pickPhoto() async => null;
}

QualityPhotoPicker createQualityPhotoPicker() => const _NoPhotoPicker();
