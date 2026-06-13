import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/photo_models.dart';
import '../services/photobooth_provider.dart';

class _C {
  static const bg = Color(0xFFFFFFEA);
  static const surface = Color(0xFFF7F3D6);
  static const border = Color(0xFFE5DFC1);
  static const accent = Color(0xFFD9B87C);
  static const text = Color(0xFF4A4638);
  static const muted = Color.fromARGB(255, 71, 68, 56);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const _layouts = PhotoLayout.values;

  Timer? _idleTimer;
  static const _idleTimeout = Duration(seconds: 90);

  late PageController _pageController;

  double _viewportFraction(double width) {
    if (width <= 600) return 0.68;
    if (width <= 1024) return 0.55;
    return 0.42;
  }

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
    _pageController = PageController(
      viewportFraction: 0.65, // default, rebuilt in didChangeDependencies
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.of(context).size.width;
    final fraction = _viewportFraction(width);
    if (_pageController.viewportFraction != fraction) {
      _pageController.dispose();
      _pageController = PageController(
        viewportFraction: fraction,
        initialPage: _currentIndex,
      );
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _pageController.dispose();
    super.dispose();
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

  void _goLeft() {
    _resetIdleTimer();
    if (_currentIndex > 0) {
      _pageController.animateToPage(
        _currentIndex - 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goRight() {
    _resetIdleTimer();
    if (_currentIndex < _layouts.length - 1) {
      _pageController.animateToPage(
        _currentIndex + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPageChanged(int index) {
    _resetIdleTimer();
    setState(() => _currentIndex = index);
  }

  void _onCardTapped(int index) {
    _resetIdleTimer();
    if (index == _currentIndex) {
      _choose();
    } else {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _choose() {
    _idleTimer?.cancel();
    context.read<PhotoboothProvider>().startSession(_layouts[_currentIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _resetIdleTimer(),
      onPanDown: (_) => _resetIdleTimer(),
      child: Scaffold(
        backgroundColor: _C.bg,
        body: SafeArea(
          child: Column(
            children: [
              _Header(),
              const Divider(color: _C.border, height: 1),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _layouts.length,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final isActive = index == _currentIndex;
                    return _LayoutCard(
                      layout: _layouts[index],
                      isActive: isActive,
                      onTap: () => _onCardTapped(index),
                    );
                  },
                ),
              ),
              _DotIndicator(
                count: _layouts.length,
                activeIndex: _currentIndex,
              ),
              _BottomBar(
                currentIndex: _currentIndex,
                total: _layouts.length,
                onLeft: _goLeft,
                onRight: _goRight,
                onChoose: _choose,
                layoutLabel: _layouts[_currentIndex].label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(48, 32, 48, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select a Layout',
                    style: TextStyle(
                      fontFamily: 'Rascal',
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      color: _C.text,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout Card (carousel item)
// ---------------------------------------------------------------------------

class _LayoutCard extends StatelessWidget {
  final PhotoLayout layout;
  final bool isActive;
  final VoidCallback onTap;

  const _LayoutCard({
    required this.layout,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double scale = isActive ? 1.0 : 0.92;
    final double opacity = isActive ? 1.0 : 0.65;
    final Color borderColor = isActive ? _C.accent : _C.border;
    final double borderWidth = isActive ? 2.0 : 1.0;
    final List<BoxShadow> shadow = isActive
        ? [
            BoxShadow(
              color: _C.accent.withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ]
        : [];

    return Semantics(
      label: 'Layout option: ${layout.label}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          opacity: opacity,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            scale: scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: _C.surface,
                border: Border.all(color: borderColor, width: borderWidth),
                borderRadius: BorderRadius.circular(16),
                boxShadow: shadow,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // Layout label
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        layout.label.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Rascal',
                          fontSize: 14,
                          letterSpacing: 4,
                          color: _C.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        layout.subtitle,
                        style: const TextStyle(
                          fontFamily: 'Rascal',
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: _C.muted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Photo count badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _C.accent.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${layout.photoCount} PHOTOS',
                        style: const TextStyle(
                          fontFamily: 'Rascal',
                          fontSize: 10,
                          letterSpacing: 2,
                          color: _C.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Thumbnail preview
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: _C.border, width: 1),
                          borderRadius: BorderRadius.circular(8),
                          color: _C.bg,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            layout.thumbnailAsset,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dot Indicator
// ---------------------------------------------------------------------------

class _DotIndicator extends StatelessWidget {
  final int count;
  final int activeIndex;

  const _DotIndicator({required this.count, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final isActive = i == activeIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive
                  ? _C.accent
                  : _C.border.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Bar
// ---------------------------------------------------------------------------

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
    final canGoLeft = currentIndex > 0;
    final canGoRight = currentIndex < total - 1;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _C.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Row(
        children: [
          _NavArrowButton(
            icon: Icons.arrow_back_rounded,
            enabled: canGoLeft,
            onTap: onLeft,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _ChooseButton(onTap: onChoose),
          ),
          const SizedBox(width: 16),
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

// ---------------------------------------------------------------------------
// Nav Arrow Button
// ---------------------------------------------------------------------------

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
    final color = widget.enabled ? (_pressed ? _C.accent : _C.text) : _C.border;

    return Semantics(
      label: widget.icon == Icons.arrow_back_rounded
          ? 'Previous layout'
          : 'Next layout',
      button: true,
      child: GestureDetector(
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
            color:
                _pressed ? _C.accent.withValues(alpha: 0.08) : Colors.transparent,
          ),
          child: Icon(widget.icon, color: color, size: 22),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choose Button
// ---------------------------------------------------------------------------

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
              color: _hovered ? _C.accent : _C.accent.withValues(alpha: 0.9),
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
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'SELECT THIS',
                style: TextStyle(
                  fontFamily: 'Rascal',
                  fontSize: 13,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                  color: _C.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
