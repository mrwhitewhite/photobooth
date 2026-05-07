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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(),
            const Divider(color: _C.border, height: 1),
            Expanded(child: _LayoutGrid()),
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
          Text(
            'SnapBooth',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 22,
              fontStyle: FontStyle.italic,
              color: _C.muted,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Layout grid ───────────────────────────────────────────────────────────────
class _LayoutGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const layouts = PhotoLayout.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.72,
        ),
        itemCount: layouts.length,
        itemBuilder: (_, i) => _LayoutCard(layout: layouts[i]),
      ),
    );
  }
}

// ── Layout card ───────────────────────────────────────────────────────────────
class _LayoutCard extends StatefulWidget {
  final PhotoLayout layout;
  const _LayoutCard({required this.layout});

  @override
  State<_LayoutCard> createState() => _LayoutCardState();
}

class _LayoutCardState extends State<_LayoutCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<Color?> _borderColor;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _borderColor = ColorTween(begin: _C.border, end: _C.accent)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
          context.read<PhotoboothProvider>().startSession(widget.layout);
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                color: _hovered ? _C.surface : _C.bg,
                border: Border.all(
                  color: _borderColor.value ?? _C.border,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: child,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Template thumbnail
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        widget.layout.thumbnailAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(height: 1, color: _C.border),
                  const SizedBox(height: 10),
                  Text(
                    widget.layout.label.toUpperCase(),
                    style: GoogleFonts.lato(
                      fontSize: 9,
                      letterSpacing: 2.5,
                      color: _C.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.layout.subtitle,
                    style: GoogleFonts.cormorant(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: _C.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: _C.accent.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          '${widget.layout.photoCount} PHOTOS',
                          style: GoogleFonts.lato(
                            fontSize: 8,
                            letterSpacing: 1.5,
                            color: _C.accent,
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
      ),
    );
  }
}
