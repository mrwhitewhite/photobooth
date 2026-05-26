import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'image_rasterizer.dart';
import 'printer_debug.dart';
import 'web_bluetooth_transport.dart';

class PrinterService {
  // UUIDs confirmed for Xprinter XP-N160II (18F0 / 2AF1 pair).
  static const String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid =
      '00002af1-0000-1000-8000-00805f9b34fb';

  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    chunkSize: 512,
    interChunkDelayMs: 0,
  );

  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576,
  }) async {
    try {
      printerLog('Requesting Bluetooth permissions...');
      await ensureBluetoothPermissions();

      printerLog('Connecting to printer...');
      await _transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      printerLog('Sending init command...');
      await _transport.sendData(ImageRasterizer.buildInitCommand());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      printerLog('Rasterizing image (paperWidthPx=$paperWidthPx)...');
      final rasterPayload = await ImageRasterizer.processAndBuildRaster(
        imageBytes,
        paperWidthPx: paperWidthPx,
      );

      printerLog('Sending raster payload (${rasterPayload.length} bytes)...');
      await _transport.sendData(rasterPayload);

      await Future<void>.delayed(const Duration(milliseconds: 500));

      printerLog('Sending feed+cut command...');
      await _transport.sendData(ImageRasterizer.buildFeedCutCommand());

      printerLog('Print complete.');
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    } on ImageRasterizerException catch (e) {
      throw PrinterException(e.message);
    }
  }

  static void disconnect() {
    _transport.disconnect();
  }

  static Future<void> ensureBluetoothPermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final statuses = await permissions.request();
    final denied = statuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key.toString());
    if (denied.isNotEmpty) {
      throw PrinterException(
        'Bluetooth permissions denied: ${denied.join(', ')}. '
        'Please grant them in Settings.',
      );
    }
    printerLog('All Bluetooth permissions granted.');
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
