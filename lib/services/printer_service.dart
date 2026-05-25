import 'dart:typed_data';

import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PrinterService — Orchestrator
// ─────────────────────────────────────────────────────────────────────────────

class PrinterService {
  // ── Configurable UUIDs ─────────────────────────────────────────────────

  /// BLE GATT service UUID. Override for non-standard models.
  static String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';

  /// Writable BLE GATT characteristic UUID.
  static String characteristicUuid = '00002af1-0000-1000-8000-00805f9b34fb';

  // ── Internal transport ─────────────────────────────────────────────────

  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    chunkSize: 100,
    interChunkDelayMs: 50,
  );

  // FIX: Concurrency guard preventing overlapping BLE stream corruptions
  static bool _isPrinting = false;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Prints [imageBytes] (PNG) silently to the paired XPrinter via BLE.
  ///
  /// Default [paperWidthPx] is explicitly hardcoded to 576, which perfectly
  /// matches your 80mm thermal paper printable area at 203 DPI.
  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576, // 80 mm @ 203 dpi
  }) async {
    // Prevent double-triggering while a job is actively chunking
    if (_isPrinting) {
      throw const PrinterException(
          'A print job is already in progress. Please wait.');
    }

    _isPrinting = true;

    try {
      // 1. Establish BLE connection (no-op if already connected).
      await _transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      // 2. Send ESC/POS initialisation (reset + center alignment).
      await _transport.sendData(ImageRasterizer.buildInitCommand());

      // Small settle time after hardware reset
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 3. Process the image: decode → downscale → dither → GS v 0.
      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      // 4. Stream the raster payload over BLE.
      //    The transport handles 100-byte chunking with write-with-response
      //    ACKs and 50 ms inter-chunk pacing.
      await _transport.sendData(rasterPayload);

      // 5. Feed paper and cut.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _transport.sendData(ImageRasterizer.buildFeedCutCommand());
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    } on ImageRasterizerException catch (e) {
      throw PrinterException(e.message);
    } finally {
      // CRITICAL: Always release lock, even if an exception occurs mid-flight
      _isPrinting = false;
    }
  }

  /// Disconnects the cached BLE device (if any) and forces a new
  /// device-picker on the next [printReceipt] call.
  static void disconnect() {
    _transport.disconnect();
    _isPrinting = false; // Reset state on manual drop
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Exception type
// ─────────────────────────────────────────────────────────────────────────────

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
