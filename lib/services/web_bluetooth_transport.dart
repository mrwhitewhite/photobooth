// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_interop';

// ─────────────────────────────────────────────────────────────────────────────
//  Type-safe JS interop bindings for the Web Bluetooth API
// ─────────────────────────────────────────────────────────────────────────────
//
// These `extension type` declarations map 1-to-1 with the browser's Web
// Bluetooth objects.  Every property and method is strongly typed so we never
// need to cast through `dynamic` or raw `JSAny`.
//
// Reference: https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API

/// Binding to `navigator.bluetooth.requestDevice(options)`.
///
/// This must be called from a user-gesture context (e.g. a button tap) or
/// the browser will reject the promise with a `SecurityError`.
@JS('navigator.bluetooth.requestDevice')
external JSPromise<JSObject> _jsRequestDevice(JSObject options);

/// Represents a `BluetoothDevice` returned by `requestDevice()`.
@JS()
extension type BluetoothDevice._(JSObject _) implements JSObject {
  /// Human-readable device name (e.g. "XPrinter-A1B2").
  external JSString get name;

  /// The GATT server associated with this device.
  external BluetoothRemoteGATTServer get gatt;
}

/// Represents `BluetoothRemoteGATTServer` — the gateway to services.
@JS()
extension type BluetoothRemoteGATTServer._(JSObject _) implements JSObject {
  /// Connects to the GATT server.  Resolves with a reference to self.
  external JSPromise<BluetoothRemoteGATTServer> connect();

  /// Discovers the primary service matching [serviceUuid].
  external JSPromise<BluetoothRemoteGATTService> getPrimaryService(
    JSAny serviceUuid,
  );
}

/// Represents `BluetoothRemoteGATTService`.
@JS()
extension type BluetoothRemoteGATTService._(JSObject _) implements JSObject {
  /// Discovers the characteristic matching [characteristicUuid].
  external JSPromise<BluetoothRemoteGATTCharacteristic> getCharacteristic(
    JSAny characteristicUuid,
  );
}

/// Represents `BluetoothRemoteGATTCharacteristic` — the writable endpoint.
@JS()
extension type BluetoothRemoteGATTCharacteristic._(JSObject _)
    implements JSObject {
  /// Writes [value] and waits for the device to acknowledge (flow-controlled).
  external JSPromise<JSAny?> writeValueWithResponse(JSArrayBuffer value);

  /// Writes [value] without waiting for acknowledgement (fire-and-forget).
  external JSPromise<JSAny?> writeValueWithoutResponse(JSArrayBuffer value);
}

// ─────────────────────────────────────────────────────────────────────────────
//  WebBluetoothTransport
// ─────────────────────────────────────────────────────────────────────────────

/// A self-contained BLE transport layer that knows nothing about printing,
/// images, or ESC/POS.  It handles:
///
///   1. Device discovery via the browser's BLE picker
///   2. GATT connection and characteristic caching
///   3. Chunked, flow-controlled data streaming
///
/// Usage:
/// ```dart
/// final transport = WebBluetoothTransport();
/// await transport.connect(serviceUuid: '...', characteristicUuid: '...');
/// await transport.sendData(myBytePayload);
/// transport.disconnect();
/// ```
class WebBluetoothTransport {
  // ── Tunables ─────────────────────────────────────────────────────────────

  /// Maximum bytes per BLE write packet.  Kept conservative (200 bytes) to
  /// avoid overflowing the printer's tiny BLE receive FIFO.  The BLE spec
  /// allows up to 512 bytes with negotiated MTU, but most thermal printer
  /// firmware handles 200 bytes reliably.
  final int chunkSize;

  /// Milliseconds to pause between consecutive BLE write packets.  This
  /// pacing delay lets the printer's internal buffer drain to the thermal
  /// head.  30 ms is a safe default for XPrinter models; increase to 50 ms
  /// if you observe dropped lines or garbled output.
  final int interChunkDelayMs;

  WebBluetoothTransport({
    this.chunkSize = 200,
    this.interChunkDelayMs = 30,
  });

  // ── Cached connection state ──────────────────────────────────────────────

