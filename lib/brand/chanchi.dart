import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:monekin/brand/motion.dart';

enum ChanchiMood { idle, happy, thinking, sleepy, worried }

class _MoodLayers {
  const _MoodLayers(this.eyes, this.mouth, [this.extra]);

  final String eyes;
  final String mouth;
  final String? extra;

  bool get blinks => eyes == 'open' || eyes == 'up' || eyes == 'worried';
}

// Mirrors MOODS in tools/brand/gen_chanchi.py.
const _moods = {
  ChanchiMood.idle: _MoodLayers('open', 'smile'),
  ChanchiMood.happy: _MoodLayers('happy', 'big', 'coin'),
  ChanchiMood.thinking: _MoodLayers('up', 'flat', 'thought'),
  ChanchiMood.sleepy: _MoodLayers('closed', 'flat', 'zz'),
  ChanchiMood.worried: _MoodLayers('worried', 'o', 'sweat'),
};

const _layersDir = 'assets/brand/layers/chanchi_';
const _viewBoxWidth = 160.0;
const _viewBoxHeight = 140.0;

String _asset(String name) => '$_layersDir$name.svg';

/// The mascot, drawn as stacked SVG layers so each part moves on its own.
/// Decorative: the text next to it carries the message.
class ChanchiMascot extends StatefulWidget {
  const ChanchiMascot({
    super.key,
    required this.mood,
    this.size = 120,
    this.animate = true,
  });

  final ChanchiMood mood;

  /// Width in dp; the height keeps the 160 × 140 proportion.
  final double size;

  /// With false (or with reduced motion) it is drawn still, with no timers.
  final bool animate;

  static final Set<String> _loaded = {};

  static Iterable<String> get _allAssets => [
    _asset('body'),
    for (final l in _moods.values) ...[
      _asset('eyes_${l.eyes}'),
      _asset('mouth_${l.mouth}'),
      if (l.extra != null) _asset('extra_${l.extra}'),
    ],
  ];

  static bool get _isPreloaded => _allAssets.every(_loaded.contains);

  /// Loads every layer into the flutter_svg cache so Chanchi shows up whole
  /// on its first frame. Safe to call more than once; call it at startup.
  static Future<void> preload() async {
    await Future.wait([
      for (final asset in _allAssets.toSet())
        () async {
          final loader = SvgAssetLoader(asset);
          await svg.cache.putIfAbsent(
            loader.cacheKey(null),
            () => loader.loadBytes(null),
          );
          _loaded.add(asset);
        }(),
    ]);
  }

  @override
  State<ChanchiMascot> createState() => _ChanchiMascotState();
}

