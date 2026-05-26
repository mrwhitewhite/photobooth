import 'dart:math' as math;
import 'dart:typed_data';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ClassicBtTransport {
  final int chunkSize;

  final int interChunkDelayMs;

  ClassicBtTransport({
    this.chunkSize = 512,
    this.interChunkDelayMs = 0,
  });

  String? _connectedMac;

  bool get isConnected => _connectedMac != null;

  Future<void> connectToDeviceId({
    required String deviceId,
    String serviceUuid = '',
    String characteristicUuid = '',
  }) async {
    if (_connectedMac == deviceId) return;

    if (_connectedMac != null) {
      await PrintBluetoothThermal.disconnect;
      _connectedMac = null;
    }

    try {
      final bool connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: deviceId,
      );

      if (!connected) {
        throw PrinterTransportException(
          'Could not connect to $deviceId. '
          'Ensure the printer is on, in range, and paired.',
        );
      }

      _connectedMac = deviceId;
    } catch (e) {
      _connectedMac = null;
      if (e is PrinterTransportException) rethrow;
      throw PrinterTransportException('Bluetooth connection failed: $e');
    }
  }

  Future<void> sendData(Uint8List data) async {
    if (_connectedMac == null) {
      throw const PrinterTransportException(
        'Not connected — call connectToDeviceId() first.',
      );
    }

    int offset = 0;
    while (offset < data.length) {
      final end = math.min(offset + chunkSize, data.length);
      final chunk = data.sublist(offset, end);

      try {
        final bool ok = await PrintBluetoothThermal.writeBytes(chunk);
        if (!ok) {
          throw PrinterTransportException(
            'Write returned false at offset $offset. '
            'Printer may have disconnected.',
          );
        }
      } catch (e) {
        if (e is PrinterTransportException) rethrow;
        throw PrinterTransportException(
          'Bluetooth write failed at offset $offset: $e',
        );
      }

      offset = end;

      if (interChunkDelayMs > 0 && offset < data.length) {
        await Future<void>.delayed(Duration(milliseconds: interChunkDelayMs));
      }
    }
  }

  Future<void> disconnect() async {
    if (_connectedMac != null) {
      await PrintBluetoothThermal.disconnect;
      _connectedMac = null;
    }
  }
}

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);

  @override
  String toString() => 'PrinterTransportException: $message';
}
