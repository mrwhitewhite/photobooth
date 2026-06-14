import 'dart:typed_data';

import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_manager.dart';

class PrinterService {
  static const int _paperWidthDots = 576;

  /// Brightness multiplier applied before printing.
  /// 1.0 = no change, >1.0 = lighter. 1.3 ≈ 30% brighter.
  static const double _printBrightness = 1.3;

  /// Gamma correction for print output.
  /// >1.0 lifts midtones, improving detail in dithered thermal prints.
  static const double _printGamma = 1.3;

  /// Pre-processes image bytes for thermal printing by boosting brightness
  /// and applying gamma correction. This keeps the on-screen preview
  /// unaffected while ensuring the printed output is ~30% lighter.
  static Uint8List _brightenForPrint(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const PrinterException(
        'Failed to decode image for print brightness adjustment.',
      );
    }

    // Linear brightness boost — lifts all pixel values proportionally.
    final brightened = img.adjustColor(decoded, brightness: _printBrightness);

    // Gamma correction — non-linear curve that especially lightens midtones,
    // which is critical for dithered thermal output where midtones tend to
    // clump into solid black.
    final corrected = img.gamma(brightened, gamma: _printGamma);

    return Uint8List.fromList(img.encodePng(corrected));
  }

  static Future<void> printReceipt(Uint8List imageBytes) async {
    try {
      await ensureBluetoothPermissions();

      final saved = await BluetoothManager.getSavedDevice();
      if (saved == null) {
        throw const PrinterException(
          'No printer selected. Please select a Bluetooth printer first.',
        );
      }

      if (!await XprinterConnection.isConnected()) {
        await XprinterConnection.connect(
          type: XprinterConnectionType.bluetooth,
          address: saved.id,
        );
      }

      await PosPrinter.initialize();

      // Brighten image before sending to the thermal printer.
      final printReadyBytes = _brightenForPrint(imageBytes);

      final bitmapBytes = XprinterImageLoader.fromBytes(
        bytes: printReadyBytes,
        targetWidthDots: _paperWidthDots,
        mode: XprinterImageMode.dither,
      );

      if (bitmapBytes == null) {
        throw const PrinterException('Image preparation failed.');
      }

      await PosPrinter.printBitmap(
        bitmapBytes,
        alignment: XprinterAlignment.center,
        widthDots: _paperWidthDots,
      );

      await PosPrinter.feedLine(4);
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