class _ChanchiMascotState extends State<ChanchiMascot>
    with TickerProviderStateMixin {
  static const _extraDelay = Duration(milliseconds: 300);

  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: BrandDurations.chanchiShort,
  );
  late final AnimationController _extra = AnimationController(
    vsync: this,
    duration: _extraDelay + BrandDurations.chanchiLong,
  );
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );

  final _random = math.Random();
  Timer? _blinkTimer;
  bool _ready = false;
  bool _motionStarted = false;

  bool get _moves =>
      widget.animate &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void initState() {
    super.initState();
    if (ChanchiMascot._isPreloaded) {
      _ready = true;
    } else {
      unawaited(
        ChanchiMascot.preload().then((_) {
          if (mounted) setState(() => _ready = true);
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(ChanchiMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.animate != widget.animate) {
      _motionStarted = false;
      _syncMotion();
    }
  }

  void _syncMotion() {
    if (!_ready || !mounted) return;

    if (!_moves) {
      _blinkTimer?.cancel();
      _hop.stop();
      _extra.stop();
      return;
    }
    if (_motionStarted) return;
    _motionStarted = true;

    unawaited(_hop.forward(from: 0));
    unawaited(_extra.forward(from: 0));
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    if (!_moves || !_moods[widget.mood]!.blinks) return;

    _blinkTimer = Timer(
      Duration(milliseconds: 3500 + _random.nextInt(1500)),
      () async {
        if (!mounted || !_moves) return;
        await _blink.forward(from: 0);
        if (mounted) _scheduleBlink();
      },
    );
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _hop.dispose();
    _extra.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size;
    final height = width * _viewBoxHeight / _viewBoxWidth;

    if (!_ready) return SizedBox(width: width, height: height);

    // Start as soon as the layers are ready (didChangeDependencies ran before).
    if (!_motionStarted && _moves) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncMotion());
    }

    final layers = _moods[widget.mood]!;
    final animating = _moves;
    final unit = width / _viewBoxWidth;

    Widget layer(String name) =>
        SvgPicture(SvgAssetLoader(_asset(name)), width: width, height: height);

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: width,
          height: height,
          child: AnimatedBuilder(
            animation: Listenable.merge([_hop, _extra, _blink]),
            builder: (context, _) {
              final pose = animating
                  ? _hopPose.transform(_hop.value)
                  : _Pose.rest;

              Widget eyes = layer('eyes_${layers.eyes}');
              if (layers.blinks && animating) {
                // 1 -> 0.1 -> 1 over the 120 ms of the controller.
                final v = _blink.value;
                final scaleY = 1 - 0.9 * math.sin(math.pi * v);
                eyes = Transform.scale(
                  scaleY: scaleY,
                  alignment: const Alignment(0.3, -0.04),
                  child: eyes,
                );
              }

              Widget? extra;
              if (layers.extra != null) {
                extra = _buildExtra(
                  layer('extra_${layers.extra}'),
                  unit,
                  animating ? _extraProgress(_extra.value) : null,
                );
              }

              return Transform.translate(
                offset: Offset(0, pose.dy * height),
                child: Transform.scale(
                  scaleX: pose.sx,
                  scaleY: pose.sy,
                  alignment: const Alignment(0, 0.9),
                  child: Stack(
                    children: [
                      layer('body'),
                      eyes,
                      layer('mouth_${layers.mouth}'),
                      ?extra,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 0..1 progress of the extra after its delay.
  double _extraProgress(double controllerValue) {
    final total = _extraDelay + BrandDurations.chanchiLong;
    final start = _extraDelay.inMicroseconds / total.inMicroseconds;
    return ((controllerValue - start) / (1 - start)).clamp(0.0, 1.0);
  }

  /// [progress] is null when the mascot is drawn still: the extra then sits
  /// where the SVG puts it.
  Widget _buildExtra(Widget child, double unit, double? progress) {
    if (progress == null) return child;

    switch (widget.mood) {
      case ChanchiMood.happy:
        // The coin falls into the slot and shrinks out.
        final fall = Curves.easeInCubic.transform(progress);
        return Opacity(
          opacity:
              (1 -
              Curves.easeIn.transform(
                ((progress - 0.7) / 0.3).clamp(0.0, 1.0),
              )),
          child: Transform.translate(
            offset: Offset(0, 26 * unit * fall),
            child: Transform.scale(
              scale: 1 - 0.45 * fall,
              alignment: const Alignment(-0.025, -0.65),
              child: child,
            ),
          ),
        );
      case ChanchiMood.thinking:
        // Three heartbeats, ending at rest.
        final beat = math.sin(math.pi * ((progress * 3) % 1));
        return Transform.scale(
          scale: 1 + 0.14 * (progress >= 1 ? 0 : beat),
          alignment: const Alignment(0.6, -0.5),
          child: child,
        );
      case ChanchiMood.sleepy:
        final rise = Curves.easeOutCubic.transform(progress);
        return Opacity(
          opacity: rise,
          child: Transform.translate(
            offset: Offset(0, 8 * unit * (1 - rise)),
            child: child,
          ),
        );
      case ChanchiMood.worried:
        final slide = Curves.easeInCubic.transform(progress);
        return Opacity(
          opacity:
              1 -
              Curves.easeIn.transform(((progress - 0.5) / 0.5).clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: Offset(0, 12 * unit * slide),
            child: child,
          ),
        );
      case ChanchiMood.idle:
        return child;
    }
  }
}

/// Squash and stretch: vertical offset (fraction of the height) and scales.
class _Pose {
  const _Pose(this.dy, this.sx, this.sy);

  static const rest = _Pose(0, 1, 1);

  final double dy;
  final double sx;
  final double sy;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
    a.dy + (b.dy - a.dy) * t,
    a.sx + (b.sx - a.sx) * t,
    a.sy + (b.sy - a.sy) * t,
  );
}

class _PoseTween extends Tween<_Pose> {
  _PoseTween(_Pose begin, _Pose end) : super(begin: begin, end: end);

  @override
  _Pose lerp(double t) => _Pose.lerp(begin!, end!, t);
}

final _hopPose = TweenSequence<_Pose>([
  // Crouch.
  TweenSequenceItem(
    tween: _PoseTween(
      _Pose.rest,
      const _Pose(0, 1.08, 0.9),
    ).chain(CurveTween(curve: Curves.easeOut)),
    weight: 20,
  ),
  // Stretch up.
  TweenSequenceItem(
    tween: _PoseTween(
      const _Pose(0, 1.08, 0.9),
      const _Pose(-0.14, 0.94, 1.08),
    ).chain(CurveTween(curve: BrandCurves.enter)),
    weight: 30,
  ),
  // Land.
  TweenSequenceItem(
    tween: _PoseTween(
      const _Pose(-0.14, 0.94, 1.08),
      const _Pose(0, 1.08, 0.92),
    ).chain(CurveTween(curve: Curves.easeIn)),
    weight: 25,
  ),
  // Settle.
  TweenSequenceItem(
    tween: _PoseTween(
      const _Pose(0, 1.08, 0.92),
      _Pose.rest,
    ).chain(CurveTween(curve: BrandCurves.bounce)),
    weight: 25,
  ),
]);
