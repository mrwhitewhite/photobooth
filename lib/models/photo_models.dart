import 'dart:typed_data';

class CapturedPhoto {
  final Uint8List bytes;
  final DateTime capturedAt;

  CapturedPhoto({required this.bytes, required this.capturedAt});
}
