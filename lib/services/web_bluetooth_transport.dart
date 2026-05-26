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
  external JSPromise<BluetoothRemoteGATTService> getPrimaryService(
      JSAny serviceUuid);
}

@JS()
extension type BluetoothRemoteGATTService._(JSObject _) implements JSObject {
  external JSPromise<BluetoothRemoteGATTCharacteristic> getCharacteristic(
      JSAny characteristicUuid);
}

@JS()
extension type BluetoothRemoteGATTCharacteristic._(JSObject _)
    implements JSObject {
  external JSPromise<JSAny?> writeValueWithResponse(JSArrayBuffer value);
  external JSPromise<JSAny?> writeValueWithoutResponse(JSArrayBuffer value);
}

class WebBluetoothTransport {
  final int chunkSize;

  final int interChunkDelayMs;

  WebBluetoothTransport({
    this.chunkSize = 512,
    this.interChunkDelayMs = 30,
  });

  BluetoothRemoteGATTCharacteristic? _cachedCharacteristic;

  _WriteMode? _writeMode;

  bool get isConnected => _cachedCharacteristic != null;

  Future<void> connect({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (_cachedCharacteristic != null) return;

    try {
      final options = <String, Object>{
        'filters': [
          {
            'services': <String>[serviceUuid]
          }
        ],
        'optionalServices': <String>[serviceUuid],
      }.jsify() as JSObject;

      final device = await _jsRequestDevice(options).toDart as BluetoothDevice;
      final server = await device.gatt.connect().toDart;
      final service = await server.getPrimaryService(serviceUuid.toJS).toDart;
      final characteristic =
          await service.getCharacteristic(characteristicUuid.toJS).toDart;

      _cachedCharacteristic = characteristic;

      _writeMode = await _probeWriteMode(characteristic);
    } catch (e) {
      _cachedCharacteristic = null;
      _writeMode = null;
      throw PrinterTransportException('BLE connection failed: $e');
    }
  }

  Future<void> sendData(Uint8List data) async {
    final characteristic = _cachedCharacteristic;
    final mode = _writeMode;
    if (characteristic == null || mode == null) {
      throw const PrinterTransportException(
          'Not connected — call connect() first.');
    }

    int offset = 0;
    while (offset < data.length) {
      final end = math.min(offset + chunkSize, data.length);

      final chunk = Uint8List.fromList(data.sublist(offset, end));
      final jsBuffer = chunk.buffer.toJS;

      try {
        if (mode == _WriteMode.withResponse) {
          await characteristic.writeValueWithResponse(jsBuffer).toDart;
        } else {
          await characteristic.writeValueWithoutResponse(jsBuffer).toDart;
        }
      } catch (e) {
        throw PrinterTransportException(
            'BLE write failed at offset $offset: $e');
      }

      offset = end;

      if (offset < data.length) {
        await Future<void>.delayed(Duration(milliseconds: interChunkDelayMs));
      }
    }
  }

  void disconnect() {
    _cachedCharacteristic = null;
    _writeMode = null;
  }

  static Future<_WriteMode> _probeWriteMode(
    BluetoothRemoteGATTCharacteristic characteristic,
  ) async {
    final probe = Uint8List(1);
    try {
      await characteristic.writeValueWithResponse(probe.buffer.toJS).toDart;
      return _WriteMode.withResponse;
    } catch (_) {
      return _WriteMode.withoutResponse;
    }
  }
}

enum _WriteMode { withResponse, withoutResponse }

class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);
  @override
  String toString() => 'PrinterTransportException: $message';
}
