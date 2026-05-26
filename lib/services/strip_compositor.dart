import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class StripCompositor {
  static const double _stripW = 600.0;
  static const double _stripH = 1800.0;
  static const double _padding = 20.0;
  static const double _borderRadius = 8.0;

  static Future<Uint8List> generateStrip(List<Uint8List> photos) async {
    final canvas = img.Image(
      width: _stripW.toInt(),
      height: _stripH.toInt(),
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorUint8.rgba(0x1A, 0x12, 0x08, 0xFF));

    final int count = photos.length;
    final double slotH = (_stripH - _padding * (count + 1)) / count;
    const double slotW = _stripW - _padding * 2;

    for (int i = 0; i < count; i++) {
      final double y = _padding + i * (slotH + _padding);
      const double x = _padding;

      final decoded = img.decodeImage(photos[i]);
      if (decoded == null) {
        throw const StripCompositorException('Failed to decode strip photo.');
      }

      final double srcAspect = decoded.width / decoded.height;
      final double dstAspect = slotW / slotH;
      int cropX = 0, cropY = 0, cropW = decoded.width, cropH = decoded.height;

      if (srcAspect > dstAspect) {
        cropH = decoded.height;
        cropW = (cropH * dstAspect).round();
        cropX = ((decoded.width - cropW) / 2).round();
      } else {
        cropW = decoded.width;
        cropH = (cropW / dstAspect).round();
        cropY = ((decoded.height - cropH) / 2).round();
      }

      final cropped = img.copyCrop(
        decoded,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      final resized = img.copyResize(
        cropped,
        width: slotW.round(),
        height: slotH.round(),
        interpolation: img.Interpolation.cubic,
      );

      final slotImage = img.Image.from(resized, numChannels: 4);
      _applyRoundedCorners(slotImage, _borderRadius.round());

      img.compositeImage(
        canvas,
        slotImage,
        dstX: x.round(),
        dstY: y.round(),
        blend: img.BlendMode.alpha,
      );
    }

    img.drawString(
      canvas,
      img.arial_24,
      (canvas.width / 2 - 90).round(),
      canvas.height - 50,
      '✦ SnapBooth ✦',
      color: img.ColorUint8.rgba(232, 196, 160, 180),
    );

    return Uint8List.fromList(img.encodePng(canvas));
  }

  static void _applyRoundedCorners(img.Image image, int radius) {
    final w = image.width;
    final h = image.height;
    final r = min(radius, min(w, h) ~/ 2);
    if (r <= 0) return;
    final r2 = r * r;

    void clearPixel(int x, int y) {
      final pixel = image.getPixel(x, y);
      img.setPixelRgba(
        image,
        x,
        y,
        img.getRed(pixel),
        img.getGreen(pixel),
        img.getBlue(pixel),
        0,
      );
    }

    for (int y = 0; y < r; y++) {
      for (int x = 0; x < r; x++) {
        final dx = r - 1 - x;
        final dy = r - 1 - y;
        if (dx * dx + dy * dy > r2) {
          clearPixel(x, y);
          clearPixel(w - 1 - x, y);
          clearPixel(x, h - 1 - y);
          clearPixel(w - 1 - x, h - 1 - y);
        }
      }
    }
  }
}

class StripCompositorException implements Exception {
  final String message;
  const StripCompositorException(this.message);

  @override
  String toString() => 'StripCompositorException: $message';
}
