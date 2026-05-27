import 'dart:typed_data';

class ImageRasterizer {
  static Future<Uint8List> processAndBuildRaster(
    Uint8List pngBytes, {
    required int paperWidthPx,
  }) async {
    // Mobile stub: return minimal printer commands (init + feed+cut)
    return Uint8List.fromList([
      0x1B, 0x40, // init
      0x1B, 0x32, // line feed
      0x1B, 0x64, 0x05, // feed 5
      0x1D, 0x56, 0x42, 0x00, // cut
    ]);
  }

  static Uint8List buildInitCommand() => Uint8List.fromList([0x1B, 0x40]);

  static Uint8List buildFeedCutCommand() =>
      Uint8List.fromList([0x1B, 0x32, 0x1B, 0x64, 0x05, 0x1D, 0x56, 0x42, 0x00]);
}

class ImageRasterizerException implements Exception {
  final String message;
  const ImageRasterizerException(this.message);
  @override
  String toString() => 'ImageRasterizerException: $message';
}
