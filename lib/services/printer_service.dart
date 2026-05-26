import 'dart:typed_data';

import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

class PrinterService {
  // Standard XPrinter BLE service/characteristic UUIDs (unchanged).
  static const String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid =
      '00002af1-0000-1000-8000-00805f9b34fb';

  // XP-N160II print head is 576 dots wide (80 mm × 8 dots/mm × 0.9 coverage).
  static const int _paperWidthPx = 576;

  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    chunkSize: 512,
    interChunkDelayMs: 30,
  );

  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = _paperWidthPx,
  }) async {
    try {
      await _transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      // Send init command and give the printer a moment to apply the reset
      // before the raster data starts arriving.
      await _transport.sendData(ImageRasterizer.buildInitCommand());
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      await _transport.sendData(rasterPayload);

      // Wait for the printer to finish consuming the raster buffer before
      // issuing the cut. 600 ms covers even tall photo-strip payloads.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _transport.sendData(ImageRasterizer.buildFeedCutCommand());
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    } on ImageRasterizerException catch (e) {
      throw PrinterException(e.message);
    }
  }

  static void disconnect() {
    _transport.disconnect();
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);
  @override
  String toString() => 'PrinterException: $message';
}
