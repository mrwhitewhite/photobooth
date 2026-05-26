import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'printer_debug.dart';

class WebBluetoothTransport {
  final int chunkSize;
  final int interChunkDelayMs;

  WebBluetoothTransport({
    this.chunkSize = 512,
    this.interChunkDelayMs = 0,
  });

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cachedCharacteristic;

  bool get isConnected => _cachedCharacteristic != null;

  Future<void> connect({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (_device != null && _cachedCharacteristic != null) {
      final state = await _device!.connectionState.first;
      if (state == BluetoothConnectionState.connected) {
        printerLog('Already connected — reusing existing connection.');
        return;
      }
      printerLog('Stale connection detected — reconnecting.');
      _cachedCharacteristic = null;
      _device = null;
    }

    final serviceGuid = Guid(serviceUuid);
    final characteristicGuid = Guid(characteristicUuid);

    try {
      printerLog('Starting BLE scan (no service filter)...');

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

      ScanResult target;
      try {
        final results = await FlutterBluePlus.scanResults
            .timeout(const Duration(seconds: 12))
            .firstWhere(
              (results) => results.any(_isXprinter),
            );
        target = results.firstWhere(_isXprinter);
      } on TimeoutException {
        throw const PrinterTransportException(
          'No Xprinter found within scan timeout. '
          'Make sure the printer is on and in range.',
        );
      }

      printerLog(
        'Found device: "${target.device.platformName}" '
        '(${target.device.remoteId}), RSSI=${target.rssi}',
      );

      await FlutterBluePlus.stopScan();

      _device = target.device;

      await _device!.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      printerLog('GATT connected.');

      final services = await _device!.discoverServices();

      if (kPrinterDebug) {
        printerLog('--- Discovered GATT services ---');
        for (final s in services) {
          printerLog('  Service: ${s.uuid}');
          for (final c in s.characteristics) {
            printerLog(
              '    Char: ${c.uuid} '
              '| write=${c.properties.write} '
              '| writeNoResp=${c.properties.writeWithoutResponse} '
              '| notify=${c.properties.notify}',
            );
          }
        }
        printerLog('--------------------------------');
      }

      final service = services.firstWhere(
        (s) => s.uuid == serviceGuid,
        orElse: () => throw PrinterTransportException(
          'Service $serviceUuid not found on printer. '
          'Check UUID or enable kPrinterDebug to see available services.',
        ),
      );

      final characteristic = service.characteristics.firstWhere(
        (c) => c.uuid == characteristicGuid,
        orElse: () => throw PrinterTransportException(
          'Characteristic $characteristicUuid not found. '
          'Check UUID or enable kPrinterDebug to see available characteristics.',
        ),
      );

      _cachedCharacteristic = characteristic;
      printerLog('Characteristic locked. Ready to print.');
    } catch (e) {
      _cachedCharacteristic = null;
      await _device?.disconnect();
      _device = null;
      if (e is PrinterTransportException) rethrow;
      throw PrinterTransportException('Bluetooth connection failed: $e');
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> sendData(Uint8List data) async {
    final characteristic = _cachedCharacteristic;
    if (characteristic == null) {
      throw const PrinterTransportException(
        'Not connected — call connect() first.',
      );
    }

    final useWithoutResponse = !characteristic.properties.write &&
        characteristic.properties.writeWithoutResponse;

    printerLog(
      'Sending ${data.length} bytes '
      '(chunkSize=$chunkSize, withoutResponse=$useWithoutResponse)...',
    );

    int offset = 0;
    while (offset < data.length) {
      final end = math.min(offset + chunkSize, data.length);
      final chunk = data.sublist(offset, end);

      try {
        await characteristic.write(
          chunk,
          withoutResponse: useWithoutResponse,
        );
      } catch (e) {
        throw PrinterTransportException(
          'Bluetooth write failed at offset $offset: $e',
        );
      }

      offset = end;

      if (offset < data.length && interChunkDelayMs > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: interChunkDelayMs),
        );
      }
    }

    printerLog('Send complete.');
  }

  void disconnect() {
    printerLog('Disconnecting.');
    _cachedCharacteristic = null;
    _device?.disconnect();
    _device = null;
  }

  static bool _isXprinter(ScanResult r) {
    final name = r.device.platformName.toLowerCase();

    return name.contains('xprinter') ||
        name.contains('xp-') ||
        name.startsWith('xp') ||
        name.contains('printer');
  }
}

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);

  @override
  String toString() => 'PrinterTransportException: $message';
}
