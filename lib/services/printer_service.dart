import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

// ─────────────────────────────────────────────────────────────────────────────
//  JS interop shims for Web Bluetooth
// ─────────────────────────────────────────────────────────────────────────────

@JS('navigator.bluetooth.requestDevice')
external JSPromise _requestDevice(JSObject options);

@JS()
extension type _BluetoothDevice._(JSObject _) implements JSObject {
  external JSString get name;
  external _BluetoothRemoteGATTServer get gatt;
}

@JS()
extension type _BluetoothRemoteGATTServer._(JSObject _) implements JSObject {
  external JSPromise connect();
  external JSPromise getPrimaryService(JSAny service);
}

@JS()
extension type _BluetoothRemoteGATTService._(JSObject _) implements JSObject {
  external JSPromise getCharacteristic(JSAny characteristic);
}

@JS()
extension type _BluetoothRemoteGATTCharacteristic._(JSObject _)
    implements JSObject {
  external JSPromise writeValueWithResponse(JSArrayBuffer value);
  external JSPromise writeValueWithoutResponse(JSArrayBuffer value);
}

// ─────────────────────────────────────────────────────────────────────────────
//  PrinterService
// ─────────────────────────────────────────────────────────────────────────────

/// Sends a composite photo strip directly to an XPrinter over BLE.
///
/// Uses the Web Bluetooth API (Chromium-based browsers only) — **no print
/// dialog appears**.  The user will see a one-time device-picker when they
/// first tap PRINT (required by the Web Bluetooth security model); after that
/// the [_cachedCharacteristic] is reused for every subsequent print.
///
/// ## XPrinter BLE UUIDs
/// Most XPrinter BLE models use:
///   • Service :  `0x18F0`
///   • Write Characteristic: `0x18F1`
///
/// If your unit uses different UUIDs, override [serviceUuid] /
/// [characteristicUuid] in the [printReceipt] call or update the defaults.
class PrinterService {
  // ── Configurable UUIDs ───────────────────────────────────────────────────

  /// BLE GATT service UUID.  Override for non-standard models.
  static String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';

  /// Writable BLE GATT characteristic UUID.
  static String characteristicUuid = '00002af1-0000-1000-8000-00805f9b34fb';

  /// Max bytes per BLE write packet (most printers handle 512 bytes fine).
  static const int _chunkSize = 512;

  /// Max rows per raster band.  Thermal printers have a small internal raster
  /// buffer; sending too many rows in a single GS v 0 command causes the
  /// printer to overlay rows (the "layered" artefact).  24 rows matches the
  /// typical thermal print-head dot height — if layering persists, try
  /// lowering to 8 or even 1.
  static const int _maxBandRows = 24;

  /// Milliseconds to wait between BLE write packets within a single band.
  static const int _interChunkDelayMs = 50;

  /// Milliseconds to wait between raster bands.  This gives the printer time
  /// to physically print the band and advance the paper before receiving the
  /// next GS v 0 command.  Increase to 300–500 if layering still occurs.
  static const int _interBandDelayMs = 200;

  // ── Cached connection ────────────────────────────────────────────────────

