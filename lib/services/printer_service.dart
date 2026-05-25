import 'dart:typed_data';

import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

class PrinterService {
  static String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';

  static String characteristicUuid = '00002af1-0000-1000-8000-00805f9b34fb';

  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576,
  }) async {
    try {
      // Chunk size must be a multiple of bytesPerRow so BLE packet boundaries
      // never split a raster row. Splitting mid-row causes the thermal head to
      // pause inside a row, producing visible horizontal banding.
      // 5 rows per chunk is a good balance of throughput and safety margin.
      final rowBytes = ImageRasterizer.bytesPerRow(paperWidthPx);
      final alignedChunkSize = rowBytes * 5; // e.g. 72 * 5 = 360 for 576px

      final transport = WebBluetoothTransport(
        chunkSize: alignedChunkSize,
        interChunkDelayMs: 20,
      );

      await transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      await transport.sendData(ImageRasterizer.buildInitCommand());

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      await transport.sendData(rasterPayload);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      await transport.sendData(ImageRasterizer.buildFeedCutCommand());
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    } on ImageRasterizerException catch (e) {
      throw PrinterException(e.message);
    }
  }

  static void disconnect() {
    // Transport is created per-print; nothing to disconnect statically.
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}