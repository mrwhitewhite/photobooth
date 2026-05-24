import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

// ─────────────────────────────────────────────────────────────────────────────
//  ImageRasterizer
// ─────────────────────────────────────────────────────────────────────────────
//
// Handles the complete image-processing pipeline for thermal printing:
//
//   PNG bytes → Canvas decode → Multi-pass downscale → Atkinson dither
//     → 1-bit monochrome → GS v 0 ESC/POS raster command
//
// This class has NO knowledge of BLE, transport, or printer connectivity.
// It is a pure image-processing + byte-layout utility.
// ─────────────────────────────────────────────────────────────────────────────

class ImageRasterizer {
  /// Processes a PNG image and returns a complete ESC/POS `GS v 0` raster
  /// payload ready to be sent to the printer in one shot.
  ///
  /// **Pipeline:**
  /// 1. Decode PNG via HTML Canvas `<img>` element
  /// 2. Multi-pass downscale to [paperWidthPx] with high-quality smoothing
  /// 3. Atkinson error-diffusion dithering → 1-bit monochrome
  /// 4. Pack into a single `GS v 0` raster command (header + pixel data)
  ///
  /// The single-command approach eliminates horizontal banding artifacts
  /// caused by multiple consecutive raster commands.
  static Future<Uint8List> processAndBuildRaster(
    Uint8List pngBytes, {
    required int paperWidthPx,
  }) async {
    // ── Step 1: Decode the PNG via an HTML <img> element ─────────────────
    final rgba = await _decodePngToRgba(pngBytes, paperWidthPx);

    // ── Step 2: Atkinson dither RGBA → 1-bit monochrome ─────────────────
    final mono = _atkinsonDither(rgba.pixels, rgba.width, rgba.height);

    // ── Step 3: Pack into GS v 0 raster command ─────────────────────────
    return _buildGsV0Payload(mono, rgba.width, rgba.height);
  }

  // ── ESC/POS command helpers ───────────────────────────────────────────────

  /// Returns the ESC/POS initialisation sequence:
  ///
  /// ```
  /// ESC @     (0x1B 0x40)   — Reset / initialise printer
  /// ESC a 1   (0x1B 0x61 0x01) — Center alignment
  /// ```
  ///
  /// This should be sent before the raster payload to ensure the printer
  /// is in a known state.
  static Uint8List buildInitCommand() {
    return Uint8List.fromList([
      0x1B, 0x40, //       ESC @ — hardware reset
      0x1B, 0x61, 0x01, // ESC a 1 — center alignment
    ]);
  }

  /// Returns the ESC/POS feed-and-cut sequence:
  ///
  /// ```
  /// ESC d 5       (0x1B 0x64 0x05)         — Feed 5 lines
  /// GS V B 0      (0x1D 0x56 0x42 0x00)    — Partial cut
  /// ```
  ///
  /// This should be sent after the raster payload to advance the paper
  /// past the cutter blade and perform a partial cut.
  static Uint8List buildFeedCutCommand() {
    return Uint8List.fromList([
      0x1B, 0x64, 0x05, //       ESC d 5 — feed 5 lines
      0x1D, 0x56, 0x42, 0x00, // GS V B 0 — partial cut
    ]);
  }

  // ── PNG decoding + multi-pass downscaling ─────────────────────────────────