  static _BluetoothRemoteGATTCharacteristic? _cachedCharacteristic;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Prints [imageBytes] (PNG) silently to the paired XPrinter via BLE.
  ///
  /// [paperWidthPx] should match the thermal paper width in pixels at the
  /// printer's DPI (e.g. 576 px for 80 mm at 203 dpi, 384 for 58 mm).
  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576, // 80 mm @ 203 dpi
  }) async {
    // 1. Get (or acquire) the BLE write characteristic.
    final characteristic = await _getCharacteristic();

    // 2. Decode PNG → 1-bit dithered monochrome pixels.
    final prepared = await _prepareImage(imageBytes, paperWidthPx);

    // 3. Send ESC/POS initialisation header.
    await _sendChunked(characteristic, Uint8List.fromList([
      0x1B, 0x40,             // ESC @   — reset / initialise printer
      0x1B, 0x61, 0x01,       // ESC a 1 — center alignment
      0x1B, 0x33, 0x00,       // ESC 3 0 — set line spacing to 0 (no gaps
                              //           between raster bands)
    ]));

    // 4. Send image band-by-band with pauses for mechanical advance.
    await _sendImageBands(characteristic, prepared);

    // 5. Restore default line spacing, feed, and cut.
    await _sendChunked(characteristic, Uint8List.fromList([
      0x1B, 0x32,             // ESC 2   — restore default line spacing
      0x1B, 0x64, 0x05,       // ESC d 5 — feed 5 lines
      0x1D, 0x56, 0x42, 0x00, // GS V B 0 — partial cut
    ]));
  }

  /// Disconnects the cached BLE device (if any) and forces a new device-picker
  /// on the next [printReceipt] call.
  static void disconnect() {
    _cachedCharacteristic = null;
  }

  // ── BLE helpers ──────────────────────────────────────────────────────────

  static Future<_BluetoothRemoteGATTCharacteristic>
      _getCharacteristic() async {
    if (_cachedCharacteristic != null) return _cachedCharacteristic!;

    // Build the requestDevice options object.
    final filters = [
      {'services': _shortUuidList(serviceUuid)},
    ].jsify();

    final optionalServices = _shortUuidList(serviceUuid).jsify();

    final options = {
      'filters': filters,
      'optionalServices': optionalServices,
    }.jsify() as JSObject;

    // Show the browser's BLE device picker (requires a user gesture — the
    // PRINT button tap satisfies this).
    final deviceRaw = await _requestDevice(options).toDart;
    final device = deviceRaw as _BluetoothDevice;

    final serverRaw = await device.gatt.connect().toDart;
    final server = serverRaw as _BluetoothRemoteGATTServer;

    final serviceRaw =
        await server.getPrimaryService(serviceUuid.toJS).toDart;
    final service = serviceRaw as _BluetoothRemoteGATTService;

    final charRaw =
        await service.getCharacteristic(characteristicUuid.toJS).toDart;
    final characteristic = charRaw as _BluetoothRemoteGATTCharacteristic;

    _cachedCharacteristic = characteristic;
    
    return characteristic;
  }

  /// Wraps a UUID string inside a list (requestDevice optionalServices
  /// accepts both short 16-bit ints and full 128-bit strings).
  static List<String> _shortUuidList(String uuid) => [uuid];

  /// Sends [data] over BLE in [_chunkSize]-byte packets with a small delay
  /// between each packet to avoid overflowing the printer's BLE buffer.
  static Future<void> _sendChunked(
    _BluetoothRemoteGATTCharacteristic characteristic,
    Uint8List data,
  ) async {
    int offset = 0;
    while (offset < data.length) {
      final end = math.min(offset + _chunkSize, data.length);
      final chunk = data.sublist(offset, end);
      final jsBuffer = chunk.buffer.toJS;
      try {
        await characteristic.writeValueWithResponse(jsBuffer).toDart;
      } catch (_) {
        // Some printers only support writeWithoutResponse.
        await characteristic.writeValueWithoutResponse(jsBuffer).toDart;
      }
      offset = end;
      // Delay between BLE packets to avoid overflowing printer buffer.
      await Future<void>.delayed(
        const Duration(milliseconds: _interChunkDelayMs),
      );
    }
  }

  // ── Image preparation ────────────────────────────────────────────────────

  /// Decodes the PNG, resizes it to [targetWidthPx] wide (preserving aspect),
  /// and converts to 1-bit monochrome using Atkinson dithering.
  ///
  /// Returns a [_PreparedImage] containing the mono pixel data and dimensions.
  static Future<_PreparedImage> _prepareImage(
    Uint8List pngBytes,
    int targetWidthPx,
  ) async {
    // Decode the PNG via a temporary canvas element.
    final canvas = web.HTMLCanvasElement();
    final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;

    final blob = web.Blob(
      [pngBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final objectUrl = web.URL.createObjectURL(blob);

    final img = web.HTMLImageElement();
    final completer = Completer<void>();
    img.onload = ((JSAny? _) => completer.complete()).toJS;
    img.onerror = ((JSAny? _, JSAny? __, JSAny? ___, JSAny? ____, JSAny? _____) =>
        completer.completeError(const PrinterException(
            'Image decode failed during ESC/POS conversion.'))).toJS;
    img.src = objectUrl;
    await completer.future;

    web.URL.revokeObjectURL(objectUrl);

    final srcW = img.naturalWidth;
    final srcH = img.naturalHeight;

    // Scale so width == targetWidthPx, keep aspect ratio.
    final scale = targetWidthPx / srcW;
    final printW = targetWidthPx;
    final printH = (srcH * scale).round();

    canvas.width = printW;
    canvas.height = printH;
    ctx.drawImage(img, 0, 0, printW, printH);

    final imageData = ctx.getImageData(0, 0, printW, printH);
    // imageData.data is a JSUint8ClampedArray; convert to Dart first.
    final pixels = imageData.data.toDart; // Uint8ClampedList RGBA

    // Convert RGBA → 1-bit using Atkinson dithering.
    final monoPixels = _atkinsonDither(pixels, printW, printH);

    return _PreparedImage(monoPixels: monoPixels, width: printW, height: printH);
  }

  // ── Band-by-band raster sending ─────────────────────────────────────────

  /// Sends the raster image in small bands, waiting [_interBandDelayMs]
  /// between each band so the printer can physically print and advance the
  /// paper.  This is the key fix for the "layered" artefact — the previous
  /// approach packed all bands into one byte array and streamed it
  /// continuously, which overflowed the printer's internal raster buffer.
  static Future<void> _sendImageBands(
    _BluetoothRemoteGATTCharacteristic characteristic,
    _PreparedImage image,
  ) async {
    final bytesPerRow = (image.width + 7) ~/ 8;
    int rowsSent = 0;

    while (rowsSent < image.height) {
      final bandRows = math.min(_maxBandRows, image.height - rowsSent);

      // Build this band's complete GS v 0 command + pixel data.
      final bandBytes = _buildBand(
        image.monoPixels,
        image.width,
        bytesPerRow,
        rowsSent,
        bandRows,
      );

      // Send this band over BLE (internally chunked with inter-chunk delays).
      await _sendChunked(characteristic, bandBytes);

      rowsSent += bandRows;

      // ── Critical: wait for the printer to finish this band ──────────────
      // Without this delay the printer receives the next GS v 0 command
      // before it has finished processing (and physically advancing past)
      // the current band, which causes row overlap / layering.
      if (rowsSent < image.height) {
        await Future<void>.delayed(
          const Duration(milliseconds: _interBandDelayMs),
        );
      }
    }
  }

  /// Builds one GS v 0 raster command containing [bandRows] rows of 1-bit
  /// pixel data starting at [startRow].
  static Uint8List _buildBand(
    Uint8List monoPixels,
    int width,
    int bytesPerRow,
    int startRow,
    int bandRows,
  ) {
    final xL = bytesPerRow & 0xFF;
    final xH = (bytesPerRow >> 8) & 0xFF;
    final yL = bandRows & 0xFF;
    final yH = (bandRows >> 8) & 0xFF;

    final out = BytesBuilder();

    // GS v 0 m xL xH yL yH d1...dk
    // m = 0 → normal density, no scaling.
    out.add([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);

    // Pack 1-bit pixel rows for this band.
    for (int row = startRow; row < startRow + bandRows; row++) {
      for (int byteIdx = 0; byteIdx < bytesPerRow; byteIdx++) {
        int b = 0;
        for (int bit = 0; bit < 8; bit++) {
          final col = byteIdx * 8 + bit;
          if (col < width) {
            final pixelIndex = row * width + col;
            if (monoPixels[pixelIndex] == 0) {
              // Black pixel → set bit (MSB first).
              b |= (0x80 >> bit);
            }
          }
        }
        out.addByte(b);
      }
    }

    return out.toBytes();
  }

  // ── Atkinson dithering ───────────────────────────────────────────────────

  /// Returns a flat array of 0/255 values (0 = black, 255 = white) for a
  /// 1-bit dithered representation of the source RGBA pixels.
  static Uint8List _atkinsonDither(
    Uint8ClampedList src,
    int width,
    int height,
  ) {
    final grey = Float64List(width * height);
    for (int i = 0; i < width * height; i++) {
      final r = src[i * 4];
      final g = src[i * 4 + 1];
      final b = src[i * 4 + 2];
      grey[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    }

    final out = Uint8List(width * height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final oldPixel = grey[idx].clamp(0, 255);
        final newPixel = oldPixel < 128 ? 0.0 : 255.0;
        out[idx] = newPixel.toInt();
        final err = (oldPixel - newPixel) / 8.0;

        void spread(int dx, int dy) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
            grey[ny * width + nx] += err;
          }
        }

        spread(1, 0);
        spread(2, 0);
        spread(-1, 1);
        spread(0, 1);
        spread(1, 1);
        spread(0, 2);
      }
    }

    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper types
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the 1-bit monochrome pixel data and image dimensions produced by
/// [PrinterService._prepareImage].
class _PreparedImage {
  final Uint8List monoPixels;
  final int width;
  final int height;

  const _PreparedImage({
    required this.monoPixels,
    required this.width,
    required this.height,
  });
}

// ── Exception type ────────────────────────────────────────────────────────────

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
