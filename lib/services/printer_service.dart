import 'dart:typed_data';

import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PrinterService — Orchestrator
// ─────────────────────────────────────────────────────────────────────────────
//
// A thin coordination layer that wires [WebBluetoothTransport] (BLE comms)
// and [ImageRasterizer] (image processing + ESC/POS) together.
//
// The public API is intentionally identical to the previous monolithic
// implementation so that all call sites (e.g. PreviewScreen) work without
// modification.
//
// Flow:
//   printReceipt(imageBytes) →
//     1. transport.connect()
//     2. send ESC/POS init command
//     3. processAndBuildRaster(imageBytes, paperWidthPx)
//     4. send raster payload
//     5. send feed + cut command
// ─────────────────────────────────────────────────────────────────────────────

/// Sends a composite photo strip directly to an XPrinter over BLE.
///
/// Uses the Web Bluetooth API (Chromium-based browsers only) — **no print
/// dialog appears**.  The user will see a one-time device-picker when they
/// first tap PRINT (required by the Web Bluetooth security model); after that
/// the connection is reused for every subsequent print.
///
/// ## XPrinter BLE UUIDs
/// Most XPrinter BLE models use:
///   • Service:              `0x18F0`
///   • Write Characteristic: `0x2AF1`
///
/// If your unit uses different UUIDs, update [serviceUuid] /
/// [characteristicUuid] before calling [printReceipt].
class PrinterService {
  // ── Configurable UUIDs ─────────────────────────────────────────────────

  /// BLE GATT service UUID.  Override for non-standard models.
  static String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';

  /// Writable BLE GATT characteristic UUID.
  static String characteristicUuid = '00002af1-0000-1000-8000-00805f9b34fb';

  // ── Internal transport ─────────────────────────────────────────────────

  /// Single shared transport instance.  The transport caches the BLE
  /// characteristic internally, so repeated [printReceipt] calls reuse
  /// the existing connection without showing the device picker again.
  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    chunkSize: 200,
    interChunkDelayMs: 30,
  );

  // ── Public API ─────────────────────────────────────────────────────────

  /// Prints [imageBytes] (PNG) silently to the paired XPrinter via BLE.
  ///
  /// [paperWidthPx] should match the thermal paper width in pixels at the
  /// printer's DPI (e.g. 576 px for 80 mm at 203 dpi, 384 for 58 mm).
  ///
  /// **Pipeline:**
  /// 1. Establish BLE connection (or reuse cached)
  /// 2. Send ESC/POS hardware reset + center alignment
  /// 3. Decode PNG → multi-pass downscale → Atkinson dither → GS v 0
  /// 4. Stream the complete raster payload over BLE
  /// 5. Feed paper and perform partial cut
  ///
  /// Throws [PrinterException] on image processing or BLE errors.
  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576, // 80 mm @ 203 dpi
  }) async {
    try {
      // 1. Establish BLE connection (no-op if already connected).
      await _transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      // 2. Send ESC/POS initialisation (reset + center alignment).
      await _transport.sendData(ImageRasterizer.buildInitCommand());

      // Small settle time after hardware reset — the printer needs a
      // moment to process the init sequence before accepting raster data.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 3. Process the image: decode → downscale → dither → GS v 0.
      //    This happens entirely in the browser via HTML Canvas; no
      //    network calls or native plugins involved.
      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      // 4. Stream the raster payload over BLE.
      //    The transport handles 200-byte chunking with write-with-response
      //    ACKs and 30 ms inter-chunk pacing.  The printer receives the
      //    entire image as a single continuous GS v 0 raster operation.
      await _transport.sendData(rasterPayload);

      // 5. Feed paper and cut.
      //    Wait for the printer to finish processing the last raster
      //    chunks before sending the feed+cut command.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _transport.sendData(ImageRasterizer.buildFeedCutCommand());
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    } on ImageRasterizerException catch (e) {
      throw PrinterException(e.message);
    }
  }

  /// Disconnects the cached BLE device (if any) and forces a new
  /// device-picker on the next [printReceipt] call.
  static void disconnect() {
    _transport.disconnect();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Exception type
// ─────────────────────────────────────────────────────────────────────────────

/// Exception thrown by [PrinterService] when printing fails.
///
/// This is the only exception type surfaced to the UI layer.  Internal
/// transport and image-processing exceptions are caught and re-wrapped.
class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
