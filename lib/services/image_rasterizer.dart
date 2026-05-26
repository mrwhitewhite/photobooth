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

  static Uint8List buildInitCommand() {
    return Uint8List.fromList([
      0x1B,
      0x40,
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

    img.onload = (web.Event _) {
      loadCompleter.complete();
    }.toJS;
    img.onerror = (web.Event _) {
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
          'Decoded image has zero dimensions.');
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
      final a = rgba[base + 3] / 255.0;
      final r = rgba[base] * a + 255.0 * (1.0 - a);
      final g = rgba[base + 1] * a + 255.0 * (1.0 - a);
      final b = rgba[base + 2] * a + 255.0 * (1.0 - a);

      grey[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    }

    final out = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final oldVal = grey[idx].clamp(0.0, 255.0);
        final newVal = oldVal < 128.0 ? 0.0 : 255.0;
        out[idx] = newVal.toInt();
        final err = oldVal - newVal;

        if (x + 1 < width) {
          grey[idx + 1] = (grey[idx + 1] + err * 7.0 / 16.0).clamp(0.0, 255.0);
        }
        if (y + 1 < height) {
          if (x - 1 >= 0) {
            grey[(y + 1) * width + (x - 1)] =
                (grey[(y + 1) * width + (x - 1)] + err * 3.0 / 16.0)
                    .clamp(0.0, 255.0);
          }
          grey[(y + 1) * width + x] =
              (grey[(y + 1) * width + x] + err * 5.0 / 16.0).clamp(0.0, 255.0);
          if (x + 1 < width) {
            grey[(y + 1) * width + (x + 1)] =
                (grey[(y + 1) * width + (x + 1)] + err * 1.0 / 16.0)
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
    final payload = Uint8List(8 + bytesPerRow * height);

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
        int packed = 0;
        for (int bit = 0; bit < 8; bit++) {
          final col = byteIdx * 8 + bit;
          if (col < width && monoPixels[rowBase + col] == 0) {
            packed |= (0x80 >> bit);
          }
        }
        payload[offset++] = packed;
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
