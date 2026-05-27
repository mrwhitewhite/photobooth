import 'dart:typed_data';
import '../models/photo_models.dart';

/// Minimal mobile stub of ImageProcessor used to allow Android/iOS builds.
///
/// This provides a lightweight implementation that returns the first
/// provided photo as the composite. It intentionally avoids heavy
/// platform-specific image processing to keep the build simple; replace
/// with a full native implementation if required.
class ImageProcessor {
  static Future<Uint8List> composite({
    required List<Uint8List> photos,
    required PhotoLayout layout,
  }) async {
    if (photos.isNotEmpty) return photos.first;
    throw Exception('No photos provided');
  }

  static Future<void> saveToGallery(Uint8List bytes, String filename) async {
    // No-op stub for mobile builds. Implement with a plugin if needed.
    return;
  }

  static void downloadFile(Uint8List bytes, String filename) {
    // No-op for mobile.
  }
}
