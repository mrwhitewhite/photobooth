import 'dart:typed_data';

class CapturedPhoto {
  final Uint8List bytes;
  final DateTime capturedAt;
  CapturedPhoto({required this.bytes, required this.capturedAt});
}

class LayoutSlot {
  final double x, y, w, h;
  const LayoutSlot(this.x, this.y, this.w, this.h);
}

enum PhotoLayout {
  layout1x1,
  layout2x1,
  layout2x2,
  layout3x1,
  layout4x2;

  int get photoCount => switch (this) {
        PhotoLayout.layout1x1 => 1,
        PhotoLayout.layout2x1 => 2,
        PhotoLayout.layout2x2 => 4,
        PhotoLayout.layout3x1 => 3,
        PhotoLayout.layout4x2 => 8,
      };

  String get label => switch (this) {
        PhotoLayout.layout1x1 => '1 Photo',
        PhotoLayout.layout2x1 => '2 Photos',
        PhotoLayout.layout2x2 => '4 Photos',
        PhotoLayout.layout3x1 => '3 Photos',
        PhotoLayout.layout4x2 => '8 Photos',
      };

  String get subtitle => switch (this) {
        PhotoLayout.layout1x1 => 'Single portrait',
        PhotoLayout.layout2x1 => 'Vertical duo strip',
        PhotoLayout.layout2x2 => '2×2 grid',
        PhotoLayout.layout3x1 => 'Triple strip',
        PhotoLayout.layout4x2 => '4×2 full session',
      };

  String get templateAsset => switch (this) {
        PhotoLayout.layout1x1 => 'assets/layout/1x1.png',
        PhotoLayout.layout2x1 => 'assets/layout/2x1_camera.png',
        PhotoLayout.layout2x2 => 'assets/layout/2x2.PNG',
        PhotoLayout.layout3x1 => 'assets/layout/3x1.png',
        PhotoLayout.layout4x2 => 'assets/layout/4x2.png',
      };

  String get thumbnailAsset => templateAsset;

  List<LayoutSlot> get slots => switch (this) {
        PhotoLayout.layout1x1 => const [
            LayoutSlot(0.0440, 0.1587, 0.9116, 0.6891),
          ],
        PhotoLayout.layout2x1 => const [
            LayoutSlot(0.1277, 0.2104, 0.5310, 0.2351),
            LayoutSlot(0.1883, 0.5845, 0.4707, 0.2071),
          ],
        PhotoLayout.layout2x2 => const [
            LayoutSlot(0.0254, 0.1324, 0.4639, 0.3470),
            LayoutSlot(0.5134, 0.1324, 0.4633, 0.3470),
            LayoutSlot(0.0254, 0.4947, 0.4639, 0.3458),
            LayoutSlot(0.5134, 0.4947, 0.4633, 0.3458),
          ],
        PhotoLayout.layout3x1 => const [
            LayoutSlot(0.0599, 0.0945, 0.8815, 0.2506),
            LayoutSlot(0.0599, 0.3647, 0.8815, 0.2459),
            LayoutSlot(0.0599, 0.6300, 0.8815, 0.2455),
          ],
        PhotoLayout.layout4x2 => const [
            LayoutSlot(0.084, 0.076, 0.344, 0.202), // Row 1, Left
            LayoutSlot(0.084, 0.291, 0.344, 0.202), // Row 2, Left
            LayoutSlot(0.084, 0.506, 0.344, 0.202), // Row 3, Left
            LayoutSlot(0.084, 0.721, 0.344, 0.202), // Row 4, Left
            LayoutSlot(0.572, 0.076, 0.344, 0.202), // Row 1, Right
            LayoutSlot(0.572, 0.291, 0.344, 0.202), // Row 2, Right
            LayoutSlot(0.572, 0.506, 0.344, 0.202), // Row 3, Right
            LayoutSlot(0.572, 0.721, 0.344, 0.202), // Row 4, Right
          ],
      };
}
