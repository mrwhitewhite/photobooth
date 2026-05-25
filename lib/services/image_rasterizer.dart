import 'dart:async';
import 'dart:math' show pow;
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

//

//

//

class ImageRasterizer {
  /// Processes a PNG image and returns a complete ESC/POS `GS v 0` raster
  /// payload ready to be sent to the printer in one shot.
  ///
  /// **Pipeline:**
  /// 1. Decode PNG via HTML Canvas `<img>` element
  /// 2. Multi-pass downscale to [paperWidthPx] with high-quality smoothing
  /// 3. Contrast + gamma enhancement for thermal printing
  /// 4. Floyd-Steinberg error-diffusion dithering → 1-bit monochrome
  /// 5. Pack into a single `GS v 0` raster command (header + pixel data)
  ///
  /// The single-command approach eliminates horizontal banding artifacts
  /// caused by multiple consecutive raster commands.
  static Future<Uint8List> processAndBuildRaster(
    Uint8List pngBytes, {
    required int paperWidthPx,
  }) async {
    final rgba = await _decodePngToRgba(pngBytes, paperWidthPx);

    // ── Step 2: Floyd-Steinberg dither RGBA → 1-bit monochrome ──────────
    // Floyd-Steinberg diffuses 100% of error — gives smoother gradients
    // and fewer visible banding lines compared to Atkinson for photos.
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

    //

    //

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

  // ── Floyd-Steinberg dithering ─────────────────────────────────────────────

  /// Converts RGBA pixel data to 1-bit monochrome using Floyd-Steinberg
  /// dithering with contrast enhancement and gamma correction.
  ///
  /// **Why Floyd-Steinberg for photos?**
  /// Floyd–Steinberg diffuses 100% of the quantisation error across 4
  /// neighbours, producing smooth gradients with minimal visible banding.
  /// This is ideal for photographic content where fine tonal transitions
  /// need to be preserved (skin tones, backgrounds, shadows).
  ///
  /// **Kernel layout** (fractions of error):
  /// ```
  ///         *   7/16
  ///   3/16  5/16  1/16
  /// ```
  ///
  /// **Pre-processing steps applied before dithering:**
  /// 1. Alpha-blend against white background
  /// 2. Gamma correction (γ=0.85) — brightens midtones so they survive
  ///    the binary threshold without going solid black
  /// 3. Contrast boost (+20 levels) — sharpens edges for clarity
  ///
  /// Returns a `Uint8List` of length `width × height` where each element is
  /// `0` (black) or `255` (white).
  static Uint8List _floydSteinbergDither(
    Uint8ClampedList rgba,
    int width,
    int height,
  ) {
    final totalPixels = width * height;

    // ── Step A: Convert RGBA → grayscale with alpha blending ───────────
    final grey = Float64List(totalPixels);

    for (int i = 0; i < totalPixels; i++) {
      final base = i * 4;
      final r = rgba[base];
      final g = rgba[base + 1];
      final b = rgba[base + 2];
      final a = rgba[base + 3];

      // Alpha blending against white (255).
      final alphaFrac = a / 255.0;
      final blendedR = r * alphaFrac + 255.0 * (1.0 - alphaFrac);
      final blendedG = g * alphaFrac + 255.0 * (1.0 - alphaFrac);
      final blendedB = b * alphaFrac + 255.0 * (1.0 - alphaFrac);

      // BT.601 luminance.
      double lum = 0.299 * blendedR + 0.587 * blendedG + 0.114 * blendedB;

      // ── Step B: Gamma correction (γ < 1.0 brightens midtones) ────────
      // Thermal paper tends to over-darken, so we lift the midtones
      // slightly before thresholding to preserve photo detail.
      // Gamma 0.85 brightens by ~10% — adjust between 0.75–1.0 to taste.
      lum = 255.0 * pow((lum / 255.0).clamp(0.0, 1.0), 1.5).toDouble();

      // ── Step C: Contrast boost ────────────────────────────────────────
      // Pulls shadows darker and highlights brighter by a fixed amount.
      // Factor: 1.25 gives a noticeable but not excessive contrast lift.
      const factor = 2.25; // 1.0 = no change, >1.0 increases contrast
      lum = ((lum - 128.0) * factor + 128.0).clamp(0.0, 255.0);

      grey[i] = lum;
    }

    // ── Step D: Serpentine Floyd-Steinberg error diffusion ───────────────
    //
    // Serpentine (bidirectional) scanning alternates left→right and
    // right→left each row.  This prevents error from always accumulating
    // in the same horizontal direction, which is the root cause of the
    // "1-2-1-2" banding artifact on thermal printers.
    //
    // When scanning right→left the error kernel is mirrored:
    //   Normal (L→R):  * 7/16 | 3/16 5/16 1/16 (below)
    //   Mirrored (R→L): 7/16 * | 1/16 5/16 3/16 (below)
    final out = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
      final bool ltr = (y % 2 == 0); // true = left-to-right

      if (ltr) {
        // ── Left → Right ────────────────────────────────────────────────
        for (int x = 0; x < width; x++) {
          final idx = y * width + x;
          final oldPixel = grey[idx].clamp(0.0, 255.0);
          final newPixel = oldPixel < 128.0 ? 0.0 : 255.0;
          out[idx] = newPixel.toInt();
          final err = oldPixel - newPixel;

          if (x + 1 < width)
            grey[idx + 1] =
                (grey[idx + 1] + err * 7.0 / 16.0).clamp(0.0, 255.0);
          if (y + 1 < height && x - 1 >= 0)
            grey[(y + 1) * width + (x - 1)] =
                (grey[(y + 1) * width + (x - 1)] + err * 3.0 / 16.0)
                    .clamp(0.0, 255.0);
          if (y + 1 < height)
            grey[(y + 1) * width + x] =
                (grey[(y + 1) * width + x] + err * 5.0 / 16.0)
                    .clamp(0.0, 255.0);
          if (y + 1 < height && x + 1 < width)
            grey[(y + 1) * width + (x + 1)] =
                (grey[(y + 1) * width + (x + 1)] + err * 1.0 / 16.0)
                    .clamp(0.0, 255.0);
        }
      } else {
        // ── Right → Left (mirrored kernel) ──────────────────────────────
        for (int x = width - 1; x >= 0; x--) {
          final idx = y * width + x;
          final oldPixel = grey[idx].clamp(0.0, 255.0);
          final newPixel = oldPixel < 128.0 ? 0.0 : 255.0;
          out[idx] = newPixel.toInt();
          final err = oldPixel - newPixel;

          // Left neighbour gets 7/16 (direction is now rightward in output)
          if (x - 1 >= 0)
            grey[idx - 1] =
                (grey[idx - 1] + err * 7.0 / 16.0).clamp(0.0, 255.0);
          // Below-right: 3/16 (mirrored from below-left)
          if (y + 1 < height && x + 1 < width)
            grey[(y + 1) * width + (x + 1)] =
                (grey[(y + 1) * width + (x + 1)] + err * 3.0 / 16.0)
                    .clamp(0.0, 255.0);
          if (y + 1 < height)
            grey[(y + 1) * width + x] =
                (grey[(y + 1) * width + x] + err * 5.0 / 16.0)
                    .clamp(0.0, 255.0);
          // Below-left: 1/16 (mirrored from below-right)
          if (y + 1 < height && x - 1 >= 0)
            grey[(y + 1) * width + (x - 1)] =
                (grey[(y + 1) * width + (x - 1)] + err * 1.0 / 16.0)
                    .clamp(0.0, 255.0);
        }
      }
    }

    return out;
  }


