import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
// Conditional export: use web implementation when compiled for web,
// otherwise use the mobile stub. This prevents web-only `package:web`
// APIs from being analyzed/compiled for Android builds.
export 'image_processor_mobile.dart'
    if (dart.library.html) 'image_processor_web.dart';
}

class _TransparentBox {
  int xMin;
  int xMax;
  int yMin;
  int yMax;

  _TransparentBox(this.xMin, this.xMax, this.yMin, this.yMax);

  int get area => (xMax - xMin + 1) * (yMax - yMin + 1);
}
