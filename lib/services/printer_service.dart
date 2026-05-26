import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'bluetooth_manager.dart';
import 'image_rasterizer.dart';
import 'web_bluetooth_transport.dart';

class PrinterService {
  static const String serviceUuid = '';
  static const String characteristicUuid = '';

  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    chunkSize: 512,
    interChunkDelayMs: 0,
  );

  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = 576,
  }) async {
    try {
      await ensureBluetoothPermissions();

      final saved = await BluetoothManager.getSavedDevice();
      if (saved == null) {
        throw const PrinterException(
          'No printer selected. Please select a Bluetooth printer first.',
        );
      }

      await _transport.connectToDeviceId(
        deviceId: saved.id,
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

  static Future<void> ensureBluetoothPermissions() async {
    final permissions = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final statuses = await permissions.request();
    final denied = statuses.values.where((status) => !status.isGranted);
    if (denied.isNotEmpty) {
      throw const PrinterException(
        'Bluetooth permissions are required to print.',
      );
    }
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
