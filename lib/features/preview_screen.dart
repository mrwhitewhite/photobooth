import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../models/photo_models.dart';
import '../services/image_processor.dart';
import '../services/local_save_service.dart';
import '../services/photobooth_provider.dart';
import '../services/printer_service.dart';
import '../services/email_service.dart';

class _C {
  static const bg = Color(0xFFFFFFEA);
  static const surface = Color(0xFFF5F1D2);
  static const border = Color(0xFFE5DFC1);
  static const accent = Color(0xFFD9B87C);
  static const text = Color(0xFF4A4638);
  static const muted = Color(0xFF7B7561);
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
  bool _isSendingEmail = false;
  bool _isSaving = false;
  Uint8List? _composite;
  String? _error;

  Timer? _idleTimer;
  static const _idleTimeout = Duration(seconds: 90);

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _buildComposite();
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdle);
  }

  void _onIdle() {
    if (mounted) {
      context.read<PhotoboothProvider>().reset();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
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
        // Auto-save to local storage right after compositing.
        _autoSave(bytes);
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

  Future<void> _autoSave(Uint8List bytes) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final path = await LocalSaveService.saveComposite(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Color(0xFFD9B87C), size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Photo saved locally ✓\n$path',
                    style: const TextStyle(
                      fontFamily: 'PoppinsMedium',
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E3A1E),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auto-save failed: ${e.toString()}',
              style: const TextStyle(
                  fontFamily: 'PoppinsMedium', letterSpacing: 0.5),
            ),
            backgroundColor: _C.danger,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendEmail() async {
    if (_composite == null || _isSendingEmail) return;

    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _C.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.email_outlined, color: _C.accent, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'SEND PHOTO',
                      style: TextStyle(
                        fontFamily: 'PoppinsMedium',
                        fontSize: 13,
                        letterSpacing: 3,
                        color: _C.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter the email address to receive your photo.',
                  style: TextStyle(
                    fontFamily: 'PoppinsMedium',
                    fontSize: 11,
                    color: _C.muted,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: emailController,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(
                    fontFamily: 'PoppinsMedium',
                    color: _C.text,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'example@email.com',
                    hintStyle: const TextStyle(
                      fontFamily: 'PoppinsMedium',
                      color: _C.muted,
                      fontSize: 12,
                    ),
                    prefixIcon: const Icon(Icons.alternate_email_rounded,
                        color: _C.muted, size: 18),
                    filled: true,
                    fillColor: _C.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _C.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _C.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _C.accent),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _C.danger),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _C.danger),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter an email address';
                    }
                    final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$');
                    if (!emailRegex.hasMatch(v.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(color: _C.border),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Text(
                              'CANCEL',
                              style: TextStyle(
                                fontFamily: 'PoppinsMedium',
                                fontSize: 11,
                                letterSpacing: 2,
                                color: _C.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.of(ctx).pop(true);
                          }
                        },
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: _C.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Text(
                              'SEND',
                              style: TextStyle(
                                fontFamily: 'PoppinsMedium',
                                fontSize: 11,
                                letterSpacing: 2,
                                color: _C.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final email = emailController.text.trim();
    setState(() => _isSendingEmail = true);
    try {
      await EmailService.sendPhoto(
        recipientEmail: email,
        imageBytes: _composite!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo sent to $email ✓',
              style: const TextStyle(
                  fontFamily: 'PoppinsMedium', letterSpacing: 1),
            ),
            backgroundColor: const Color(0xFF1E3A1E),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send email: ${e.toString()}',
              style: const TextStyle(
                  fontFamily: 'PoppinsMedium', letterSpacing: 0.5),
            ),
            backgroundColor: _C.danger,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  Future<void> _print() async {
    if (_composite == null || _isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      await PrinterService.ensureBluetoothPermissions();
      await PrinterService.printReceipt(_composite!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sent to XPrinter ✓',
              style: TextStyle(fontFamily: 'PoppinsMedium', letterSpacing: 1),
            ),
            backgroundColor: Color(0xFF1E3A1E),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) {
        _showPrintError(e.message);
      }
    } catch (e) {
      if (mounted) {
        PrinterService.disconnect();
        _showPrintError(
          'Bluetooth error — tap PRINT to reconnect.\n${e.toString()}',
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _resetIdleTimer(),
      onPanDown: (_) => _resetIdleTimer(),
      child: Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 900 ||
                constraints.maxWidth < constraints.maxHeight;
            if (isNarrow) {
              return Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: Container(
                      color: _C.surface,
                      child: _buildPreviewPanel(),
                    ),
                  ),
                  Container(height: 1, color: _C.border),
                  Expanded(
                    flex: 6,
                    child: _buildActionPanel(provider, compact: true),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Container(
                    color: _C.surface,
                    child: _buildPreviewPanel(),
                  ),
                ),
                Container(width: 1, color: _C.border),
                SizedBox(
                  width: 320,
                  child: _buildActionPanel(provider, compact: false),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    if (_isCompositing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child:
                  CircularProgressIndicator(color: _C.accent, strokeWidth: 1.5),
            ),
            SizedBox(height: 24),
            Text(
              'COMPOSITING YOUR PHOTOS',
              style: TextStyle(
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
              const Text('Compositing failed',
                  style:
                      TextStyle(fontFamily: 'PoppinsMedium', color: _C.text)),
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
                  color: _C.accent.withValues(alpha: 0.25),
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

  Widget _buildActionPanel(
    PhotoboothProvider provider, {
    required bool compact,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Preview',
          style: TextStyle(
            fontFamily: 'Rascal',
            fontSize: compact ? 36 : 48,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
            color: _C.text,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 40,
          height: 1,
          color: _C.accent.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          provider.selectedLayout.label,
          style: const TextStyle(
            fontFamily: 'Rascal',
            fontSize: 20,
            color: _C.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${provider.capturedCount} photos captured',
          style: const TextStyle(
            fontFamily: 'Rascal',
            fontSize: 20,
            color: _C.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (provider.allPhotos.isNotEmpty) ...[
          const SizedBox(height: 20),
          _PhotoStrip(
              photos: provider.allPhotos, layout: provider.selectedLayout),
        ],
        if (!compact) const Spacer(),
        if (compact) const SizedBox(height: 24),
        _ActionButton(
          label: _isPrinting ? 'PRINTING…' : 'PRINT',
          icon:
              _isPrinting ? Icons.hourglass_top_rounded : Icons.print_outlined,
          filled: false,
          enabled: _composite != null && !_isPrinting,
          onTap: _print,
        ),
        const SizedBox(height: 12),
        _ActionButton(
          label: _isSendingEmail ? 'SENDING…' : 'SEND EMAIL',
          icon: _isSendingEmail
              ? Icons.hourglass_top_rounded
              : Icons.email_outlined,
          filled: true,
          enabled: _composite != null && !_isSendingEmail,
          onTap: _sendEmail,
        ),
        const SizedBox(height: 24),
        Container(height: 1, color: _C.border),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'START OVER',
          icon: Icons.refresh_rounded,
          filled: false,
          enabled: true,
          danger: true,
          onTap: () => provider.reset(),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'MyReceipt · ${DateTime.now().year}',
            style: const TextStyle(
              fontFamily: 'PoppinsMedium',
              fontSize: 9,
              letterSpacing: 3,
              color: _C.border,
            ),
          ),
        ),
      ],
    );

    return Container(
      color: _C.bg,
      padding: compact
          ? const EdgeInsets.all(24)
          : const EdgeInsets.fromLTRB(32, 48, 32, 40),
      child: compact ? SingleChildScrollView(child: content) : content,
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  final List<Uint8List> photos;
  final PhotoLayout layout;
  const _PhotoStrip({required this.photos, required this.layout});

  @override
  Widget build(BuildContext context) {
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
    if (widget.filled) return _C.text;
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
