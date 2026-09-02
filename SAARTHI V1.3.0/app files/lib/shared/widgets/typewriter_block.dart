import 'package:flutter/material.dart';

class TypewriterBlock extends StatefulWidget {
  const TypewriterBlock({
    super.key,
    required this.lines,
    this.lineStyles,
    this.textAlign,
    this.duration = const Duration(milliseconds: 1400),
    this.startDelay = Duration.zero,
    this.curve = Curves.linear,
    this.cursor = false,
    this.cursorChar = '|',
    this.cursorBlinkDuration = const Duration(milliseconds: 550),
    this.cursorAfterComplete = false,
    this.onCompleted,
  });

  final List<String> lines;
  final List<TextStyle?>? lineStyles;
  final TextAlign? textAlign;
  final Duration duration;
  final Duration startDelay;
  final Curve curve;
  final bool cursor;
  final String cursorChar;
  final Duration cursorBlinkDuration;
  final bool cursorAfterComplete;
  final VoidCallback? onCompleted;

  @override
  State<TypewriterBlock> createState() => _TypewriterBlockState();
}

class _TypewriterBlockState extends State<TypewriterBlock>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _animation;
  late AnimationController _cursorController;
  bool _completed = false;
  int _totalSteps = 0;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _initCursor();
    _start();
  }

  @override
  void didUpdateWidget(covariant TypewriterBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines != widget.lines || oldWidget.duration != widget.duration) {
      _controller.dispose();
      _initAnimation();
      _start();
    }
  }

  void _initAnimation() {
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final chars = widget.lines.fold<int>(0, (sum, line) => sum + line.length);
    _totalSteps = chars + (widget.lines.length > 1 ? widget.lines.length - 1 : 0);
    _animation = StepTween(begin: 0, end: _totalSteps).animate(
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

  List<TextSpan> _buildSpans(int count) {
    final spans = <TextSpan>[];
    var remaining = count;
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final style = widget.lineStyles != null && widget.lineStyles!.length > i
          ? widget.lineStyles![i]
          : null;

      if (remaining <= 0) {
        break;
      }

      if (remaining >= line.length) {
        spans.add(TextSpan(text: line, style: style));
        remaining -= line.length;
        if (i < widget.lines.length - 1) {
          if (remaining > 0) {
            spans.add(const TextSpan(text: '\n'));
            remaining -= 1;
          } else {
            break;
          }
        }
      } else {
        spans.add(TextSpan(text: line.substring(0, remaining), style: style));
        remaining = 0;
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final showCursor = widget.cursor && (!_completed || widget.cursorAfterComplete);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final cursorStyle = (widget.lineStyles == null || widget.lineStyles!.isEmpty)
        ? defaultStyle
        : widget.lineStyles!.lastWhere(
            (style) => style?.color != null,
            orElse: () => defaultStyle,
          ) ??
          defaultStyle;
    return AnimatedBuilder(
      animation: Listenable.merge([_animation, _cursorController]),
      builder: (context, child) {
        final count = _animation.value.clamp(0, _totalSteps);
        final spans = _buildSpans(count);
        final cursorOpacity = showCursor ? _cursorController.value : 0.0;
        return RichText(
          textAlign: widget.textAlign ?? TextAlign.start,
          text: TextSpan(
            style: defaultStyle,
            children: [
              ...spans,
              if (showCursor)
                TextSpan(
                  text: widget.cursorChar,
                  style: cursorStyle.copyWith(
                    color: (cursorStyle.color ?? Colors.black)
                        .withValues(alpha: cursorOpacity),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
