import 'dart:math';

import 'package:flutter/material.dart';

/// A continuously morphing four-point sparkle/star shape: four petals meeting
/// at a sharp center point, each tapering to a true sharp tip, animating
/// between thin/needle-like and slightly fuller silhouettes as [progress]
/// loops from 0 to 1.
class MorphingSparkle extends StatelessWidget {
  const MorphingSparkle({super.key, required this.progress, required this.color, required this.size});

  final double progress;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MorphingSparklePainter(progress: progress, color: color),
    );
  }
}

class _MorphingSparklePainter extends CustomPainter {
  _MorphingSparklePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * pi;
    final bulge = 0.11 + 0.09 * (0.5 + 0.5 * sin(t));
    final rotation = (pi / 10) * sin(t * 0.5);
    final squashX = 1.0 + 0.2 * sin(2 * t + pi / 4);
    final squashY = 1.0 + 0.2 * sin(2 * t + 3 * pi / 4);
    final tipLength = size.shortestSide / 2;
    final paint = Paint()..color = color;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation);
    canvas.scale(squashX, squashY);

    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * pi / 2);
      canvas.drawPath(_petalPath(tipLength, bulge), paint);
      canvas.restore();
    }

    canvas.restore();
  }

  Path _petalPath(double tipLength, double bulge) {
    final cp1 = Offset(tipLength * 0.34, tipLength * bulge);
    final cp2 = Offset(tipLength * 0.8, tipLength * bulge * 0.3);
    final tip = Offset(tipLength, 0);
    return Path()
      ..moveTo(0, 0)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, tip.dx, tip.dy)
      ..cubicTo(cp2.dx, -cp2.dy, cp1.dx, -cp1.dy, 0, 0)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _MorphingSparklePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
