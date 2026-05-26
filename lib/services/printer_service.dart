import 'dart:typed_data';

import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_manager.dart';

class PrinterService {
  static const int _paperWidthDots = 576; // 80 mm paper

  static Future<void> printReceipt(Uint8List imageBytes) async {
    try {
      await ensureBluetoothPermissions();

      final saved = await BluetoothManager.getSavedDevice();
      if (saved == null) {
        throw const PrinterException(
          'No printer selected. Please select a Bluetooth printer first.',
        );
      }

      // Reconnect if not already connected.
      if (!await XprinterConnection.isConnected()) {
        await XprinterConnection.connect(
          type: XprinterConnectionType.bluetooth,
          address: saved.id,
        );
      }

      // Initialise printer.
      await PosPrinter.initialize();

      // Prepare and print the bitmap using the SDK's built-in pipeline.
      // XprinterImageLoader handles: alpha flatten → resize → dither.
      final bitmapBytes = XprinterImageLoader.fromBytes(
        bytes: imageBytes,
        targetWidthDots: _paperWidthDots,
        mode: XprinterImageMode.dither, // Floyd-Steinberg for photos
      );

      if (bitmapBytes == null) {
        throw const PrinterException('Image preparation failed.');
      }

      await PosPrinter.printBitmap(
        bitmapBytes,
        alignment: XprinterAlignment.center, // Added 'alignment:'
        widthDots: _paperWidthDots,
      );

      // Feed and cut.
      await PosPrinter.feedLine(5);
      await PosPrinter.cutPaper();
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    }
  }

  static void disconnect() {
    XprinterConnection.disconnect();
  }

  static Future<void> ensureBluetoothPermissions() async {
    final permissions = <Permission>[
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

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);

  @override
  String toString() => 'PrinterTransportException: $message';
}
