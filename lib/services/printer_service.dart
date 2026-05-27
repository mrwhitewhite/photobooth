import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_manager.dart';

class PrinterService {
  static const int _paperWidthDots = 576;

  static Future<void> printReceipt(Uint8List imageBytes) async {
    try {
      await ensureBluetoothPermissions();

      final saved = await BluetoothManager.getSavedDevice();
      if (saved == null) {
        throw const PrinterException('No printer selected.');
      }

      if (!await XprinterConnection.isConnected()) {
        await XprinterConnection.connect(
          type: XprinterConnectionType.bluetooth,
          address: saved.id,
        );
      }

      await PosPrinter.initialize();

      // 1. Decode the image into a manipulatable object
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        throw const PrinterException('Decoding failed.');
      }

      // 2. Define your chunk height (e.g., 200–300 pixels per chunk)
      int chunkHeight = 250;
      int totalHeight = originalImage.height;

      // 3. Loop through and print the image section by section
      for (int y = 0; y < totalHeight; y += chunkHeight) {
        int currentChunkHeight =
            (y + chunkHeight > totalHeight) ? totalHeight - y : chunkHeight;

        // Crop a vertical slice of the image
        final croppedSlice = img.copyCrop(
          originalImage,
          x: 0,
          y: y,
          width: originalImage.width,
          height: currentChunkHeight,
        );

        // Convert this specific slice into bitmap bytes for Xprinter
        final bitmapBytes = XprinterImageLoader.fromBytes(
          bytes: Uint8List.fromList(img.encodePng(croppedSlice)),
          targetWidthDots: _paperWidthDots,
          mode: XprinterImageMode.dither,
        );

        if (bitmapBytes != null) {
          // Print the individual slice
          await PosPrinter.printBitmap(
            bitmapBytes,
            alignment: XprinterAlignment.center,
            widthDots: _paperWidthDots,
          );

          // CRITICAL: Pause for 150-300ms to let the Bluetooth buffer clear
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // 4. Wrap up the print job
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
