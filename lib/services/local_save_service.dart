import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class LocalSaveService {
  /// Saves [imageBytes] as a JPEG in a "PhotoBooth" folder inside the public
  /// Downloads directory on Android (or documents directory on iOS).
  static Future<String> saveComposite(Uint8List imageBytes) async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      // Hardcode the public Downloads directory for Android
      baseDir = Directory('/storage/emulated/0/Download');
    } else {
      // iOS sandboxing prevents direct access to a public Downloads folder.
      // Fallback to Documents directory.
      baseDir = await getApplicationDocumentsDirectory();
    }

    // Create a dedicated "PhotoBooth" subfolder.
    final saveDir = Directory('${baseDir.path}/PhotoBooth');

    // If this throws a "Permission Denied" error, check your AndroidManifest!
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
