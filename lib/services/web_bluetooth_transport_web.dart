// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_interop';

@JS('navigator.bluetooth.requestDevice')
external JSPromise<JSObject> _jsRequestDevice(JSObject options);

@JS()
extension type BluetoothDevice._(JSObject _) implements JSObject {
  external JSString get name;
  external BluetoothRemoteGATTServer get gatt;
}

@JS()
extension type BluetoothRemoteGATTServer._(JSObject _) implements JSObject {
  external JSPromise<BluetoothRemoteGATTServer> connect();
  external JSPromise<BluetoothRemoteGATTService> getPrimaryService(JSAny serviceUuid);
}

@JS()
extension type BluetoothRemoteGATTService._(JSObject _) implements JSObject {
  external JSPromise<BluetoothRemoteGATTCharacteristic> getCharacteristic(JSAny characteristicUuid);
}

@JS()
extension type BluetoothRemoteGATTCharacteristic._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> writeValueWithResponse(JSArrayBuffer value);
  external JSPromise<JSAny?> writeValueWithoutResponse(JSArrayBuffer value);
}

class WebBluetoothTransport {
  final int chunkSize;
  final int interChunkDelayMs;

  WebBluetoothTransport({this.chunkSize = 512, this.interChunkDelayMs = 30});

  BluetoothRemoteGATTCharacteristic? _cachedCharacteristic;
  _WriteMode? _writeMode;

  bool get isConnected => _cachedCharacteristic != null;

  Future<void> connect({required String serviceUuid, required String characteristicUuid}) async {
    // original web implementation...
    throw UnimplementedError();
  }

  Future<void> sendData(Uint8List data) async {
    throw UnimplementedError();
  }

  void disconnect() {
    _cachedCharacteristic = null;
    _writeMode = null;
  }
}

enum _WriteMode { withResponse, withoutResponse }

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);
  @override
  String toString() => 'PrinterTransportException: $message';
}