  BluetoothRemoteGATTCharacteristic? _cachedCharacteristic;

  /// Whether a BLE characteristic is currently cached (i.e. connected).
  bool get isConnected => _cachedCharacteristic != null;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Opens the browser's BLE device picker, connects to the selected device's
  /// GATT server, discovers the specified service and characteristic, and
  /// caches the characteristic for subsequent [sendData] calls.
  ///
  /// If a characteristic is already cached, this is a no-op (returns the
  /// existing connection).  Call [disconnect] first to force a fresh picker.
  ///
  /// Throws [PrinterTransportException] on any BLE failure.
  Future<void> connect({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    if (_cachedCharacteristic != null) return;

    try {
      // ── Build requestDevice options ────────────────────────────────────
      //
      // The Web Bluetooth API expects:
      //   { filters: [{ services: [uuid] }], optionalServices: [uuid] }
      //
      // `filters.services` tells the browser to only show devices that
      // advertise the given service UUID.  `optionalServices` grants
      // permission to access the service after connection.
      final filterEntry = <String, Object>{
        'services': <String>[serviceUuid],
      };
      final options = <String, Object>{
        'filters': <Object>[filterEntry],
        'optionalServices': <String>[serviceUuid],
      }.jsify() as JSObject;

      // Show the browser's native BLE device picker.  This MUST be triggered
      // by a user gesture or the browser will reject with SecurityError.
      final device =
          await _jsRequestDevice(options).toDart as BluetoothDevice;

      // Connect to the device's GATT server.
      final server = await device.gatt.connect().toDart;

      // Discover the target service.
      final service =
          await server.getPrimaryService(serviceUuid.toJS).toDart;

      // Discover the writable characteristic within that service.
      final characteristic =
          await service.getCharacteristic(characteristicUuid.toJS).toDart;

      _cachedCharacteristic = characteristic;
    } catch (e) {
      _cachedCharacteristic = null;
      throw PrinterTransportException(
        'BLE connection failed: $e',
      );
    }
  }

  /// Sends [data] over BLE in [chunkSize]-byte packets with flow-controlled
  /// pacing.
  ///
  /// Each packet is written using `writeValueWithResponse` which waits for
  /// the device to ACK before returning.  If the device doesn't support
  /// write-with-response, falls back to `writeValueWithoutResponse`.
  ///
  /// A [interChunkDelayMs] pause is inserted between consecutive packets to
  /// prevent the printer's internal buffer from overflowing.
  ///
  /// Throws [PrinterTransportException] if not connected or if a write fails.
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

      // Convert the Dart Uint8List into a JS ArrayBuffer for the BLE API.
      final jsBuffer = chunk.buffer.toJS;

      try {
        // Prefer write-with-response: the printer ACKs each packet,
        // providing reliable flow control.
        await characteristic.writeValueWithResponse(jsBuffer).toDart;
      } catch (_) {
        // Fallback for printers that only support write-without-response.
        try {
          await characteristic.writeValueWithoutResponse(jsBuffer).toDart;
        } catch (e) {
          throw PrinterTransportException(
            'BLE write failed at offset $offset: $e',
          );
        }
      }

      offset = end;

      // Pacing delay between packets.  Skip the delay after the last packet
      // to avoid unnecessary latency.
      if (offset < data.length) {
        await Future<void>.delayed(
          Duration(milliseconds: interChunkDelayMs),
        );
      }
    }
  }

  /// Drops the cached BLE characteristic, effectively disconnecting.
  ///
  /// The next call to [connect] will show the browser's device picker again.
  /// Note: this does not call `device.gatt.disconnect()` because the Web
  /// Bluetooth spec automatically disconnects when the page navigates away,
  /// and explicitly disconnecting can cause issues with some printer firmware
  /// that expects the host to maintain the connection.
  void disconnect() {
    _cachedCharacteristic = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Exception type
// ─────────────────────────────────────────────────────────────────────────────

/// Exception thrown by [WebBluetoothTransport] when a BLE operation fails.
class PrinterTransportException implements Exception {
  final String message;
  const PrinterTransportException(this.message);

  @override
  String toString() => 'PrinterTransportException: $message';
}
