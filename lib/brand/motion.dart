import 'package:flutter/material.dart';

/// Durations from MARCA.md ("Movimiento").
abstract final class BrandDurations {
  static const tap = Duration(milliseconds: 120);
  static const state = Duration(milliseconds: 200);
  static const card = Duration(milliseconds: 320);
  static const page = Duration(milliseconds: 450);
  static const chanchiShort = Duration(milliseconds: 600);
  static const chanchiLong = Duration(milliseconds: 1200);
  static const balanceCount = Duration(milliseconds: 700);
  static const stagger = Duration(milliseconds: 40);

  /// With reduced motion only fades of this length or less remain.
  static const reducedFade = Duration(milliseconds: 150);

  /// Exits last 70% of the matching entrance.
  static Duration exitOf(Duration enter) =>
      Duration(microseconds: (enter.inMicroseconds * 0.7).round());
}

/// Curves from MARCA.md.
abstract final class BrandCurves {
  static const enter = Cubic(0.22, 1, 0.36, 1);

  /// Only for small elements: scan button, chips and Chanchi.
  static const bounce = Curves.easeOutBack;
  static const exit = Curves.easeInCubic;
}

/// Tabular figures, required for every money number.
const tabularFigures = [FontFeature.tabularFigures()];

/// Durations and curves resolved against the "reduce motion" setting
/// (`MediaQuery.disableAnimations`).
class BrandMotion {
  const BrandMotion({this.reduce = false});

  final bool reduce;

  static BrandMotion of(BuildContext context) => BrandMotion(
    reduce: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  /// Press feedback: none at all with reduced motion.
  Duration get tap => reduce ? Duration.zero : BrandDurations.tap;

  /// State changes become a fade of 150 ms or less.
  Duration get state =>
      reduce ? BrandDurations.reducedFade : BrandDurations.state;
  Duration get card =>
      reduce ? BrandDurations.reducedFade : BrandDurations.card;
  Duration get page =>
      reduce ? BrandDurations.reducedFade : BrandDurations.page;

  /// Delay between items of a staggered list.
  Duration get stagger => reduce ? Duration.zero : BrandDurations.stagger;

  Curve get enter => BrandCurves.enter;
  Curve get bounce => reduce ? BrandCurves.enter : BrandCurves.bounce;
  Curve get exit => BrandCurves.exit;
}

/// Fades and slides its child in, [BrandDurations.stagger] after the previous
/// item. Only the first [maxAnimated] items animate; the rest are just there.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.maxAnimated = 8,
  });

  final int index;
  final Widget child;
  final int maxAnimated;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final motion = BrandMotion.of(context);
    if (motion.reduce || widget.index >= widget.maxAnimated) return;

    final delay = BrandDurations.stagger * widget.index;
    final total = delay + BrandDurations.card;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: BrandCurves.enter,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return widget.child;

    return AnimatedBuilder(
      animation: progress,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: progress.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - progress.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Scales its child to 0.97 while it is pressed. It listens to raw pointers,
/// so it never competes with the child's own tap handling.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final motion = BrandMotion.of(context);

    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !motion.reduce ? widget.scale : 1,
        duration: motion.tap,
        curve: BrandCurves.enter,
        child: widget.child,
      ),
    );
  }
}

/// Counts from the previous value (from zero the first time) up to [value] in
/// 700 ms. With reduced motion it shows the final value from the first frame.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.textAlign,
    this.duration = BrandDurations.balanceCount,
  });

  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final effective = base.copyWith(fontFeatures: tabularFigures);

    if (BrandMotion.of(context).reduce) {
      return Text(format(value), style: effective, textAlign: textAlign);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, current, _) =>
          Text(format(current), style: effective, textAlign: textAlign),
    );
  }
}
