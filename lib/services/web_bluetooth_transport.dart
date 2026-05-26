import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class WebBluetoothTransport {
  final int chunkSize;
  final int interChunkDelayMs;

  WebBluetoothTransport({
    this.chunkSize = 200,
    this.interChunkDelayMs = 30,
  });

  BluetoothConnection? _connection;

  bool get isConnected => _connection?.isConnected == true;

  Future<void> connectToDeviceId({
    required String deviceId,
    String? serviceUuid,
    String? characteristicUuid,
  }) async {
    if (isConnected) return;

    try {
      _connection = await BluetoothConnection.toAddress(deviceId)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      _connection = null;
      throw PrinterTransportException(
        'Classic Bluetooth connection to $deviceId failed: $e',
      );
    }
  }

  Future<void> connect({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    throw const PrinterTransportException(
      'connect() by service UUID is not supported for Classic Bluetooth. '
      'Use connectToDeviceId() with the device MAC address.',
    );
  }

  Future<void> sendData(Uint8List data) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw const PrinterTransportException(
        'Not connected — call connectToDeviceId() first.',
      );
    }

    int offset = 0;
    while (offset < data.length) {
      final end = math.min(offset + chunkSize, data.length);
      final chunk = data.sublist(offset, end);

      try {
        conn.output.add(chunk);
        await conn.output.allSent;
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
  }

  void disconnect() {
    _connection?.close();
    _connection = null;
  }
}

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);

  @override
  String toString() => 'PrinterTransportException: $message';
}