  // ── GS v 0 raster payload construction ────────────────────────────────────

  /// Packs dithered 1-bit monochrome pixel data into a single, continuous
  /// `GS v 0` ESC/POS raster bit-image command.
  ///
  /// **Command format:**
  /// ```
  /// Byte 0:   0x1D (GS)
  /// Byte 1:   0x76 (v)
  /// Byte 2:   0x30 (0)
  /// Byte 3:   m     — mode (0 = normal density, no scaling)
  /// Byte 4:   xL    — bytes per row, low byte
  /// Byte 5:   xH    — bytes per row, high byte
  /// Byte 6:   yL    — total rows, low byte
  /// Byte 7:   yH    — total rows, high byte
  /// Byte 8+:  d1…dk — packed 1-bit pixel data (MSB = leftmost pixel)
  /// ```
  ///
  /// **Why a single command?**
  /// Sending the image as multiple small raster commands (one per band)
  /// causes horizontal banding artifacts because each command boundary
  /// triggers a mechanical print-head pause, thermal cool/heat cycle, and
  /// firmware-level paper advance rounding.  A single command tells the
  /// printer to process the entire image in one continuous operation.
  ///
  /// **Bit layout:**
  /// Each byte encodes 8 horizontal pixels, MSB first.
  /// A set bit (1) = black dot.  A clear bit (0) = white (no heat).
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

    //

    //

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
