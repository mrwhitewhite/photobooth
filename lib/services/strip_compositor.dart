import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

@JS('URL.createObjectURL')
external JSString _createObjectURL(web.Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

class StripCompositor {
  static const double _stripW = 600.0;
  static const double _stripH = 1800.0;
  static const double _padding = 20.0;
  static const double _borderRadius = 8.0;

  static Future<Uint8List> generateStrip(List<Uint8List> photos) async {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = _stripW.toInt();
    canvas.height = _stripH.toInt();
    final ctx = canvas.context2D;

    // Fill Background (#1A1208 Art-Deco Surface)
    ctx.fillStyle = '#1A1208'.toJS; // FillStyle still needs toJS for the string
    ctx.fillRect(0, 0, _stripW, _stripH);

    final int count = photos.length;
    final double slotH = (_stripH - _padding * (count + 1)) / count;
    const double slotW = _stripW - _padding * 2;

    for (int i = 0; i < count; i++) {
      final double y = _padding + i * (slotH + _padding);
      const double x = _padding;

      final blob = web.Blob([photos[i].toJS].toJS);
      final url = _createObjectURL(blob).toDart;
      final img = web.HTMLImageElement();
      img.src = url;

      await img.onLoad.first;

      final double srcAspect = img.naturalWidth / img.naturalHeight;
      final double dstAspect = slotW / slotH;
      double sx, sy, sw, sh;

      if (srcAspect > dstAspect) {
        sh = img.naturalHeight.toDouble();
        sw = sh * dstAspect;
        sx = (img.naturalWidth - sw) / 2;
        sy = 0;
      } else {
        sw = img.naturalWidth.toDouble();
        sh = sw / dstAspect;
        sx = 0;
        sy = (img.naturalHeight - sh) / 2;
      }

      ctx.save();
      _drawRoundedRect(ctx, x, y, slotW, slotH, _borderRadius);
      ctx.clip();

      // FIX: Numerical arguments do NOT need .toJS
      ctx.drawImage(
          img,
          sx,
          sy,
          sw,
          sh, // Source
          x,
          y,
          slotW,
          slotH // Destination
          );

      ctx.restore();
      _revokeObjectURL(url);
    }

    // Draw Watermark
    ctx.fillStyle = 'rgba(232, 196, 160, 0.5)'.toJS;
    ctx.font = '24px "Playfair Display"';
    ctx.textAlign = 'center';
    // FIX: Coordinates do not need .toJS[cite: 1]
    ctx.fillText('✦ SnapBooth ✦', _stripW / 2, _stripH - 40);

    final completer = Completer<Uint8List>();
    void onBlob(web.Blob resultBlob) {
      final reader = web.FileReader();
      reader.readAsArrayBuffer(resultBlob);
      reader.onLoadEnd.first.then((_) {
        final buffer = (reader.result as JSArrayBuffer).toDart;
        completer.complete(buffer.asUint8List());
      });
    }

    canvas.toBlob(onBlob.toJS, 'image/png');

    return completer.future;
  }

  static void _drawRoundedRect(web.CanvasRenderingContext2D ctx, double x,
      double y, double w, double h, double r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }
}
