import 'dart:typed_data';

// ── Photo capture result ──────────────────────────────────────────────────────
class CapturedPhoto {
  final Uint8List bytes;
  final DateTime capturedAt;
  CapturedPhoto({required this.bytes, required this.capturedAt});
}

// ── Slot: normalized photo position within a template ─────────────────────────
// x, y, w, h are all fractions of the template's total width/height (0.0–1.0)
class LayoutSlot {
  final double x, y, w, h;
  const LayoutSlot(this.x, this.y, this.w, this.h);
}

// ── Photo layout options ──────────────────────────────────────────────────────
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

  /// Asset path for the transparent template PNG overlay
  String get templateAsset => switch (this) {
        PhotoLayout.layout1x1 => 'assets/layout/1x1.png',
        PhotoLayout.layout2x1 => 'assets/layout/2x1_camera.png',
        PhotoLayout.layout2x2 => 'assets/layout/2x2.PNG',
        PhotoLayout.layout3x1 => 'assets/layout/3x1.png',
        PhotoLayout.layout4x2 => 'assets/layout/4x2.png',
      };

  /// Thumbnail shown on the layout selection card (same PNG, just displayed smaller)
  String get thumbnailAsset => templateAsset;

  /// Photo slot positions within the template (normalized 0.0–1.0).
  /// These assume standard photobooth templates with consistent margins.
  /// Adjust if your specific template PNGs have different hole positions.
  List<LayoutSlot> get slots => switch (this) {
        PhotoLayout.layout1x1 => const [
            LayoutSlot(0.05, 0.05, 0.90, 0.82),
          ],
        PhotoLayout.layout2x1 => const [
            LayoutSlot(0.07, 0.04, 0.86, 0.44),
            LayoutSlot(0.07, 0.52, 0.86, 0.44),
          ],
        PhotoLayout.layout2x2 => const [
            LayoutSlot(0.04, 0.04, 0.45, 0.45),
            LayoutSlot(0.51, 0.04, 0.45, 0.45),
            LayoutSlot(0.04, 0.51, 0.45, 0.45),
            LayoutSlot(0.51, 0.51, 0.45, 0.45),
          ],
        PhotoLayout.layout3x1 => const [
            LayoutSlot(0.06, 0.03, 0.88, 0.29),
            LayoutSlot(0.06, 0.355, 0.88, 0.29),
            LayoutSlot(0.06, 0.68, 0.88, 0.29),
          ],
        PhotoLayout.layout4x2 => const [
            LayoutSlot(0.04, 0.03, 0.44, 0.21),
            LayoutSlot(0.52, 0.03, 0.44, 0.21),
            LayoutSlot(0.04, 0.265, 0.44, 0.21),
            LayoutSlot(0.52, 0.265, 0.44, 0.21),
            LayoutSlot(0.04, 0.50, 0.44, 0.21),
            LayoutSlot(0.52, 0.50, 0.44, 0.21),
            LayoutSlot(0.04, 0.735, 0.44, 0.21),
            LayoutSlot(0.52, 0.735, 0.44, 0.21),
          ],
      };
}
