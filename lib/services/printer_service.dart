import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:x_printer/x_printer.dart';

/// Service for printing images over Bluetooth using a thermal printer.
///
/// Uses the [XPrinter] package to scan, connect, and print base64-encoded
/// images. All methods are static for convenient access throughout the app.
class PrinterService {
  static final XPrinter _printer = XPrinter();

  /// The duration to wait for a Bluetooth device to appear during scanning.
  static const Duration _scanTimeout = Duration(seconds: 10);

  /// Whether the printer is currently connected.
  static Future<bool> get isConnected => _printer.isConnected;

  /// Scans for nearby Bluetooth printers and connects to the first one found.
  ///
  /// Listens to [peripheralsStream] for discovered devices. Connects to the
  /// first device with a non-null UUID.
  ///
  /// Throws a [PrinterException] if no device is discovered within the
  /// timeout period or if the connection attempt fails.
  static Future<void> scanAndConnect() async {
    try {
      final completer = Completer<String>();

      late final StreamSubscription<List<Peripheral>> subscription;
      subscription = _printer.peripheralsStream.listen(
        (peripherals) {
          if (completer.isCompleted) return;
          for (final device in peripherals) {
            if (device.uuid != null && device.uuid!.isNotEmpty) {
              completer.complete(device.uuid!);
              subscription.cancel();
              return;
            }
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) {
            completer.completeError(
              PrinterException('Scan failed: $error'),
            );
          }
          subscription.cancel();
        },
      );

      // Start scanning — devices will arrive via peripheralsStream.
      await _printer.startScan();

      final uuid = await completer.future.timeout(
        _scanTimeout,
        onTimeout: () {
          subscription.cancel();
          _printer.stopScan();
          throw PrinterException(
            'No printer found within ${_scanTimeout.inSeconds} seconds',
          );
        },
      );

      await _printer.stopScan();
      await _printer.connect(uuid);
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException('Failed to scan and connect: $e');
    }
  }

  /// Prints an image from raw image bytes.
  ///
  /// If the printer is not already connected, this will automatically scan
  /// for nearby devices and connect to the first one found before printing.
  ///
  /// [imageBytes] should contain the raw bytes of a valid image (e.g. PNG).
  ///
  /// Throws a [PrinterException] if connection or printing fails.
  static Future<void> printReceipt(Uint8List imageBytes) async {
    try {
      final connected = await isConnected;
      if (!connected) {
        await scanAndConnect();
      }

      final base64String = base64Encode(imageBytes);
      await _printer.printImage(base64String);
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException('Failed to print: $e');
    }
  }

  /// Disconnects from the currently connected printer.
  ///
  /// Safe to call even if no printer is connected.
  static Future<void> disconnect() async {
    try {
      await _printer.disconnect();
    } catch (e) {
      throw PrinterException('Failed to disconnect: $e');
    }
  }
}

/// Exception thrown when a printer operation fails.
class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => 'PrinterException: $message';
}
