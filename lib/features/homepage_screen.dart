import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/bluetooth_manager.dart';
import '../services/photobooth_provider.dart';
import '../services/printer_service.dart';

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideUp = Tween<double>(begin: 40, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    try {
      await PrinterService.ensureBluetoothPermissions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }

    final saved = await BluetoothManager.getSavedDevice();

    if (saved != null) {
      if (mounted) {
        context.read<PhotoboothProvider>().goToLayoutSelect();
      }
      return;
    }

    if (!mounted) return;
    final chosen = await BluetoothManager.showPickerDialog(context);

    if (chosen == null) {
      return;
    }

    await BluetoothManager.saveDevice(chosen.id, chosen.name);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer "${chosen.name}" saved.'),
          backgroundColor: const Color(0xFFF7F3D6),
        ),
      );
      context.read<PhotoboothProvider>().goToLayoutSelect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/homepage.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFFFFFFEA).withValues(alpha: 0.9),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) => Opacity(
              opacity: _fadeIn.value,
              child: Transform.translate(
                offset: Offset(0, _slideUp.value),
                child: child,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 8),
                _SavedPrinterBadge(onChangePrinter: _showChangePrinterDialog),
                const SizedBox(height: 40),
                _StartButton(onTap: _handleStart),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showChangePrinterDialog() async {
    final chosen = await BluetoothManager.showPickerDialog(context);
    if (chosen == null) return;
    await BluetoothManager.saveDevice(chosen.id, chosen.name);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer changed to "${chosen.name}".'),
          backgroundColor: const Color(0xFFF7F3D6),
        ),
      );
    }
  }
}

class _SavedPrinterBadge extends StatefulWidget {
  final VoidCallback onChangePrinter;
  const _SavedPrinterBadge({required this.onChangePrinter});

  @override
  State<_SavedPrinterBadge> createState() => _SavedPrinterBadgeState();
}

class _SavedPrinterBadgeState extends State<_SavedPrinterBadge> {
  String? _savedName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await BluetoothManager.getSavedDevice();
    if (mounted) setState(() => _savedName = saved?.name);
  }

  @override
  Widget build(BuildContext context) {
    if (_savedName == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: widget.onChangePrinter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3D6).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD9B87C), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_connected,
                color: Color(0xFFD9B87C), size: 14),
            const SizedBox(width: 6),
            Text(
              _savedName!,
              style: const TextStyle(
                color: Color(0xFFD9B87C),
                fontSize: 12,
                fontFamily: 'PoppinsMedium',
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Change',
              style: TextStyle(
                color: Color(0xFF7B7561),
                fontSize: 11,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFF7B7561),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartButton extends StatefulWidget {
  final VoidCallback onTap;
  const _StartButton({required this.onTap});

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 220,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFEADFC3),
            border: Border.all(color: const Color(0xFF4A4638), width: 4),
          ),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFFFF6E6), width: 4),
                left: BorderSide(color: Color(0xFFFFF6E6), width: 4),
                bottom: BorderSide(color: Color(0xFFC6B895), width: 4),
                right: BorderSide(color: Color(0xFFC6B895), width: 4),
              ),
            ),
            child: const Center(
              child: Text(
                'Start',
                style: TextStyle(
                  fontFamily: 'CHAOS16',
                  fontSize: 24,
                  color: Color(0xFF4A4638),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
