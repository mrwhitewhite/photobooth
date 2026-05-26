import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

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

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, canvasW, canvasH),
    );

    // White background.
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, canvasW, canvasH),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    // Detect template slots from transparent regions.
    final detectedSlots = await _detectTemplateSlots(
      templateImg,
      canvasW.toInt(),
      canvasH.toInt(),
      layout.photoCount,
    );
    final slots = detectedSlots.isNotEmpty ? detectedSlots : layout.slots;

    // Draw each photo into its slot.
    for (int i = 0; i < photos.length && i < slots.length; i++) {
      final slot = slots[i];
      final photoImg = await _decodeImage(photos[i]);

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

      canvas.save();
      canvas.clipRect(ui.Rect.fromLTWH(slotX, slotY, slotW, slotH));

      canvas.drawImageRect(
        photoImg,
        ui.Rect.fromLTWH(
          0,
          0,
          photoImg.width.toDouble(),
          photoImg.height.toDouble(),
        ),
        ui.Rect.fromLTWH(
          slotX + fit.offsetX,
          slotY + fit.offsetY,
          fit.width,
          fit.height,
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
      photoImg.dispose();
    }

    // Draw template overlay on top.
    canvas.drawImageRect(
      templateImg,
      ui.Rect.fromLTWH(
        0,
        0,
        templateImg.width.toDouble(),
        templateImg.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, canvasW, canvasH),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    templateImg.dispose();

    // Encode to PNG.
    final picture = recorder.endRecording();
    final composited =
        await picture.toImage(canvasW.toInt(), canvasH.toInt());
    final ByteData? pngData =
        await composited.toByteData(format: ui.ImageByteFormat.png);
    composited.dispose();
    picture.dispose();

    if (pngData == null) {
      throw StateError('Failed to encode composite image as PNG.');
    }

    return pngData.buffer.asUint8List();
  }

  /// Loads an image from the asset bundle.
  static Future<ui.Image> _loadAssetImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List();
    return _decodeImage(bytes);
  }

  /// Decodes raw image bytes into a [ui.Image].
  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
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

  /// Detects transparent slot regions in the template image.
  static Future<List<LayoutSlot>> _detectTemplateSlots(
    ui.Image templateImg,
    int width,
    int height,
    int expectedCount,
  ) async {
    // Scale the template to the target dimensions and read pixel data.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawImageRect(
      templateImg,
      ui.Rect.fromLTWH(
        0,
        0,
        templateImg.width.toDouble(),
        templateImg.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final ByteData? pixelData =
        await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    rendered.dispose();
    picture.dispose();

    if (pixelData == null) return const [];

    final pixels = pixelData.buffer.asUint8List();

    final List<List<_Segment>> rowSegments =
        List.generate(height, (_) => []);
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
      final matched =
          List<bool>.filled(active.length, false, growable: true);

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

  /// Saves image bytes to the device gallery.
  static Future<void> saveToGallery(Uint8List bytes, String name) async {
    final result = await ImageGallerySaverPlus.saveImage(
      bytes,
      name: name,
      quality: 100,
    );
    if (result == null || result['isSuccess'] != true) {
      throw Exception('Failed to save image to gallery');
    }
  }
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
