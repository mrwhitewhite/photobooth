import 'dart:async';
import 'dart:typed_data';

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);
  @override
  String toString() => 'PrinterTransportException: $message';
}

class WebBluetoothTransport {
  final int chunkSize;
  final int interChunkDelayMs;

  WebBluetoothTransport({this.chunkSize = 512, this.interChunkDelayMs = 30});

  Future<void> connect({required String serviceUuid, required String characteristicUuid}) async {
    throw const PrinterTransportException('Web Bluetooth not supported on this platform.');
  }

  Future<void> sendData(Uint8List data) async {
    throw const PrinterTransportException('Web Bluetooth not supported on this platform.');
  }

  void disconnect() {}

  bool get isConnected => false;
}
