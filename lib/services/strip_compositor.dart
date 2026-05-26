import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

class StripCompositor {
  static const double _stripW = 1200.0;
  static const double _stripH = 1800.0;
  static const double _padding = 20.0;
  static const double _borderRadius = 8.0;

  /// Creates a photo strip image from the given [photos].
  ///
  /// Lays out photos vertically on a 1200×1800 dark canvas with padding,
  /// rounded corners, cover-fit cropping, and a branded footer label.
  /// Returns the composited image as PNG bytes.
  static Future<Uint8List> generateStrip(List<Uint8List> photos) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      const ui.Rect.fromLTWH(0, 0, _stripW, _stripH),
    );

    // Dark background fill.
    final bgPaint = ui.Paint()..color = const ui.Color(0xFF1A1208);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, _stripW, _stripH), bgPaint);

    final int count = photos.length;
    final double slotH = (_stripH - _padding * (count + 1)) / count;
    const double slotW = _stripW - _padding * 2;

    for (int i = 0; i < count; i++) {
      final double y = _padding + i * (slotH + _padding);
      const double x = _padding;

      final ui.Image image = await _decodeImage(photos[i]);

      // Compute cover-fit source rect (center crop to match slot aspect ratio).
      final double srcAspect = image.width / image.height;
      final double dstAspect = slotW / slotH;

      double sx, sy, sw, sh;
      if (srcAspect > dstAspect) {
        sh = image.height.toDouble();
        sw = sh * dstAspect;
        sx = (image.width - sw) / 2;
        sy = 0;
      } else {
        sw = image.width.toDouble();
        sh = sw / dstAspect;
        sx = 0;
        sy = (image.height - sh) / 2;
      }

      final srcRect = ui.Rect.fromLTWH(sx, sy, sw, sh);
      final dstRect = ui.Rect.fromLTWH(x, y, slotW, slotH);

      // Clip to a rounded rectangle, draw the image, then restore.
      canvas.save();
      canvas.clipRRect(
        ui.RRect.fromRectAndRadius(dstRect, const ui.Radius.circular(_borderRadius)),
      );
      canvas.drawImageRect(image, srcRect, dstRect, ui.Paint());
      canvas.restore();

      image.dispose();
    }

    // Footer branding text.
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: 24,
      fontFamily: 'Playfair Display',
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0x80E8C4A0),
      ))
      ..addText('✦ SnapBooth ✦');
    final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: _stripW));

    // Position the text so its baseline sits at y = _stripH - 40.
    final double textY = _stripH - 40 - paragraph.height + paragraph.alphabeticBaseline;
    canvas.drawParagraph(paragraph, ui.Offset(0, textY));

    // Rasterise to PNG.
    final picture = recorder.endRecording();
    final ui.Image composited = await picture.toImage(_stripW.toInt(), _stripH.toInt());
    final ByteData? pngData = await composited.toByteData(format: ui.ImageByteFormat.png);
    composited.dispose();
    picture.dispose();

    if (pngData == null) {
      throw StateError('Failed to encode photo strip as PNG.');
    }

    return pngData.buffer.asUint8List();
  }

  /// Decodes raw image bytes into a [ui.Image].
  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
