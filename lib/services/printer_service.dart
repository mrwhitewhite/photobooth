import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for printing images over Bluetooth using a thermal printer.
///
/// Uses the [BlueThermalPrinter] package to scan, connect, and print image bytes.
/// All methods are static for convenient access throughout the app.
class PrinterService {
  static final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  /// Ensure required Bluetooth permissions are granted on Android.
  /// Throws [PrinterException] if permissions are denied.
  static Future<void> _ensureBluetoothPermissions() async {
    if (!Platform.isAndroid) return;

    final permissions = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.location,
    ];

    final statuses = await permissions.request();

    final grantedConnect =
        statuses[Permission.bluetoothConnect]?.isGranted == true ||
            statuses[Permission.bluetooth]?.isGranted == true;
    final grantedScan = statuses[Permission.bluetoothScan]?.isGranted == true ||
        statuses[Permission.location]?.isGranted == true ||
        statuses[Permission.locationWhenInUse]?.isGranted == true;

    if (!grantedConnect || !grantedScan) {
      throw const PrinterException('Bluetooth permissions not granted');
    }
  }

  /// Whether the printer is currently connected.
  static Future<bool?> get isConnected => _printer.isConnected;

  /// Scans for nearby Bluetooth printers and connects to the first one found.
  ///
  /// Listens to [peripheralsStream] for discovered devices. Connects to the
  /// first device with a non-null UUID.
  ///
  /// Throws a [PrinterException] if no device is discovered within the
  /// timeout period or if the connection attempt fails.
  static Future<void> scanAndConnect() async {
    try {
      await _ensureBluetoothPermissions();
      final devices = await _printer.getBondedDevices();
      if (devices.isEmpty) {
        throw const PrinterException('No bonded Bluetooth printers found');
      }

      // Prefer the first bonded printer, but log available bonded devices.
      for (final device in devices) {
        debugPrint(
            'blue_thermal_printer: bonded device name=${device.name ?? "<no-name>"} address=${device.address ?? "<no-address>"}');
      }

      final device = devices.first;
      try {
        await _printer.connect(device);
      } catch (e) {
        throw PrinterException(
            'Failed to connect to printer (address=${device.address}): $e');
      }
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
      await _ensureBluetoothPermissions();
      final connected = await isConnected;
      if (connected != true) {
        await scanAndConnect();
      }

      try {
        await _printer.printImageBytes(imageBytes);
      } catch (e) {
        throw PrinterException('Print failed: $e');
      }
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
