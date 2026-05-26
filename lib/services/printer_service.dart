import 'dart:typed_data';

import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

class PrinterService {
  static String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';

  static String characteristicUuid = '00002af1-0000-1000-8000-00805f9b34fb';

  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    // 504 = 72 bytes/row × 7 rows for 576 px (80 mm @ 203 dpi) paper.
    // Aligning chunks to row boundaries prevents the print head from
    // pausing mid-row between Bluetooth packets, which is the primary cause
    // of the "1-2-1-2" banding artifact.
    chunkSize: 512,
    // 0 ms: write-with-response already provides backpressure;
    // an extra artificial delay only gives the print head more time
    // to cool unevenly between chunks.
    interChunkDelayMs: 0,
  );

  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576,
  }) async {
    try {
      await _transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      await _transport.sendData(ImageRasterizer.buildInitCommand());

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      await _transport.sendData(rasterPayload);

      await Future<void>.delayed(const Duration(milliseconds: 500));
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
