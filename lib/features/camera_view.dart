export 'camera_view_mobile.dart' if (dart.library.html) 'camera_view_web.dart';

class _TemplateSlotView extends StatelessWidget {
  final PhotoLayout layout;
  final List<LayoutSlot> slots;
  final Size? templateImageSize;
  final String viewID;
  final PhotoboothProvider provider;
  final int countdown;
  final AnimationController countdownAnim;
  final Animation<double> countdownScale;
  final Animation<double> countdownOpacity;

  const _TemplateSlotView({
    required this.layout,
    required this.slots,
    required this.templateImageSize,
    required this.viewID,
    required this.provider,
    required this.countdown,
    required this.countdownAnim,
    required this.countdownScale,
    required this.countdownOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final screenW = constraints.maxWidth;
      final screenH = constraints.maxHeight;

      double tw, th;
      if (templateImageSize != null) {
        final ar = templateImageSize!.width / templateImageSize!.height;

        th = screenH * 0.85;
        tw = th * ar;
        if (tw > screenW * 0.60) {
          tw = screenW * 0.60;
          th = tw / ar;
        }
      } else {
        th = screenH * 0.85;
        tw = th * (2 / 3);
      }

      final offsetX = (screenW - tw) / 2;
      final offsetY = (screenH - th) / 2;

      final activeIndex = provider.capturedCount;
      final hasActiveSlot =
          !provider.sessionComplete && activeIndex < slots.length;

      final double camLeft =
          hasActiveSlot ? offsetX + slots[activeIndex].x * tw : 0;
      final double camTop =
          hasActiveSlot ? offsetY + slots[activeIndex].y * th : 0;
      final double camW = hasActiveSlot ? slots[activeIndex].w * tw : 0;
      final double camH = hasActiveSlot ? slots[activeIndex].h * th : 0;

      return Stack(
        children: [
          Positioned(
            left: offsetX,
            top: offsetY,
            width: tw,
            height: th,
            child: Image.asset(layout.templateAsset, fit: BoxFit.fill),
          ),
          for (int i = 0; i < slots.length; i++)
            _buildSlotWidget(i, slots[i], tw, th, offsetX, offsetY),
          if (hasActiveSlot)
            Positioned(
              left: camLeft,
              top: camTop,
              width: camW,
              height: camH,
              child: HtmlElementView(viewType: viewID),
            ),
          if (hasActiveSlot)
            Positioned(
              left: camLeft,
              top: camTop,
              width: camW,
              height: camH,
              child: const _ActiveBorder(),
            ),
          if (countdown > 0 && hasActiveSlot)
            _buildCountdownOverlay(
                slots[activeIndex], tw, th, offsetX, offsetY),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: _buildProgressDots(),
          ),
        ],
      );
    });
  }

  Widget _buildSlotWidget(
    int index,
    LayoutSlot slot,
    double tw,
    double th,
    double offsetX,
    double offsetY,
  ) {
    final left = offsetX + slot.x * tw;
    final top = offsetY + slot.y * th;
    final width = slot.w * tw;
    final height = slot.h * th;

    final isCaptured = index < provider.capturedCount;
    final isActive =
        index == provider.capturedCount && !provider.sessionComplete;

    if (isActive) return const SizedBox.shrink();

    Widget content;

    if (isCaptured) {
      content = Image.memory(
        provider.photos[index],
        fit: BoxFit.cover,
        width: width,
        height: height,
      );
    } else {
      content = Container(
        width: width,
        height: height,
        color: Colors.black.withValues(alpha: 0.60),
        child: Center(
          child: Icon(
            Icons.camera_alt_outlined,
            color: Colors.white.withValues(alpha: 0.18),
            size: (width * 0.22).clamp(10.0, 34.0),
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: ClipRect(child: content),
    );
  }

  Widget _buildCountdownOverlay(
    LayoutSlot slot,
    double tw,
    double th,
    double offsetX,
    double offsetY,
  ) {
    final slotLeft = offsetX + slot.x * tw;
    final slotTop = offsetY + slot.y * th;
    final slotW = slot.w * tw;
    final slotH = slot.h * th;
    final centerX = slotLeft + slotW / 2;
    final centerY = slotTop + slotH / 2;

    final circleSize = (slotW.clamp(60.0, 300.0) * 0.65).clamp(60.0, 180.0);
    final fontSize = (circleSize * 0.5).clamp(24.0, 90.0);

    return Positioned(
      left: centerX - circleSize / 2,
      top: centerY - circleSize / 2,
      width: circleSize,
      height: circleSize,
      child: AnimatedBuilder(
        animation: countdownAnim,
        builder: (_, __) => Opacity(
          opacity: countdownOpacity.value,
          child: Transform.scale(
            scale: countdownScale.value,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  '$countdown',
                  style: GoogleFonts.lato(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        blurRadius: 20,
                        color: Colors.black.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(provider.totalRequired, (i) {
          final done = i < provider.capturedCount;
          final current =
              i == provider.capturedCount && !provider.sessionComplete;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: done
                  ? const Color(0xFFE8C8A0)
                  : current
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _ActiveBorder extends StatefulWidget {
  const _ActiveBorder();
  @override
  State<_ActiveBorder> createState() => _ActiveBorderState();
}

class _ActiveBorderState extends State<_ActiveBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFFE8C8A0).withValues(alpha: _pulse.value),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE8C8A0)
                  .withValues(alpha: _pulse.value * 0.35),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
