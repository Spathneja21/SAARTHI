import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A retro split-flap (airport departure board) style clock: dark rounded
/// cards for hour/minute, each split by a hinge line, that mechanically
/// "flip" — the old top half falls away and a new top half falls into place
/// — whenever their value changes.
class FlipClock extends StatelessWidget {
  const FlipClock({
    super.key,
    required this.hourText,
    required this.minuteText,
    this.periodText,
    this.digitHeight = 110,
    this.backgroundColor = const Color(0xFF17181C),
    this.textColor = const Color(0xFFD8D8D8),
  });

  final String hourText;
  final String minuteText;
  final String? periodText;
  final double digitHeight;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final cardWidth = digitHeight * 0.98;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FlipUnit(
          value: hourText,
          label: periodText,
          height: digitHeight,
          width: cardWidth,
          background: backgroundColor,
          textColor: textColor,
        ),
        SizedBox(width: digitHeight * 0.14),
        _FlipUnit(
          value: minuteText,
          height: digitHeight,
          width: cardWidth,
          background: backgroundColor,
          textColor: textColor,
        ),
      ],
    );
  }
}

class _FlipUnit extends StatefulWidget {
  const _FlipUnit({
    required this.value,
    required this.height,
    required this.width,
    required this.background,
    required this.textColor,
    this.label,
  });

  final String value;
  final String? label;
  final double height;
  final double width;
  final Color background;
  final Color textColor;

  @override
  State<_FlipUnit> createState() => _FlipUnitState();
}

class _FlipUnitState extends State<_FlipUnit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late String _oldValue;
  late String _newValue;

  @override
  void initState() {
    super.initState();
    _oldValue = widget.value;
    _newValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void didUpdateWidget(covariant _FlipUnit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _oldValue = oldWidget.value;
      _newValue = widget.value;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: widget.height * 0.56,
      fontWeight: FontWeight.w700,
      color: widget.textColor,
      height: 1.0,
    );
    final radius = BorderRadius.circular(widget.height * 0.1);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final settledTop = t < 0.5 ? _oldValue : _newValue;

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: widget.background,
                  borderRadius: radius,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: _HalfDigit(
                        text: settledTop,
                        style: textStyle,
                        top: true,
                        fullHeight: widget.height,
                      ),
                    ),
                    Expanded(
                      child: _HalfDigit(
                        text: _newValue,
                        style: textStyle,
                        top: false,
                        fullHeight: widget.height,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: widget.height / 2 - 0.5,
                child: Container(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
              if (t > 0 && t < 1)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: widget.height / 2,
                  child: _FlipPanel(
                    text: t < 0.5 ? _oldValue : _newValue,
                    style: textStyle,
                    background: widget.background,
                    progress: t < 0.5 ? (t / 0.5) : ((t - 0.5) / 0.5),
                    incoming: t >= 0.5,
                    fullHeight: widget.height,
                  ),
                ),
              if (widget.label != null)
                Positioned(
                  top: widget.height * 0.07,
                  left: widget.width * 0.09,
                  child: Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: widget.height * 0.12,
                      fontWeight: FontWeight.w700,
                      color: widget.textColor.withValues(alpha: 0.85),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HalfDigit extends StatelessWidget {
  const _HalfDigit({
    required this.text,
    required this.style,
    required this.top,
    required this.fullHeight,
  });

  final String text;
  final TextStyle style;
  final bool top;
  final double fullHeight;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: SizedBox(
          height: fullHeight,
          width: double.infinity,
          child: Text(text, style: style, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// The single rotating leaf mid-flip: [incoming] = false is the outgoing
/// (old) top half folding away (0deg -> 90deg); [incoming] = true is the
/// new top half folding into place (-90deg -> 0deg).
class _FlipPanel extends StatelessWidget {
  const _FlipPanel({
    required this.text,
    required this.style,
    required this.background,
    required this.progress,
    required this.incoming,
    required this.fullHeight,
  });

  final String text;
  final TextStyle style;
  final Color background;
  final double progress;
  final bool incoming;
  final double fullHeight;

  @override
  Widget build(BuildContext context) {
    final angle = incoming
        ? (-math.pi / 2) * (1 - progress)
        : (math.pi / 2) * progress;
    final shade = math.sin(angle.abs()).clamp(0.0, 1.0) * 0.45;

    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0025)
        ..rotateX(angle),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Color.lerp(background, Colors.black, shade),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 0.5,
            child: SizedBox(
              height: fullHeight,
              width: double.infinity,
              child: Text(text, style: style, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
