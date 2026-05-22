import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;
import '../models/photo_models.dart';

/// Canvas-based image compositing engine.
/// Renders captured photos into template slots, then overlays the transparent
/// template PNG on top so its opaque frame/border covers photo edges.
class ImageProcessor {
  // Offscreen canvas dimensions (high-res output)
  static const double _outputW = 2048.0;
  static const double _outputH = 2048.0;

  /// Composite [photos] using [layout]'s template PNG and slot definitions.
  /// Returns PNG bytes of the final merged image.
  static Future<Uint8List> composite({
    required List<Uint8List> photos,
    required PhotoLayout layout,
  }) async {
    // 1. Load template PNG from Flutter assets → HTMLImageElement
    final templateImg = await _loadAssetImage(layout.templateAsset);
    final double templateW = templateImg.naturalWidth.toDouble();
    final double templateH = templateImg.naturalHeight.toDouble();

    // Use template's natural dimensions as canvas size for pixel-perfect output
    final double canvasW = templateW > 0 ? templateW : _outputW;
    final double canvasH = templateH > 0 ? templateH : _outputH;

    // 2. Create offscreen canvas
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = canvasW.toInt();
    canvas.height = canvasH.toInt();
    final ctx = canvas.context2D;

    // 3. Fill background (white — template transparent areas will show this)
    ctx.fillStyle = '#FFFFFF'.toJS;
    ctx.fillRect(0, 0, canvasW, canvasH);

    // 4. Detect the template's transparent photo slots from its alpha channel.
    final templateCanvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    templateCanvas.width = canvasW.toInt();
    templateCanvas.height = canvasH.toInt();
    final templateCtx = templateCanvas.context2D;
    templateCtx.drawImage(templateImg, 0, 0, canvasW, canvasH);
    final detectedSlots = _detectTemplateSlots(
        templateCtx, canvasW.toInt(), canvasH.toInt(), layout.photoCount);
    final slots = detectedSlots.isNotEmpty ? detectedSlots : layout.slots;

    for (int i = 0; i < photos.length && i < slots.length; i++) {
      final slot = slots[i];
      final photoImg = await _loadBytesImage(photos[i]);

      final double slotX = slot.x * canvasW;
      final double slotY = slot.y * canvasH;
      final double slotW = slot.w * canvasW;
      final double slotH = slot.h * canvasH;

      // Use cover-fit for layouts that need the photo to match the template
      // shape by cropping instead of leaving blank edges.
      final fit = _shouldCoverFit(layout)
          ? _coverFit(
              photoImg.naturalWidth.toDouble(),
              photoImg.naturalHeight.toDouble(),
              slotW,
              slotH,
            )
          : _containFit(
              photoImg.naturalWidth.toDouble(),
              photoImg.naturalHeight.toDouble(),
              slotW,
              slotH,
            );

      ctx.save();
      // Clip to slot rectangle so photo doesn't bleed outside
      ctx.beginPath();
      ctx.rect(slotX, slotY, slotW, slotH);
      ctx.clip();

      ctx.drawImage(
        photoImg,
        0,
        0,
        photoImg.naturalWidth.toDouble(),
        photoImg.naturalHeight.toDouble(), // source
        slotX + fit.offsetX,
        slotY + fit.offsetY,
        fit.width,
        fit.height,
      );
      ctx.restore();
    }

    // 5. Draw template PNG on top — transparent holes reveal photos below
    ctx.drawImage(templateImg, 0, 0, canvasW, canvasH);

    // 6. Read canvas as PNG bytes
    return _canvasToBytes(canvas);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Load a Flutter asset by path into an HTMLImageElement.
  static Future<web.HTMLImageElement> _loadAssetImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List();
    return _loadBytesImage(bytes);
  }

  /// Convert raw PNG/JPEG bytes into an HTMLImageElement via Blob URL.
  /// Detects PNG vs JPEG by magic bytes so the browser gets the correct MIME type.
  static Future<web.HTMLImageElement> _loadBytesImage(Uint8List bytes) async {
    // Detect format: PNG starts with 0x89504E47, JPEG with 0xFFD8FF
    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final mimeType = isPng ? 'image/png' : 'image/jpeg';
    final blob =
        web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final img = web.HTMLImageElement();
    img.src = url;

    final completer = Completer<web.HTMLImageElement>();
    img.onload = (web.Event _) {
      web.URL.revokeObjectURL(url);
      completer.complete(img);
    }.toJS;
    img.onerror = (web.Event _) {
      web.URL.revokeObjectURL(url);
      completer.completeError('Failed to load image');
    }.toJS;

    return completer.future;
  }

  /// Compute destination rectangle for a contained image fit inside the slot.
  /// This preserves the full photo and centers it, leaving blank edges if needed.
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
    web.CanvasRenderingContext2D ctx,
    int width,
    int height,
    int expectedCount,
  ) {
    final imageData = ctx.getImageData(0, 0, width, height);
    final pixels = imageData.data.toDart;

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
      // Pick the largest visible slots first, then normalize order.
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

  /// Render canvas to PNG bytes via toBlob → FileReader.
  static Future<Uint8List> _canvasToBytes(web.HTMLCanvasElement canvas) {
    final completer = Completer<Uint8List>();
    canvas.toBlob(
      (web.Blob blob) {
        final reader = web.FileReader();
        reader.readAsArrayBuffer(blob);
        reader.onloadend = (web.Event _) {
          final buffer = (reader.result as JSArrayBuffer).toDart;
          completer.complete(buffer.asUint8List());
        }.toJS;
      }.toJS,
      'image/png',
    );
    return completer.future;
  }

  /// Trigger a browser file download of [bytes] as [filename].
  static void downloadFile(Uint8List bytes, String filename) {
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement;
    a.href = url;
    a.download = filename;
    web.document.body!.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
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
