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
  // 512 bytes: safely below the BLE 512-byte ATT MTU limit while still being
  // large enough to keep throughput high. The previous 504 was fine in size
  // but the mixed write-mode fallback (see sendData) caused the printer to
  // lose track of which bytes it had ACK'd.
  final int chunkSize;

  // 30 ms gives the XP-N160II's BLE stack time to flush the write buffer
  // before the next chunk arrives. Lower values (< 20 ms) can cause the
  // printer to silently drop chunks, producing truncated or banded output.
  final int interChunkDelayMs;

  WebBluetoothTransport({
    this.chunkSize = 512,
    this.interChunkDelayMs = 30,
  });

  BluetoothRemoteGATTCharacteristic? _cachedCharacteristic;
  // Track which write mode the characteristic actually supports so we never
  // mix modes mid-transfer (mixing caused sync loss and banding in the old code).
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
      // Probe which write mode works by sending an empty buffer.
      // We do this once at connect time so every subsequent chunk uses
      // the same mode — no mid-transfer switching.
      _writeMode = await _probeWriteMode(characteristic);
    } catch (e) {
      _cachedCharacteristic = null;
      _writeMode = null;
      throw PrinterTransportException('BLE connection failed: $e');
    }
  }

  // Sends [data] in fixed-size chunks, always using the same write mode.
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
      // sublist gives a view-backed copy — we need an isolated buffer so the
      // JS ArrayBuffer is not shared with the next iteration.
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

  // Probe once with a 1-byte payload to learn which write mode the
  // characteristic supports. Prefers writeValueWithResponse (reliable,
  // flow-controlled); falls back to writeValueWithoutResponse only if the
  // GATT properties don't include WRITE (e.g. WRITE_WITHOUT_RESPONSE only).
  static Future<_WriteMode> _probeWriteMode(
    BluetoothRemoteGATTCharacteristic characteristic,
  ) async {
    final probe = Uint8List(1); // single zero byte — harmless to the printer
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
