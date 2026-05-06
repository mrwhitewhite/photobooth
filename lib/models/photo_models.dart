import 'dart:typed_data';

class CapturedPhoto {
  final Uint8List bytes;
  final DateTime capturedAt;

  CapturedPhoto({required this.bytes, required this.capturedAt});
}

enum PhotoLayout {
  single,
  doubleV,
  tripleV,
  quadV;

  int get photoCount {
    return switch (this) {
      PhotoLayout.single => 1,
      PhotoLayout.doubleV => 2,
      PhotoLayout.tripleV => 3,
      PhotoLayout.quadV => 4,
    };
  }

  String get label {
    return switch (this) {
      PhotoLayout.single => '1 Photo',
      PhotoLayout.doubleV => '2 Photos',
      PhotoLayout.tripleV => '3 Photos',
      PhotoLayout.quadV => '4 Strip',
    };
  }
}
