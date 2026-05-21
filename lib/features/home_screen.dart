import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/photo_models.dart';
import '../services/photobooth_provider.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
class _C {
  static const bg       = Color(0xFF0D0D0D);
  static const surface  = Color(0xFF1A1A1A);
  static const border   = Color(0xFF2E2E2E);
  static const accent   = Color(0xFFE8C8A0);  // warm gold
  static const text     = Color(0xFFF0EDE8);
  static const muted    = Color(0xFF888480);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const _layouts = PhotoLayout.values;

  void _goLeft() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _goRight() {
    if (_currentIndex < _layouts.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _choose() {
    context.read<PhotoboothProvider>().startSession(_layouts[_currentIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layouts[_currentIndex];

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            const Divider(color: _C.border, height: 1),
            // ── Main layout preview ──────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _LayoutPreview(
                  key: ValueKey(layout),
                  layout: layout,
                ),
              ),
            ),
            // ── Bottom bar: ← [Choose This Layout] → ─────────────────
            _BottomBar(
              currentIndex: _currentIndex,
              total: _layouts.length,
              onLeft: _goLeft,
              onRight: _goRight,
              onChoose: _choose,
              layoutLabel: layout.label,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELECT YOUR FORMAT',
                style: GoogleFonts.lato(
                  fontSize: 10,
                  letterSpacing: 5,
                  color: _C.accent,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Choose a Layout',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  fontStyle: FontStyle.italic,
                  color: _C.text,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const Spacer(),
          Image.asset(
            'assets/logo.png',
            height: 40,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

// ── Single layout preview (one per page) ──────────────────────────────────────
class _LayoutPreview extends StatelessWidget {
  final PhotoLayout layout;
  const _LayoutPreview({super.key, required this.layout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Column(
        children: [
          // ── Layout name + details ──
          Text(
            layout.label.toUpperCase(),
            style: GoogleFonts.lato(
              fontSize: 14,
              letterSpacing: 4,
              color: _C.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            layout.subtitle,
            style: GoogleFonts.cormorant(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: _C.muted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: _C.accent.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${layout.photoCount} PHOTOS',
              style: GoogleFonts.lato(
                fontSize: 10,
                letterSpacing: 2,
                color: _C.accent,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ── Large thumbnail ──
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _C.border, width: 1),
                borderRadius: BorderRadius.circular(8),
                color: _C.surface,
              ),
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  layout.thumbnailAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom bar with left / choose / right ─────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final int total;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onChoose;
  final String layoutLabel;

  const _BottomBar({
    required this.currentIndex,
    required this.total,
    required this.onLeft,
    required this.onRight,
    required this.onChoose,
    required this.layoutLabel,
  });

  @override
  Widget build(BuildContext context) {
    final canGoLeft  = currentIndex > 0;
    final canGoRight = currentIndex < total - 1;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _C.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Row(
        children: [
          // ── Left arrow ──
          _NavArrowButton(
            icon: Icons.arrow_back_rounded,
            enabled: canGoLeft,
            onTap: onLeft,
          ),
          const SizedBox(width: 16),
          // ── Choose this layout button (fills remaining space) ──
          Expanded(
            child: _ChooseButton(onTap: onChoose),
          ),
          const SizedBox(width: 16),
          // ── Right arrow ──
          _NavArrowButton(
            icon: Icons.arrow_forward_rounded,
            enabled: canGoRight,
            onTap: onRight,
          ),
        ],
      ),
    );
  }
}

// ── Arrow navigation button ───────────────────────────────────────────────────
class _NavArrowButton extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_NavArrowButton> createState() => _NavArrowButtonState();
}

class _NavArrowButtonState extends State<_NavArrowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? (_pressed ? _C.accent : _C.text)
        : _C.border;

    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.enabled
                ? (_pressed ? _C.accent : _C.border)
                : _C.border.withValues(alpha: 0.4),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
          color: _pressed ? _C.accent.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Icon(widget.icon, color: color, size: 22),
      ),
    );
  }
}

// ── Choose button ─────────────────────────────────────────────────────────────
class _ChooseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ChooseButton({required this.onTap});

  @override
  State<_ChooseButton> createState() => _ChooseButtonState();
}

class _ChooseButtonState extends State<_ChooseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 56,
            decoration: BoxDecoration(
              color: _hovered
                  ? _C.accent
                  : _C.accent.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: _C.accent.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'CHOOSE THIS LAYOUT',
                  style: GoogleFonts.lato(
                    fontSize: 13,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                    color: _C.bg,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: _C.bg,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
