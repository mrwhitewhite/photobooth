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

  // ESC @ (reset) — no line-spacing override so the printer uses its default
  // gap between rows. ESC 3 0x00 was setting line spacing to 0 which caused
  // adjacent raster rows to bleed into each other on the XP-N160II.
  // ESC a 1 = centre alignment (kept).
  static Uint8List buildInitCommand() {
    return Uint8List.fromList([
      0x1B, 0x40, // ESC @  — full printer reset
      0x1B, 0x61, 0x01, // ESC a 1 — centre alignment
    ]);
  }

  // ESC 2 restores the default line spacing (1/6 inch) before feeding.
  // GS V 66 0x00 = partial cut with a 0-dot feed before the knife.
  static Uint8List buildFeedCutCommand() {
    return Uint8List.fromList([
      0x1B, 0x32, // ESC 2  — restore default line spacing
      0x1B, 0x64, 0x05, // ESC d 5 — feed 5 lines
      0x1D, 0x56, 0x42, 0x00, // GS V 66 0 — partial cut
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

    // Step-down halving for high-quality downscaling (unchanged — this is fine).
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

  // Fixed Floyd-Steinberg dithering — strictly left-to-right on every row.
  //
  // The previous implementation alternated scan direction (serpentine /
  // boustrophedon). While serpentine dithering reduces overall error, it
  // creates a visible seam at every row reversal that thermal print heads
  // render as a bright horizontal band across the whole image. Fixing the
  // direction to always LTR removes the seam entirely.
  //
  // Tone adjustments also removed: pow(lum, 0.85) + contrast * 1.5 pushed
  // midtones too close to the 128 threshold, amplifying the dither pattern
  // and making banding worse. The XP-N160II's print density is good enough
  // that a clean linear luminance conversion prints well without pre-cooking.
  static Uint8List _floydSteinbergDither(
    Uint8ClampedList rgba,
    int width,
    int height,
  ) {
    final totalPixels = width * height;

    // Convert RGBA → linear greyscale, flattening alpha over white.
    final grey = Float64List(totalPixels);
    for (int i = 0; i < totalPixels; i++) {
      final base = i * 4;
      final a = rgba[base + 3] / 255.0;
      final r = rgba[base] * a + 255.0 * (1.0 - a);
      final g = rgba[base + 1] * a + 255.0 * (1.0 - a);
      final b = rgba[base + 2] * a + 255.0 * (1.0 - a);
      // Standard Rec. 601 luminance — no gamma hack.
      grey[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    }

    final out = Uint8List(totalPixels);

    // Always left-to-right — eliminates the serpentine reversal seam.
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final oldVal = grey[idx].clamp(0.0, 255.0);
        final newVal = oldVal < 128.0 ? 0.0 : 255.0;
        out[idx] = newVal.toInt();
        final err = oldVal - newVal;

        // Standard F-S kernel (right, bottom-left, bottom, bottom-right).
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

  // GS v 0 — raster bit image. Header is 8 bytes; pixel data follows.
  // Width must be a multiple of 8 bits; we pad the last byte automatically.
  static Uint8List _buildGsV0Payload(
    Uint8List monoPixels,
    int width,
    int height,
  ) {
    final bytesPerRow = (width + 7) ~/ 8;
    final payload = Uint8List(8 + bytesPerRow * height);

    // GS v 0  mode=0 (normal density)
    payload[0] = 0x1D;
    payload[1] = 0x76;
    payload[2] = 0x30;
    payload[3] = 0x00;
    // xL xH — bytes per row (little-endian)
    payload[4] = bytesPerRow & 0xFF;
    payload[5] = (bytesPerRow >> 8) & 0xFF;
    // yL yH — number of rows (little-endian)
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
            packed |= (0x80 >> bit); // MSB first, 0 = black dot
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
