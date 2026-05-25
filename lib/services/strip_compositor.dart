import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

@JS('URL.createObjectURL')
external JSString _createObjectURL(web.Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

class StripCompositor {
  // FIXED: Adjusted to 576 x 1728 to hit the exact 72mm printable width at 203 DPI (8 dots/mm)
  static const double _stripW = 576.0; 
  static const double _stripH = 1728.0; 
  
  // Adjusted padding proportionally for the tighter pixel space
  static const double _padding = 16.0;
  static const double _borderRadius = 6.0;

  static Future<Uint8List> generateStrip(List<Uint8List> photos) async {
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = _stripW.toInt();
    canvas.height = _stripH.toInt();
    final ctx = canvas.context2D;

    // FIXED: Pure Black Background for maximum thermal burner contrast
    ctx.fillStyle = '#000000'.toJS; 
    ctx.fillRect(0, 0, _stripW, _stripH);

    final int count = photos.length;
    final double slotH = (_stripH - _padding * (count + 1)) / count;
    final double slotW = _stripW - _padding * 2;

    for (int i = 0; i < count; i++) {
      final double y = _padding + i * (slotH + _padding);
      const double x = _padding;

      final blob = web.Blob([photos[i].toJS].toJS);
      final url = _createObjectURL(blob).toDart;
      final img = web.HTMLImageElement();
      img.src = url;

      try {
        await Future.any([
          img.onLoad.first,
          img.onError.first.then((_) => throw Exception("Failed to load photo at index $i")),
        ]);
      } catch (e) {
        _revokeObjectURL(url);
        rethrow;
      }

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

      ctx.drawImage(img, sx, sy, sw, sh, x, y, slotW, slotH);

      ctx.restore();
      _revokeObjectURL(url);
    }

    // FIXED: Changed to solid pure white. Alpha transparencies cause messy dithering on 203 DPI heads.
    ctx.fillStyle = '#FFFFFF'.toJS; 
    ctx.font = 'bold 24px "Playfair Display", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('✦ SnapBooth ✦', _stripW / 2, _stripH - 40);

    final completer = Completer<Uint8List>();

    void onBlob(web.Blob? resultBlob) {
      if (resultBlob == null) {
        completer.completeError(Exception("Canvas export returned null."));
        return;
      }
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