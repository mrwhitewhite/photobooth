import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WebBluetoothTransport {
  final int chunkSize;
  final int interChunkDelayMs;

  WebBluetoothTransport({
    this.chunkSize = 200,
    this.interChunkDelayMs = 30,
  });

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cachedCharacteristic;

  bool get isConnected => _cachedCharacteristic != null;

  Future<void> connect({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (_cachedCharacteristic != null) return;

    final serviceGuid = Guid(serviceUuid);
    final characteristicGuid = Guid(characteristicUuid);

    try {
      await FlutterBluePlus.startScan(
        withServices: [serviceGuid],
        timeout: const Duration(seconds: 10),
      );

      final scanResults = await FlutterBluePlus.scanResults
          .timeout(const Duration(seconds: 12))
          .firstWhere((results) => results.isNotEmpty);

      await FlutterBluePlus.stopScan();

      final device = scanResults.first.device;
      _device = device;

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == serviceGuid,
        orElse: () {
          throw const PrinterTransportException(
            'Bluetooth service not found on device.',
          );
        },
      );

      final characteristic = service.characteristics.firstWhere(
        (c) => c.uuid == characteristicGuid,
        orElse: () {
          throw const PrinterTransportException(
            'Bluetooth characteristic not found on device.',
          );
        },
      );

      _cachedCharacteristic = characteristic;
    } catch (e) {
      _cachedCharacteristic = null;
      await _device?.disconnect();
      _device = null;
      throw PrinterTransportException(
        'Bluetooth connection failed: $e',
      );
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  
  
  Future<void> connectToDeviceId({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (_cachedCharacteristic != null) return;

    final serviceGuid = Guid(serviceUuid);
    final characteristicGuid = Guid(characteristicUuid);

    try {
      final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
      _device = device;

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == serviceGuid,
        orElse: () {
          throw const PrinterTransportException(
            'Bluetooth service not found on saved device.',
          );
        },
      );

      final characteristic = service.characteristics.firstWhere(
        (c) => c.uuid == characteristicGuid,
        orElse: () {
          throw const PrinterTransportException(
            'Bluetooth characteristic not found on saved device.',
          );
        },
      );

      _cachedCharacteristic = characteristic;
    } catch (e) {
      _cachedCharacteristic = null;
      await _device?.disconnect();
      _device = null;
      throw PrinterTransportException(
        'Bluetooth connection to saved device failed: $e',
      );
    }
  }

  Future<void> sendData(Uint8List data) async {
    final characteristic = _cachedCharacteristic;
    if (characteristic == null) {
      throw const PrinterTransportException(
        'Not connected — call connect() first.',
      );
    }

    int offset = 0;
    while (offset < data.length) {
      final end = math.min(offset + chunkSize, data.length);
      final chunk = data.sublist(offset, end);

      try {
        await characteristic.write(
          chunk,
          withoutResponse: false,
        );
      } catch (e) {
        throw PrinterTransportException(
          'Bluetooth write failed at offset $offset: $e',
        );
      }

      offset = end;

      if (offset < data.length) {
        await Future<void>.delayed(
          Duration(milliseconds: interChunkDelayMs),
        );
      }
    }
  }

  void disconnect() {
    _cachedCharacteristic = null;
    _device?.disconnect();
    _device = null;
  }
}

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);

  @override
  String toString() => 'PrinterTransportException: $message';
}
