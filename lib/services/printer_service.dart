import 'dart:typed_data';

import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

class PrinterService {
  static const String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid =
      '00002af1-0000-1000-8000-00805f9b34fb';

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

      await _transport.sendData(ImageRasterizer.buildInitCommand());
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      await _transport.sendData(rasterPayload);

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
