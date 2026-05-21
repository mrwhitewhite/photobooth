import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../models/photo_models.dart';
import '../services/image_processor.dart';
import '../services/photobooth_provider.dart';
import '../services/printer_service.dart';

class _C {
  static const bg = Color(0xFF0D0D0D);
  static const surface = Color(0xFF161616);
  static const border = Color(0xFF2A2A2A);
  static const accent = Color(0xFFE8C8A0);
  static const text = Color(0xFFF0EDE8);
  static const muted = Color(0xFF888480);
  static const danger = Color(0xFFFF6B6B);
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with SingleTickerProviderStateMixin {
  bool _isCompositing = true;
  bool _isPrinting = false;
  Uint8List? _composite;
  String? _error;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _buildComposite();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _buildComposite() async {
    final provider = context.read<PhotoboothProvider>();
    try {
      final bytes = await ImageProcessor.composite(
        photos: provider.allPhotos,
        layout: provider.selectedLayout,
      );
      if (mounted) {
        provider.setComposite(bytes);
        setState(() {
          _composite = bytes;
          _isCompositing = false;
        });
        _fadeCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isCompositing = false;
        });
      }
    }
  }

  void _download() {
    if (_composite == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    ImageProcessor.downloadFile(_composite!, 'myreceipt_$ts.png');
  }

  Future<void> _print() async {
    if (_composite == null || _isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      await PrinterService.printReceipt(_composite!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sent to XPrinter ✓',
              style: const TextStyle(
                  fontFamily: 'PoppinsMedium', letterSpacing: 1),
            ),
            backgroundColor: const Color(0xFF1E3A1E),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) {
        _showPrintError(e.message);
      }
    } catch (e) {
      if (mounted) {
        // Clear cached BLE device so next tap shows the picker again.
        PrinterService.disconnect();
        _showPrintError(
          'Bluetooth error — tap PRINT again to reconnect.\n${e.toString()}',
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showPrintError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style:
              const TextStyle(fontFamily: 'PoppinsMedium', letterSpacing: 0.5),
        ),
        backgroundColor: _C.danger,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'RECONNECT',
          textColor: _C.accent,
          onPressed: () {
            PrinterService.disconnect();
            _print();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PhotoboothProvider>();

    return Scaffold(
      backgroundColor: _C.bg,
      body: Row(
        children: [
          // ── Left panel: composited image ──────────────────────────────────
          Expanded(
            flex: 6,
            child: Container(
              color: _C.surface,
              child: _buildPreviewPanel(),
            ),
          ),
          // ── Divider ───────────────────────────────────────────────────────
          Container(width: 1, color: _C.border),
          // ── Right panel: actions ──────────────────────────────────────────
          SizedBox(
            width: 320,
            child: _buildActionPanel(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    if (_isCompositing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child:
                  CircularProgressIndicator(color: _C.accent, strokeWidth: 1.5),
            ),
            const SizedBox(height: 24),
            Text(
              'COMPOSITING YOUR PHOTOS',
              style: const TextStyle(
                  fontFamily: 'PoppinsMedium',
                  fontSize: 10,
                  letterSpacing: 4,
                  color: _C.muted),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _C.danger, size: 48),
              const SizedBox(height: 16),
              Text('Compositing failed',
                  style: const TextStyle(
                      fontFamily: 'PoppinsMedium', color: _C.text)),
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      fontFamily: 'PoppinsMedium',
                      color: _C.muted,
                      fontSize: 12)),
            ],
          ),
        ),
      );
    }

    if (_composite == null) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fadeAnim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 60,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Image.memory(
              _composite!,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionPanel(PhotoboothProvider provider) {
    return Container(
      color: _C.bg,
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text(
          //   'YOUR PHOTOS',
          //   style: const TextStyle(
          //     fontFamily: 'PoppinsMedium',
          //     fontSize: 9,
          //     letterSpacing: 5,
          //     color: _C.accent,
          //   ),
          // ),
          const SizedBox(height: 12),
          Text(
            'Preview',
            style: const TextStyle(
              fontFamily: 'CHAOS16',
              fontSize: 48,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
              color: _C.text,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          Container(
              width: 40, height: 1, color: _C.accent.withValues(alpha: 0.5)),
          const SizedBox(height: 20),

          // Layout name
          Text(
            provider.selectedLayout.label,
            style: const TextStyle(
              fontFamily: 'CHAOS16',
              fontSize: 20,
              color: _C.muted,
            ),
          ),
          Text(
            '${provider.capturedCount} photos captured',
            style: const TextStyle(
              fontFamily: 'CHAOS16',
              fontSize: 20,
              color: _C.muted,
            ),
          ),

          // Photo thumbnails row
          if (provider.allPhotos.isNotEmpty) ...[
            const SizedBox(height: 24),
            _PhotoStrip(
                photos: provider.allPhotos, layout: provider.selectedLayout),
          ],

          const Spacer(),

          // ── Action buttons ────────────────────────────────────────────────

          // Print — opens browser print dialog sized for XPrinter 80 mm roll
          _ActionButton(
            label: _isPrinting ? 'PRINTING…' : 'PRINT',
            icon: _isPrinting
                ? Icons.hourglass_top_rounded
                : Icons.print_outlined,
            filled: false,
            enabled: _composite != null && !_isPrinting,
            onTap: _print,
          ),
          const SizedBox(height: 12),

          // Download
          _ActionButton(
            label: 'DOWNLOAD',
            icon: Icons.download_rounded,
            filled: true,
            enabled: _composite != null,
            onTap: _download,
          ),
          const SizedBox(height: 24),

          // Divider
          Container(height: 1, color: _C.border),
          const SizedBox(height: 24),

          // Reset → screensaver
          _ActionButton(
            label: 'START OVER',
            icon: Icons.refresh_rounded,
            filled: false,
            enabled: true,
            danger: true,
            onTap: () => provider.reset(),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'MyReceipt · ${DateTime.now().year}',
              style: const TextStyle(
                  fontFamily: 'PoppinsMedium',
                  fontSize: 9,
                  letterSpacing: 3,
                  color: _C.border),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo thumbnails strip ────────────────────────────────────────────────────
class _PhotoStrip extends StatelessWidget {
  final List<Uint8List> photos;
  final PhotoLayout layout;
  const _PhotoStrip({required this.photos, required this.layout});

  @override
  Widget build(BuildContext context) {
    // Show up to 8 thumbnails, scroll horizontally
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child:
              Image.memory(photos[i], width: 52, height: 52, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 140));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _bg {
    if (!widget.enabled) return _C.surface;
    if (widget.filled) return _C.accent;
    return Colors.transparent;
  }

  Color get _fg {
    if (!widget.enabled) return _C.muted;
    if (widget.filled) return const Color(0xFF1A1A1A);
    if (widget.danger) return _C.danger;
    return _C.text;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _ctrl.forward() : null,
      onTapUp: widget.enabled
          ? (_) {
              _ctrl.reverse();
              widget.onTap();
            }
          : null,
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _bg,
            border: Border.all(
              color: widget.danger
                  ? _C.danger.withValues(alpha: 0.5)
                  : widget.filled
                      ? Colors.transparent
                      : _C.border,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: _fg, size: 16),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'PoppinsMedium',
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                  color: _fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
