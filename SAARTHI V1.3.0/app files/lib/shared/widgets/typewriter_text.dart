import 'package:flutter/material.dart';

class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 1200),
    this.startDelay = Duration.zero,
    this.curve = Curves.linear,
    this.lineByLine = false,
    this.cursor = false,
    this.cursorChar = '|',
    this.cursorBlinkDuration = const Duration(milliseconds: 550),
    this.cursorAfterComplete = false,
    this.onCompleted,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;
  final Duration startDelay;
  final Curve curve;
  final bool lineByLine;
  final bool cursor;
  final String cursorChar;
  final Duration cursorBlinkDuration;
  final bool cursorAfterComplete;
  final VoidCallback? onCompleted;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
  with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _animation;
  late AnimationController _cursorController;
  late List<String> _lines;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _initCursor();
    _start();
  }

  @override
  void didUpdateWidget(covariant TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.duration != widget.duration ||
        oldWidget.lineByLine != widget.lineByLine) {
      _controller.dispose();
      _initAnimation();
      _start();
    }
  }

  void _initAnimation() {
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _lines = widget.text.split('\n');
    final useLineByLine = widget.lineByLine && _lines.length > 1;
    final maxSteps = useLineByLine ? _lines.length : widget.text.length;
    _animation = StepTween(begin: 0, end: maxSteps).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    _completed = false;
    _controller.addStatusListener(_handleStatus);
  }

  void _initCursor() {
    _cursorController = AnimationController(
      vsync: this,
      duration: widget.cursorBlinkDuration,
    )..repeat(reverse: true);
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _completed = true;
      widget.onCompleted?.call();
    }
  }

  Future<void> _start() async {
    if (widget.startDelay != Duration.zero) {
      await Future<void>.delayed(widget.startDelay);
      if (!mounted) {
        return;
      }
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCursor = widget.cursor && (!_completed || widget.cursorAfterComplete);
    return AnimatedBuilder(
      animation: Listenable.merge([_animation, _cursorController]),
      builder: (context, child) {
        final count = _animation.value;
        final useLineByLine = widget.lineByLine && _lines.length > 1;
        final visible = useLineByLine
          ? _lines.take(count).join('\n')
          : widget.text.substring(0, count.clamp(0, widget.text.length));
        final cursorOpacity = showCursor ? _cursorController.value : 0.0;
        return RichText(
          textAlign: widget.textAlign ?? TextAlign.start,
          text: TextSpan(
            style: widget.style,
            children: [
              TextSpan(text: visible),
              if (showCursor)
                TextSpan(
                  text: widget.cursorChar,
                  style: (widget.style ?? const TextStyle())
                      .copyWith(color: (widget.style?.color ?? Colors.black).withValues(alpha: cursorOpacity)),
                ),
            ],
          ),
        );
      },
    );
  }
}
