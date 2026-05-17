import 'dart:async';
import 'dart:js_interop';
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
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = canvasW.toInt();
    canvas.height = canvasH.toInt();
    final ctx = canvas.context2D;

    // 3. Fill background (white — template transparent areas will show this)
    ctx.fillStyle = '#FFFFFF'.toJS;
    ctx.fillRect(0, 0, canvasW, canvasH);

    // 4. Draw each captured photo into its corresponding slot
    final slots = layout.slots;
    for (int i = 0; i < photos.length && i < slots.length; i++) {
      final slot = slots[i];
      final photoImg = await _loadBytesImage(photos[i]);

      final double slotX = slot.x * canvasW;
      final double slotY = slot.y * canvasH;
      final double slotW = slot.w * canvasW;
      final double slotH = slot.h * canvasH;

      // Cover-fit: crop photo to fill slot without distortion
      final src = _coverCrop(
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
        src.left, src.top, src.width, src.height, // source
        slotX, slotY, slotW, slotH,               // destination
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
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47;
    final mimeType = isPng ? 'image/png' : 'image/jpeg';
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
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

  /// Compute cover-crop source rect so the image fills (dstW × dstH) without
  /// distortion, cropping the excess from the center.
  static ({double left, double top, double width, double height}) _coverCrop(
    double srcW, double srcH, double dstW, double dstH) {
    final srcAspect = srcW / srcH;
    final dstAspect = dstW / dstH;
    double sw, sh, sx, sy;
    if (srcAspect > dstAspect) {
      // Source is wider — crop sides
      sh = srcH;
      sw = sh * dstAspect;
      sx = (srcW - sw) / 2;
      sy = 0;
    } else {
      // Source is taller — crop top/bottom
      sw = srcW;
      sh = sw / dstAspect;
      sx = 0;
      sy = (srcH - sh) / 2;
    }
    return (left: sx, top: sy, width: sw, height: sh);
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