  /// Decodes a PNG from raw bytes into RGBA pixel data, resized to
  /// [targetWidthPx] using a high-quality multi-pass downscaling algorithm.
  ///
  /// **Why multi-pass?**
  /// A single-step large-ratio downscale (e.g. 3000px → 384px) causes
  /// severe aliasing and blurring because the browser's canvas interpolation
  /// is optimised for ratios close to 1.0.  By halving iteratively until
  /// we're within 2× of the target, each step produces high-quality output.
  ///
  /// Each intermediate step uses:
  ///   - `imageSmoothingEnabled = true`
  ///   - `imageSmoothingQuality = 'high'`  (triggers Lanczos3 in Chromium)
  static Future<_RgbaImage> _decodePngToRgba(
    Uint8List pngBytes,
    int targetWidthPx,
  ) async {
    // Create a Blob and object URL to load the PNG into an <img> element.
    final blob = web.Blob(
      [pngBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final objectUrl = web.URL.createObjectURL(blob);

    // Load the image asynchronously.
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

    // Clean up the object URL immediately — the <img> has already decoded
    // the pixel data into memory.
    web.URL.revokeObjectURL(objectUrl);

    final srcW = img.naturalWidth;
    final srcH = img.naturalHeight;

    if (srcW == 0 || srcH == 0) {
      throw const ImageRasterizerException(
        'Decoded image has zero dimensions.',
      );
    }

    // ── Compute target dimensions (preserve aspect ratio) ───────────────
    final scale = targetWidthPx / srcW;
    final targetW = targetWidthPx;
    final targetH = (srcH * scale).round();

    // ── Multi-pass step-down scaling ────────────────────────────────────
    //
    // Strategy:
    //   1. Draw the full-resolution image onto an initial canvas.
    //   2. While the current width is more than 2× the target, halve it
    //      by drawing onto a new canvas at 50% size.
    //   3. Final step: draw from the last intermediate size to the exact
    //      target dimensions.
    //
    // Each step uses the browser's high-quality interpolation (Lanczos3
    // in Chromium), which produces excellent results for ratios between
    // 0.5 and 1.0.

    var currentW = srcW;
    var currentH = srcH;

    // Initial canvas: full-resolution source.
    var currentCanvas = web.HTMLCanvasElement();
    currentCanvas.width = currentW;
    currentCanvas.height = currentH;
    var currentCtx = _getHighQualityContext(currentCanvas);
    currentCtx.drawImage(img, 0, 0, currentW, currentH);

    // Iterative 50% reductions.
    while (currentW > targetW * 2) {
      final nextW = (currentW / 2).round();
      final nextH = (currentH / 2).round();

      final nextCanvas = web.HTMLCanvasElement();
      nextCanvas.width = nextW;
      nextCanvas.height = nextH;
      final nextCtx = _getHighQualityContext(nextCanvas);

      // Draw the current canvas at half size onto the next canvas.
      nextCtx.drawImage(currentCanvas, 0, 0, nextW, nextH);

      currentCanvas = nextCanvas;
      currentW = nextW;
      currentH = nextH;
    }

    // Final step: draw from intermediate size to exact target dimensions.
    final finalCanvas = web.HTMLCanvasElement();
    finalCanvas.width = targetW;
    finalCanvas.height = targetH;
    final finalCtx = _getHighQualityContext(finalCanvas);
    finalCtx.drawImage(currentCanvas, 0, 0, targetW, targetH);

    // Extract RGBA pixel data from the final canvas.
    final imageData = finalCtx.getImageData(0, 0, targetW, targetH);
    final pixels = imageData.data.toDart; // Uint8ClampedList (RGBA)

    return _RgbaImage(pixels: pixels, width: targetW, height: targetH);
  }

  /// Returns a 2D canvas context with high-quality image smoothing enabled.
  ///
  /// The `imageSmoothingQuality = 'high'` hint tells Chromium to use its
  /// best downsampling filter (Lanczos3), which preserves fine details like
  /// thin text strokes and hairline rules much better than the default
  /// bilinear filter.
  static web.CanvasRenderingContext2D _getHighQualityContext(
    web.HTMLCanvasElement canvas,
  ) {
    final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    ctx.imageSmoothingEnabled = true;
    // Set imageSmoothingQuality via JS interop bracket operator since
    // package:web ^0.5 may not expose this property on the typed binding.
    (ctx as JSObject)['imageSmoothingQuality'] = 'high'.toJS;
    return ctx;
  }

  // ── Atkinson dithering ────────────────────────────────────────────────────

  /// Converts RGBA pixel data to 1-bit monochrome using Atkinson dithering.
  ///
  /// **Atkinson dithering** diffuses only 6/8 (75%) of the quantisation error,
  /// which produces sharper, higher-contrast output compared to Floyd–Steinberg
  /// (which diffuses 100%).  This makes it ideal for thermal printers where
  /// excessive error diffusion creates muddy midtones.
  ///
  /// **Kernel layout** (error fraction = err/8 each):
  /// ```
  ///         *   1   1
  ///     1   1   1
  ///         1
  /// ```
  ///
  /// **Alpha handling:** Semi-transparent pixels are pre-blended against a
  /// white background before luminance conversion.  This ensures transparent
  /// PNG regions print as white (paper color) rather than black.
  ///
  /// Returns a `Uint8List` of length `width × height` where each element is
  /// `0` (black) or `255` (white).
  static Uint8List _atkinsonDither(
    Uint8ClampedList rgba,
    int width,
    int height,
  ) {
    final totalPixels = width * height;

    // ── Convert RGBA → grayscale (alpha-aware) ──────────────────────────
    //
    // We use Float64List for the working buffer to preserve sub-pixel
    // precision during error diffusion.  Rounding to int at each step would
    // accumulate quantisation noise and degrade output quality.
    final grey = Float64List(totalPixels);

    for (int i = 0; i < totalPixels; i++) {
      final base = i * 4;
      final r = rgba[base];
      final g = rgba[base + 1];
      final b = rgba[base + 2];
      final a = rgba[base + 3];

      // Alpha blending against white (255).
      // If alpha = 255 (opaque), this reduces to the standard formula.
      // If alpha = 0 (transparent), luminance = 255.0 (white = paper).
      final alphaFrac = a / 255.0;
      final blendedR = r * alphaFrac + 255.0 * (1.0 - alphaFrac);
      final blendedG = g * alphaFrac + 255.0 * (1.0 - alphaFrac);
      final blendedB = b * alphaFrac + 255.0 * (1.0 - alphaFrac);

      // BT.601 luminance (standard for sRGB content).
      grey[i] = 0.299 * blendedR + 0.587 * blendedG + 0.114 * blendedB;
    }

    // ── Error-diffusion dithering ───────────────────────────────────────
    final out = Uint8List(totalPixels);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final oldPixel = grey[idx].clamp(0.0, 255.0);

        // Threshold: below 128 → black (0), above → white (255).
        final newPixel = oldPixel < 128.0 ? 0.0 : 255.0;
        out[idx] = newPixel.toInt();

        // Atkinson distributes 6/8 of the error (each neighbour gets 1/8).
        final err = (oldPixel - newPixel) / 8.0;

        // Spread error to 6 neighbours (bounds-checked).
        // Right +1
        if (x + 1 < width) {
          grey[idx + 1] += err;
        }
        // Right +2
        if (x + 2 < width) {
          grey[idx + 2] += err;
        }
        // Below-left
        if (x - 1 >= 0 && y + 1 < height) {
          grey[(y + 1) * width + (x - 1)] += err;
        }
        // Below
        if (y + 1 < height) {
          grey[(y + 1) * width + x] += err;
        }
        // Below-right
        if (x + 1 < width && y + 1 < height) {
          grey[(y + 1) * width + (x + 1)] += err;
        }
        // Two rows below
        if (y + 2 < height) {
          grey[(y + 2) * width + x] += err;
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
    // Each row is packed into ceil(width/8) bytes.
    final bytesPerRow = (width + 7) ~/ 8;
    final pixelDataSize = bytesPerRow * height;

    // Total payload = 8-byte GS v 0 header + pixel data.
    final totalSize = 8 + pixelDataSize;
    final payload = Uint8List(totalSize);

    // ── Write the GS v 0 header ─────────────────────────────────────────
    payload[0] = 0x1D; // GS
    payload[1] = 0x76; // v
    payload[2] = 0x30; // 0
    payload[3] = 0x00; // m = normal density, no scaling

    // xL/xH: bytes per row (little-endian 16-bit).
    payload[4] = bytesPerRow & 0xFF;
    payload[5] = (bytesPerRow >> 8) & 0xFF;

    // yL/yH: total rows (little-endian 16-bit).
    payload[6] = height & 0xFF;
    payload[7] = (height >> 8) & 0xFF;

    // ── Pack 1-bit pixel data (MSB first) ───────────────────────────────
    //
    // For each row and each byte position within that row, we pack 8
    // horizontal pixels into a single byte.  Bit 7 (MSB) is the leftmost
    // pixel; bit 0 (LSB) is the rightmost.
    //
    // A pixel value of 0 in monoPixels means "black" → set the bit (1).
    // A pixel value of 255 means "white" → leave the bit clear (0).
    int offset = 8;
    for (int row = 0; row < height; row++) {
      final rowBase = row * width;
      for (int byteIdx = 0; byteIdx < bytesPerRow; byteIdx++) {
        int packedByte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final col = byteIdx * 8 + bit;
          if (col < width) {
            if (monoPixels[rowBase + col] == 0) {
              // Black pixel → set bit (MSB first).
              packedByte |= (0x80 >> bit);
            }
          }
          // Out-of-bounds columns (past image width) remain 0 (white),
          // which is correct — no heat applied to padding bits.
        }
        payload[offset++] = packedByte;
      }
    }

    return payload;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper types
// ─────────────────────────────────────────────────────────────────────────────

/// Holds decoded RGBA pixel data and image dimensions.
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

// ─────────────────────────────────────────────────────────────────────────────
//  Exception type
// ─────────────────────────────────────────────────────────────────────────────

/// Exception thrown by [ImageRasterizer] when image processing fails.
class ImageRasterizerException implements Exception {
  final String message;
  const ImageRasterizerException(this.message);

  @override
  String toString() => 'ImageRasterizerException: $message';
}
