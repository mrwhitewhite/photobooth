import 'dart:typed_data';
import 'dart:js_interop';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:web/web.dart' as web;

import 'web_bluetooth_transport.dart';

class PrinterService {
  static const String serviceUuid = '000018f0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid =
      '00002af1-0000-1000-8000-00805f9b34fb';

  static const int _paperWidthPx = 576;

  static final WebBluetoothTransport _transport = WebBluetoothTransport(
    chunkSize: 512,
    interChunkDelayMs: 30,
  );

  static Future<void> printReceipt(
    Uint8List imageBytes, {
    int paperWidthPx = _paperWidthPx,
  }) async {
    try {
      await _transport.connect(
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      );

      final escBytes = await _buildEscPosBytes(imageBytes, paperWidthPx);

      await _transport.sendData(Uint8List.fromList(escBytes));
    } on PrinterTransportException catch (e) {
      throw PrinterException(e.message);
    } catch (e) {
      throw PrinterException(e.toString());
    }
  }

  static Future<List<int>> _buildEscPosBytes(
    Uint8List pngBytes,
    int paperWidthPx,
  ) async {
    final decoded = await _decodePngViaCanvas(pngBytes, paperWidthPx);

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);

    final List<int> bytes = [];
    bytes.addAll(generator.reset());
    bytes.addAll(generator.imageRaster(decoded, align: PosAlign.center));
    bytes.addAll(generator.feed(4));
    bytes.addAll(generator.cut());
    return bytes;
  }

  static Future<img.Image> _decodePngViaCanvas(
    Uint8List pngBytes,
    int targetWidth,
  ) async {
    final blob = web.Blob(
      [pngBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    final htmlImg = web.HTMLImageElement();
    htmlImg.src = url;
    await htmlImg.onLoad.first;
    web.URL.revokeObjectURL(url);

    final srcW = htmlImg.naturalWidth;
    final srcH = htmlImg.naturalHeight;
    final targetH = (srcH * targetWidth / srcW).round();

    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = targetWidth;
    canvas.height = targetH;
    final ctx = canvas.context2D;
    ctx.drawImage(htmlImg, 0, 0, targetWidth, targetH);

    final imageData = ctx.getImageData(0, 0, targetWidth, targetH);
    final rgba = imageData.data.toDart;

    final image = img.Image.fromBytes(
      width: targetWidth,
      height: targetH,
      bytes: Uint8List.fromList(rgba).buffer,
      numChannels: 4,
    );

    return image;
  }

  static void disconnect() {
    _transport.disconnect();
  }
}

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);
  @override
  String toString() => 'PrinterException: $message';
}
