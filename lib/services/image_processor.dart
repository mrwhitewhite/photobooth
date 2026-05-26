import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    final templateImg = await _loadAssetImage(layout.templateAsset);
    final double templateW = templateImg.width.toDouble();
    final double templateH = templateImg.height.toDouble();

    final double canvasW = templateW > 0 ? templateW : _outputW;
    final double canvasH = templateH > 0 ? templateH : _outputH;

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
      interpolation: img.Interpolation.cubic,
    );
    final detectedSlots = _detectTemplateSlots(
      templateCanvas,
      canvas.width,
      canvas.height,
      layout.photoCount,
    );
    final slots = detectedSlots.isNotEmpty ? detectedSlots : layout.slots;

    for (int i = 0; i < photos.length && i < slots.length; i++) {
      final slot = slots[i];
      final photoImg = await _loadBytesImage(photos[i]);

      final double slotX = slot.x * canvasW;
      final double slotY = slot.y * canvasH;
      final double slotW = slot.w * canvasW;
      final double slotH = slot.h * canvasH;

      final fit = _shouldCoverFit(layout)
          ? _coverFit(
              photoImg.width.toDouble(),
              photoImg.height.toDouble(),
              slotW,
              slotH,
            )
          : _containFit(
              photoImg.width.toDouble(),
              photoImg.height.toDouble(),
              slotW,
              slotH,
            );

      final resized = img.copyResize(
        photoImg,
        width: fit.width.round(),
        height: fit.height.round(),
        interpolation: img.Interpolation.cubic,
      );

      final slotCanvas = img.Image(
        width: slotW.round(),
        height: slotH.round(),
        numChannels: 4,
      );
      img.fill(slotCanvas, color: img.ColorUint8.rgba(0, 0, 0, 0));
      img.compositeImage(
        slotCanvas,
        resized,
        dstX: fit.offsetX.round(),
        dstY: fit.offsetY.round(),
        blend: img.BlendMode.alpha,
      );

      img.compositeImage(
        canvas,
        slotCanvas,
        dstX: slotX.round(),
        dstY: slotY.round(),
        blend: img.BlendMode.alpha,
      );
    }

    img.compositeImage(
      canvas,
      templateCanvas,
      dstX: 0,
      dstY: 0,
      blend: img.BlendMode.alpha,
    );

    return Uint8List.fromList(img.encodePng(canvas));
  }

  static Future<img.Image> _loadAssetImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List();
    return _loadBytesImage(bytes);
  }

  static Future<img.Image> _loadBytesImage(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ImageProcessorException('Failed to decode image bytes.');
    }
    return decoded;
  }

  static _FitResult _containFit(
    double srcW,
    double srcH,
    double dstW,
    double dstH,
  ) {
    final srcAspect = srcW / srcH;
    final dstAspect = dstW / dstH;
    double width, height;
    if (srcAspect > dstAspect) {
      width = dstW;
      height = dstW / srcAspect;
    } else {
      height = dstH;
      width = dstH * srcAspect;
    }
    final offsetX = (dstW - width) / 2;
    final offsetY = (dstH - height) / 2;
    return _FitResult(
      offsetX: offsetX,
      offsetY: offsetY,
      width: width,
      height: height,
    );
  }

  static _FitResult _coverFit(
    double srcW,
    double srcH,
    double dstW,
    double dstH,
  ) {
    final srcAspect = srcW / srcH;
    final dstAspect = dstW / dstH;
    double width, height;
    if (srcAspect > dstAspect) {
      height = dstH;
      width = dstH * srcAspect;
    } else {
      width = dstW;
      height = dstW / srcAspect;
    }
    final offsetX = (dstW - width) / 2;
    final offsetY = (dstH - height) / 2;
    return _FitResult(
      offsetX: offsetX,
      offsetY: offsetY,
      width: width,
      height: height,
    );
  }

  static bool _shouldCoverFit(PhotoLayout layout) {
    return layout == PhotoLayout.layout2x2 || layout == PhotoLayout.layout3x1;
  }

  static List<LayoutSlot> _detectTemplateSlots(
    img.Image template,
    int width,
    int height,
    int expectedCount,
  ) {
    final normalized = img.Image.from(template, numChannels: 4);
    final pixels = normalized.getBytes();

    final List<List<_Segment>> rowSegments = List.generate(height, (_) => []);
    for (var y = 0; y < height; y++) {
      var x = 0;
      while (x < width) {
        final alpha = pixels[(y * width + x) * 4 + 3];
        if (alpha == 0) {
          final start = x;
          do {
            x++;
          } while (x < width && pixels[(y * width + x) * 4 + 3] == 0);
          rowSegments[y].add(_Segment(start, x - 1));
        } else {
          x++;
        }
      }
    }

    final List<_TransparentBox> active = [];
    final List<_TransparentBox> boxes = [];

    for (var y = 0; y < height; y++) {
      final segments = rowSegments[y];
      final matched = List<bool>.filled(active.length, false, growable: true);

      for (final segment in segments) {
        var matchedBox = false;
        for (var i = 0; i < active.length; i++) {
          final box = active[i];
          if (segment.start <= box.xMax && segment.end >= box.xMin) {
            box.xMin = min(box.xMin, segment.start);
            box.xMax = max(box.xMax, segment.end);
            box.yMax = y;
            matched[i] = true;
            matchedBox = true;
            break;
          }
        }
        if (!matchedBox) {
          active.add(_TransparentBox(segment.start, segment.end, y, y));
          matched.add(true);
        }
      }

      for (var i = active.length - 1; i >= 0; i--) {
        if (!matched[i]) {
          boxes.add(active.removeAt(i));
          matched.removeAt(i);
        }
      }
    }

    boxes.addAll(active);

    final slotBoxes = boxes.where((box) {
      final widthFrac = (box.xMax - box.xMin + 1) / width;
      final heightFrac = (box.yMax - box.yMin + 1) / height;
      return box.area > max(1000, width * height * 0.0001) &&
          widthFrac > 0.02 &&
          heightFrac > 0.02;
    }).toList();

    if (slotBoxes.length < expectedCount) {
      return const [];
    }

    slotBoxes.sort((a, b) {
      final sizeCompare = b.area.compareTo(a.area);
      if (sizeCompare != 0) return sizeCompare;
      final rowCompare = a.yMin.compareTo(b.yMin);
      return rowCompare != 0 ? rowCompare : a.xMin.compareTo(b.xMin);
    });

    final selected = slotBoxes.take(expectedCount).toList();
    selected.sort((a, b) {
      final rowCompare = a.yMin.compareTo(b.yMin);
      return rowCompare != 0 ? rowCompare : a.xMin.compareTo(b.xMin);
    });

    return selected.map((box) {
      return LayoutSlot(
        box.xMin / width,
        box.yMin / height,
        (box.xMax - box.xMin + 1) / width,
        (box.yMax - box.yMin + 1) / height,
      );
    }).toList();
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

class _FitResult {
  final double offsetX;
  final double offsetY;
  final double width;
  final double height;

  const _FitResult({
    required this.offsetX,
    required this.offsetY,
    required this.width,
    required this.height,
  });
}

class _Segment {
  int start;
  int end;
  _Segment(this.start, this.end);
}

class _TransparentBox {
  int xMin;
  int xMax;
  int yMin;
  int yMax;

  _TransparentBox(this.xMin, this.xMax, this.yMin, this.yMax);

  int get area => (xMax - xMin + 1) * (yMax - yMin + 1);
}
