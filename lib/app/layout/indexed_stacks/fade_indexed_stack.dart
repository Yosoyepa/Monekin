import 'package:flutter/material.dart';
import 'package:monekin/app/layout/indexed_stacks/lazy_indexed_stack.dart';
import 'package:monekin/brand/motion.dart';

class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  final StackFit sizing;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = BrandDurations.page,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.sizing = StackFit.loose,
  });

  @override
  FadeIndexedStackState createState() => FadeIndexedStackState();
}

class FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void initState() {
    _controller.forward();
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = BrandMotion.of(context).reduce;

    return FadeTransition(
      opacity: _controller,
      child: ScaleTransition(
        scale: Tween<double>(begin: reduce ? 1 : 0.98, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: BrandCurves.enter),
        ),
        child: LazyIndexedStack(
          index: widget.index,
          alignment: widget.alignment,
          textDirection: widget.textDirection,
          sizing: widget.sizing,
          children: widget.children,
        ),
      ),
    );
  }
}
