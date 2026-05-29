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
  layout3x1,
  layout2x2,
  layout4x2Narrow,
  layout4x2Wide;

  int get photoCount => switch (this) {
        PhotoLayout.layout1x1 => 1,
        PhotoLayout.layout2x1 => 2,
        PhotoLayout.layout2x2 => 4,
        PhotoLayout.layout3x1 => 3,
        PhotoLayout.layout4x2Narrow => 4,
        PhotoLayout.layout4x2Wide => 4,
      };

  String get label => switch (this) {
        PhotoLayout.layout1x1 => '1 Photo',
        PhotoLayout.layout2x1 => '2 Photos',
        PhotoLayout.layout2x2 => '4 Photos',
        PhotoLayout.layout3x1 => '3 Photos',
        PhotoLayout.layout4x2Narrow => '4 Photos (Flim Style)',
        PhotoLayout.layout4x2Wide => '4 Photos (Wide)',
      };

  String get subtitle => switch (this) {
        PhotoLayout.layout1x1 => 'Single portrait',
        PhotoLayout.layout2x1 => 'Vertical duo strip',
        PhotoLayout.layout2x2 => '2×2 grid',
        PhotoLayout.layout3x1 => 'Triple strip',
        PhotoLayout.layout4x2Narrow => '4×2 flim style strip',
        PhotoLayout.layout4x2Wide => '4×2 wide strip',
      };

  String get templateAsset => switch (this) {
        PhotoLayout.layout1x1 => 'assets/layout/1x1.jpeg',
        PhotoLayout.layout2x1 => 'assets/layout/2x1_camera.jpeg',
        PhotoLayout.layout2x2 => 'assets/layout/2x2.png',
        PhotoLayout.layout3x1 => 'assets/layout/3x1.jpeg',
        PhotoLayout.layout4x2Narrow => 'assets/layout/4x2_narrow.jpeg',
        PhotoLayout.layout4x2Wide => 'assets/layout/4x2_wide.jpeg',
      };

  String get thumbnailAsset => templateAsset;

  List<List<LayoutSlot>> get slots => switch (this) {
        PhotoLayout.layout1x1 => const [
            [LayoutSlot(0.0434, 0.1590, 0.9133, 0.6802)],
          ],
        PhotoLayout.layout2x1 => const [
            [LayoutSlot(0.1245, 0.2102, 0.5390, 0.2336)],
            [LayoutSlot(0.1874, 0.5828, 0.4733, 0.2086)],
          ],
        PhotoLayout.layout2x2 => const [
            [LayoutSlot(0.0243, 0.1324, 0.4652, 0.3463)],
            [LayoutSlot(0.5138, 0.1324, 0.4619, 0.3463)],
            [LayoutSlot(0.0243, 0.4954, 0.4652, 0.3454)],
            [LayoutSlot(0.5138, 0.4954, 0.4619, 0.3454)],
          ],
        PhotoLayout.layout3x1 => const [
            [LayoutSlot(0.0609, 0.0992, 0.8797, 0.2461)],
            [LayoutSlot(0.0609, 0.3648, 0.8797, 0.2461)],
            [LayoutSlot(0.0609, 0.6305, 0.8797, 0.2453)],
          ],
        PhotoLayout.layout4x2Narrow => const [
            [
              LayoutSlot(0.0859, 0.0750, 0.3406, 0.2016),
              LayoutSlot(0.5766, 0.0750, 0.3391, 0.2016)
            ], // Row 1
            [
              LayoutSlot(0.0859, 0.2906, 0.3406, 0.2016),
              LayoutSlot(0.5766, 0.2906, 0.3391, 0.2016)
            ], // Row 2
            [
              LayoutSlot(0.0859, 0.5062, 0.3406, 0.2031),
              LayoutSlot(0.5766, 0.5062, 0.3391, 0.2031)
            ], // Row 3
            [
              LayoutSlot(0.0859, 0.7227, 0.3406, 0.2016),
              LayoutSlot(0.5766, 0.7227, 0.3391, 0.2016)
            ], // Row 4
          ],
        PhotoLayout.layout4x2Wide => const [
            [
              LayoutSlot(0.0266, 0.0945, 0.4469, 0.1828),
              LayoutSlot(0.5266, 0.0945, 0.4484, 0.1828)
            ], // Row 1
            [
              LayoutSlot(0.0266, 0.2914, 0.4469, 0.1867),
              LayoutSlot(0.5266, 0.2914, 0.4484, 0.1867)
            ], // Row 2
            [
              LayoutSlot(0.0266, 0.4922, 0.4469, 0.1867),
              LayoutSlot(0.5266, 0.4922, 0.4484, 0.1867)
            ], // Row 3
            [
              LayoutSlot(0.0266, 0.6922, 0.4469, 0.1836),
              LayoutSlot(0.5266, 0.6922, 0.4484, 0.1836)
            ], // Row 4
          ],
      };
}
