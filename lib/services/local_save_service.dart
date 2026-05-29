import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class LocalSaveService {
  /// Saves [imageBytes] as a JPEG in a "PhotoBooth" folder inside the device's
  /// external storage (or documents directory as fallback).
  ///
  /// Returns the absolute path where the file was saved, or throws on error.
  static Future<String> saveComposite(Uint8List imageBytes) async {
    // Prefer external storage so the file is easy to find on Android.
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      // Fall back to app documents directory on platforms that don't have
      // external storage (e.g. Windows desktop during development).
      base = await getApplicationDocumentsDirectory();
    }

    // Create a dedicated "PhotoBooth" subfolder.
    final saveDir = Directory('${base!.path}/PhotoBooth');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    // Filename: photobooth_<yyyyMMdd_HHmmss_mmm>.jpg
    final now = DateTime.now();
    final stamp =
        '${now.year}${_p(now.month)}${_p(now.day)}_${_p(now.hour)}${_p(now.minute)}${_p(now.second)}_${now.millisecond.toString().padLeft(3, '0')}';
    final filePath = '${saveDir.path}/photobooth_$stamp.jpg';

    final file = File(filePath);
    await file.writeAsBytes(imageBytes, flush: true);

    return filePath;
  }

  static String _p(int v) => v.toString().padLeft(2, '0');
}
