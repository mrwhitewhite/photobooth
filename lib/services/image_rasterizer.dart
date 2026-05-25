import 'dart:async';

import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class ImageRasterizer {
  static Future<Uint8List> processAndBuildRaster(
    Uint8List pngBytes, {
    required int paperWidthPx,
  }) async {
    final rgba = await _decodePngToRgba(pngBytes, paperWidthPx);

    final mono = _floydSteinbergDither(rgba.pixels, rgba.width, rgba.height);

    return _buildGsV0Payload(mono, rgba.width, rgba.height);
  }

  /// Returns the number of bytes per raster row for a given paper width.
  /// Use this to compute a BLE chunk size that is always row-aligned,
  /// which prevents mid-row chunk boundaries causing thermal banding.
  static int bytesPerRow(int paperWidthPx) => (paperWidthPx + 7) ~/ 8;

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
    final blob = web.Blob(
      [pngBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final objectUrl = web.URL.createObjectURL(blob);

    final img = web.HTMLImageElement();
    final loadCompleter = Completer<void>();

    img.onload = (web.Event event) {
      loadCompleter.complete();
    }.toJS;
    img.onerror = (web.Event event) {
      loadCompleter.completeError(
        const ImageRasterizerException('PNG decode failed.'),
      );
    }.toJS;

    img.src = objectUrl;
    await loadCompleter.future;

    web.URL.revokeObjectURL(objectUrl);

    final srcW = img.naturalWidth;
    final srcH = img.naturalHeight;

    if (srcW == 0 || srcH == 0) {
      throw const ImageRasterizerException(
        'Decoded image has zero dimensions.',
      );
    }

    final scale = targetWidthPx / srcW;
    final targetW = targetWidthPx;
    final targetH = (srcH * scale).round();

    var currentW = srcW;
    var currentH = srcH;

    var currentCanvas = web.HTMLCanvasElement();
    currentCanvas.width = currentW;
    currentCanvas.height = currentH;
    var currentCtx = _getHighQualityContext(currentCanvas);
    currentCtx.drawImage(img, 0, 0, currentW, currentH);

    while (currentW > targetW * 2) {
      final nextW = (currentW / 2).round();
      final nextH = (currentH / 2).round();

      final nextCanvas = web.HTMLCanvasElement();
      nextCanvas.width = nextW;
      nextCanvas.height = nextH;
      final nextCtx = _getHighQualityContext(nextCanvas);

      nextCtx.drawImage(currentCanvas, 0, 0, nextW, nextH);

      currentCanvas = nextCanvas;
      currentW = nextW;
      currentH = nextH;
    }

    final finalCanvas = web.HTMLCanvasElement();
    finalCanvas.width = targetW;
    finalCanvas.height = targetH;
    final finalCtx = _getHighQualityContext(finalCanvas);
    finalCtx.drawImage(currentCanvas, 0, 0, targetW, targetH);

    final imageData = finalCtx.getImageData(0, 0, targetW, targetH);
    final pixels = imageData.data.toDart;

    return _RgbaImage(pixels: pixels, width: targetW, height: targetH);
  }

  static web.CanvasRenderingContext2D _getHighQualityContext(
    web.HTMLCanvasElement canvas,
  ) {
    final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    ctx.imageSmoothingEnabled = true;

    (ctx as JSObject)['imageSmoothingQuality'] = 'high'.toJS;
    return ctx;
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

      const contrastFactor = 1.5;
      const brightnessOffset = 20.0;

      lum = ((lum - 128.0) * contrastFactor + 128.0 + brightnessOffset)
          .clamp(0.0, 255.0);
      grey[i] = lum;
    }

    final out = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
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
    }

    return out;
  }

  static Uint8List _buildGsV0Payload(
    Uint8List monoPixels,
    int width,
    int height,
  ) {
    final bytesPerRow = (width + 7) ~/ 8;

    final BytesBuilder payloadBuilder = BytesBuilder();

    // Single GS v 0 command for the entire image (no slicing).
    // Height field is 16-bit so supports up to 65535 lines.
    payloadBuilder.add([
      0x1D,
      0x76,
      0x30,
      0x00,
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
    ]);

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
        payloadBuilder.addByte(packedByte);
      }
    }

    return payloadBuilder.toBytes();
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