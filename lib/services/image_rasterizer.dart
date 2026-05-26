import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageRasterizer {
  static Future<Uint8List> processAndBuildRaster(
    Uint8List pngBytes, {
    required int paperWidthPx,
  }) async {
    final rgba = await _decodePngToRgba(pngBytes, paperWidthPx);

    final mono = _floydSteinbergDither(rgba.pixels, rgba.width, rgba.height);

    return _buildGsV0Payload(mono, rgba.width, rgba.height);
  }

  static Uint8List buildInitCommand() {
    return Uint8List.fromList([
      0x1B,
      0x40,
      0x1B,
      0x33,
      0x00,
      0x1B,
      0x61,
      0x01,
    ]);
  }

  static Uint8List buildFeedCutCommand() {
    return Uint8List.fromList([
      0x1B,
      0x32,
      0x1B,
      0x64,
      0x05,
      0x1D,
      0x56,
      0x42,
      0x00,
    ]);
  }

  static Future<_RgbaImage> _decodePngToRgba(
    Uint8List pngBytes,
    int targetWidthPx,
  ) async {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) {
      throw const ImageRasterizerException('PNG decode failed.');
    }

    final srcW = decoded.width;
    final srcH = decoded.height;

    if (srcW == 0 || srcH == 0) {
      throw const ImageRasterizerException(
        'Decoded image has zero dimensions.',
      );
    }

    final scale = targetWidthPx / srcW;
    final targetW = targetWidthPx;
    final targetH = (srcH * scale).round();

    var current = decoded;
    while (current.width > targetW * 2) {
      final nextW = (current.width / 2).round();
      final nextH = (current.height / 2).round();
      current = img.copyResize(
        current,
        width: nextW,
        height: nextH,
        interpolation: img.Interpolation.cubic,
      );
    }

    final resized = img.copyResize(
      current,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.cubic,
    );

    final rgbaBytes = Uint8ClampedList(targetW * targetH * 4);
    int offset = 0;
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final p = resized.getPixel(x, y);
        rgbaBytes[offset++] = p.r.toInt();
        rgbaBytes[offset++] = p.g.toInt();
        rgbaBytes[offset++] = p.b.toInt();
        rgbaBytes[offset++] = p.a.toInt();
      }
    }
    return _RgbaImage(
      pixels: Uint8ClampedList.fromList(rgbaBytes),
      width: targetW,
      height: targetH,
    );
  }

  static Uint8List _floydSteinbergDither(
    Uint8ClampedList rgba,
    int width,
    int height,
  ) {
    final totalPixels = width * height;

    final grey = Float64List(totalPixels);

    for (int i = 0; i < totalPixels; i++) {
      final base = i * 4;
      final r = rgba[base];
      final g = rgba[base + 1];
      final b = rgba[base + 2];
      final a = rgba[base + 3];

      final alphaFrac = a / 255.0;
      final blendedR = r * alphaFrac + 255.0 * (1.0 - alphaFrac);
      final blendedG = g * alphaFrac + 255.0 * (1.0 - alphaFrac);
      final blendedB = b * alphaFrac + 255.0 * (1.0 - alphaFrac);

      double lum = 0.299 * blendedR + 0.587 * blendedG + 0.114 * blendedB;

      lum = 255.0 * pow((lum / 255.0).clamp(0.0, 1.0), 1.1).toDouble();

      const factor = 1.25;
      lum = ((lum - 128.0) * factor + 128.0).clamp(0.0, 255.0);

      grey[i] = lum;
    }

    final out = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
      final bool ltr = (y % 2 == 0);

      if (ltr) {
        for (int x = 0; x < width; x++) {
          final idx = y * width + x;
          final oldPixel = grey[idx].clamp(0.0, 255.0);
          final newPixel = oldPixel < 128.0 ? 0.0 : 255.0;
          out[idx] = newPixel.toInt();
          final err = oldPixel - newPixel;

          if (x + 1 < width) {
            grey[idx + 1] =
                (grey[idx + 1] + err * 7.0 / 16.0).clamp(0.0, 255.0);
          }
          if (y + 1 < height && x - 1 >= 0) {
            grey[(y + 1) * width + (x - 1)] =
                (grey[(y + 1) * width + (x - 1)] + err * 3.0 / 16.0)
                    .clamp(0.0, 255.0);
          }
          if (y + 1 < height) {
            grey[(y + 1) * width + x] =
                (grey[(y + 1) * width + x] + err * 5.0 / 16.0)
                    .clamp(0.0, 255.0);
          }
          if (y + 1 < height && x + 1 < width) {
            grey[(y + 1) * width + (x + 1)] =
                (grey[(y + 1) * width + (x + 1)] + err * 1.0 / 16.0)
                    .clamp(0.0, 255.0);
          }
        }
      } else {
        for (int x = width - 1; x >= 0; x--) {
          final idx = y * width + x;
          final oldPixel = grey[idx].clamp(0.0, 255.0);
          final newPixel = oldPixel < 128.0 ? 0.0 : 255.0;
          out[idx] = newPixel.toInt();
          final err = oldPixel - newPixel;

          if (x - 1 >= 0) {
            grey[idx - 1] =
                (grey[idx - 1] + err * 7.0 / 16.0).clamp(0.0, 255.0);
          }

          if (y + 1 < height && x + 1 < width) {
            grey[(y + 1) * width + (x + 1)] =
                (grey[(y + 1) * width + (x + 1)] + err * 3.0 / 16.0)
                    .clamp(0.0, 255.0);
          }
          if (y + 1 < height) {
            grey[(y + 1) * width + x] =
                (grey[(y + 1) * width + x] + err * 5.0 / 16.0)
                    .clamp(0.0, 255.0);
          }

          if (y + 1 < height && x - 1 >= 0) {
            grey[(y + 1) * width + (x - 1)] =
                (grey[(y + 1) * width + (x - 1)] + err * 1.0 / 16.0)
                    .clamp(0.0, 255.0);
          }
        }
      }
    }

    return out;
  }

  static Uint8List _buildGsV0Payload(
    Uint8List monoPixels,
    int width,
    int height,
  ) {
    final bytesPerRow = (width + 7) ~/ 8;
    final pixelDataSize = bytesPerRow * height;

    final totalSize = 8 + pixelDataSize;
    final payload = Uint8List(totalSize);

    payload[0] = 0x1D;
    payload[1] = 0x76;
    payload[2] = 0x30;
    payload[3] = 0x00;

    payload[4] = bytesPerRow & 0xFF;
    payload[5] = (bytesPerRow >> 8) & 0xFF;

    payload[6] = height & 0xFF;
    payload[7] = (height >> 8) & 0xFF;

    int offset = 8;
    for (int row = 0; row < height; row++) {
      final rowBase = row * width;
      for (int byteIdx = 0; byteIdx < bytesPerRow; byteIdx++) {
        int packedByte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final col = byteIdx * 8 + bit;
          if (col < width) {
            if (monoPixels[rowBase + col] == 0) {
              packedByte |= (0x80 >> bit);
            }
          }
        }
        payload[offset++] = packedByte;
      }
    }

    return payload;
  }
}

class _RgbaImage {
  final Uint8ClampedList pixels;
  final int width;
  final int height;

  const _RgbaImage({
    required this.pixels,
    required this.width,
    required this.height,
  });
}

class ImageRasterizerException implements Exception {
  final String message;
  const ImageRasterizerException(this.message);

  @override
  String toString() => 'ImageRasterizerException: $message';
}
