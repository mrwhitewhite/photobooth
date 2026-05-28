import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/photo_models.dart';

class ImageProcessor {
  static const double _outputW = 2048.0;
  static const double _outputH = 2048.0;

  static Future<Uint8List> composite({
    required List<Uint8List> photos,
    required PhotoLayout layout,
  }) async {
    final templateData = await rootBundle.load(layout.templateAsset);
    return compute(_compositeInIsolate, {
      'photos': photos
          .map((bytes) => TransferableTypedData.fromList([bytes]))
          .toList(),
      'layoutIndex': layout.index,
      'templateBytes': TransferableTypedData.fromList(
        [templateData.buffer.asUint8List()],
      ),
    });
  }

  static Future<Uint8List> _compositeWithTemplate({
    required List<Uint8List> photos,
    required PhotoLayout layout,
    required Uint8List templateBytes,
  }) async {
    final templateImg = await _loadBytesImage(templateBytes);
    final double templateW = templateImg.width.toDouble();
    final double templateH = templateImg.height.toDouble();

    double canvasW = _outputW;
    double canvasH = _outputH;
    if (templateW > 0 && templateH > 0) {
      final scale = min(1.0, min(_outputW / templateW, _outputH / templateH));
      canvasW = templateW * scale;
      canvasH = templateH * scale;
    }

    final canvas = img.Image(
      width: canvasW.toInt(),
      height: canvasH.toInt(),
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorUint8.rgba(255, 255, 255, 255));

    final templateCanvas = img.copyResize(
      templateImg,
      width: canvas.width,
      height: canvas.height,
      interpolation: img.Interpolation.linear,
    );

    img.compositeImage(
      canvas,
      templateCanvas,
      dstX: 0,
      dstY: 0,
      blend: img.BlendMode.alpha,
    );

    final slots = layout.slots;

    for (int i = 0; i < photos.length && i < slots.length; i++) {
      final slot = slots[i];
      final photoImg = await _loadBytesImage(photos[i]);

      final double slotX = slot.x * canvasW;
      final double slotY = slot.y * canvasH;
      final double slotW = slot.w * canvasW;
      final double slotH = slot.h * canvasH;

      final double srcAspect = photoImg.width / photoImg.height;
      final double dstAspect = slotW / slotH;

      int cropX = 0, cropY = 0;
      int cropW = photoImg.width, cropH = photoImg.height;

      if (srcAspect > dstAspect) {
        cropH = photoImg.height;
        cropW = (cropH * dstAspect).round().clamp(1, photoImg.width);
        cropX = ((photoImg.width - cropW) / 2).round();
      } else {
        cropW = photoImg.width;
        cropH = (cropW / dstAspect).round().clamp(1, photoImg.height);
        cropY = ((photoImg.height - cropH) / 2).round();
      }

      final cropped = img.copyCrop(
        photoImg,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      final resized = img.copyResize(
        cropped,
        width: slotW.round(),
        height: slotH.round(),
        interpolation: img.Interpolation.linear,
      );

      img.compositeImage(
        canvas,
        resized,
        dstX: slotX.round(),
        dstY: slotY.round(),
        blend: img.BlendMode.alpha,
      );
    }

    return Uint8List.fromList(img.encodePng(canvas));
  }

  static Future<img.Image> _loadBytesImage(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ImageProcessorException('Failed to decode image bytes.');
    }
    return decoded;
  }

  static Future<void> downloadFile(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)]);
  }
}

class ImageProcessorException implements Exception {
  final String message;
  const ImageProcessorException(this.message);

  @override
  String toString() => 'ImageProcessorException: $message';
}

Future<Uint8List> _compositeInIsolate(Map<String, dynamic> args) async {
  final photos = (args['photos'] as List)
      .cast<TransferableTypedData>()
      .map((data) => data.materialize().asUint8List())
      .toList();
  final layoutIndex = args['layoutIndex'] as int;
  final templateBytes = (args['templateBytes'] as TransferableTypedData)
      .materialize()
      .asUint8List();

  final layout = PhotoLayout.values[layoutIndex];
  return ImageProcessor._compositeWithTemplate(
    photos: photos,
    layout: layout,
    templateBytes: templateBytes,
  );
}
