import 'dart:math';

import 'package:flutter/material.dart';

/// A full-bleed, fully opaque backdrop of diagonal wavy color bands that
/// continuously flow past each other — like a stack of liquid strata swept
/// across the canvas. Unlike a translucent overlay, this is meant to be the
/// entire background: every pixel is covered by one band or another.
class FluidMorphBackground extends StatefulWidget {
  const FluidMorphBackground({super.key, this.colors});

  /// Ordered light-to-accent band colors. Defaults to a very light powder-
  /// blue sweep if not provided.
  final List<Color>? colors;

  @override
  State<FluidMorphBackground> createState() => _FluidMorphBackgroundState();
}

class _FluidMorphBackgroundState extends State<FluidMorphBackground> with SingleTickerProviderStateMixin {
  static const List<Color> _defaultColors = [
    Color(0xFFD3E6FA), // palest powder blue
    Color(0xFFBBD8F5), // light blue
    Color(0xFFA3C9F0), // soft blue
    Color(0xFF8BB9EA), // medium blue
    Color(0xFF74AAE4), // sky blue
    Color(0xFF5D9BDE), // deeper accent blue
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors ?? _defaultColors;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _FluidBandsPainter(t: _controller.value, colors: colors),
          );
        },
      ),
    );
  }
}

class _FluidBandsPainter extends CustomPainter {
  _FluidBandsPainter({required this.t, required this.colors});

  final double t;
  final List<Color> colors;

  static const double _rotationRadians = -0.42; // ~-24deg diagonal sweep

  @override
  void paint(Canvas canvas, Size size) {
    // Oversize the working area so the diagonal rotation always fully
    // covers the visible rect, with no corner gaps.
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    final workSize = Size(diagonal, diagonal);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_rotationRadians);
    canvas.translate(-workSize.width / 2, -workSize.height / 2);

    // Band thickness is scaled to the actual viewport (not the oversized
    // rotation canvas) so several bands are visible per screen height,
    // matching a dense diagonal stripe look regardless of device size.
    final spacing = size.height * 0.2;
    final amplitude = spacing * 0.55;
    final margin = spacing * 1.5;
    final usableHeight = workSize.height + margin * 2;
    final bandCount = (usableHeight / spacing).ceil();

    // One boundary curve per band edge (bandCount + 1 of them). Each gets
    // its own pseudo-random frequency, phase, speed and harmonic mix so the
    // flow reads as organic drift rather than one uniform repeating ripple.
    List<double> boundaryAt(double x) {
      final boundaries = <double>[];
      for (var i = 0; i <= bandCount; i++) {
        final baseY = -margin + i * spacing;
        final freq1 = 0.7 + _hash(i, 1.0) * 1.8; // 0.7..2.5
        final freq2 = 1.1 + _hash(i, 2.0) * 2.3; // 1.1..3.4
        final phase1 = _hash(i, 3.0) * 2 * pi;
        final phase2 = _hash(i, 4.0) * 2 * pi;
        final speed1 = (_hash(i, 5.0) - 0.5) * 2.6; // -1.3..1.3
        final speed2 = (_hash(i, 6.0) - 0.5) * 2.2; // -1.1..1.1
        final mix = 0.35 + _hash(i, 7.0) * 0.35; // 0.35..0.7
        final wobble = amplitude *
            (mix * sin(2 * pi * (x / workSize.width) * freq1 + t * 2 * pi * speed1 + phase1) +
                (1 - mix) * sin(2 * pi * (x / workSize.width) * freq2 + t * 2 * pi * speed2 + phase2));
        boundaries.add(baseY + wobble);
      }
      return boundaries;
    }

    const steps = 48;
    final xs = List<double>.generate(steps + 1, (i) => workSize.width * i / steps);
    final columns = xs.map(boundaryAt).toList();

    for (var band = 0; band < bandCount; band++) {
      final path = Path();
      path.moveTo(xs[0], columns[0][band]);
      for (var i = 1; i <= steps; i++) {
        path.lineTo(xs[i], columns[i][band]);
      }
      for (var i = steps; i >= 0; i--) {
        path.lineTo(xs[i], columns[i][band + 1]);
      }
      path.close();

      final paint = Paint()
        ..color = _colorForBand(band)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  /// Deterministic pseudo-random value in [0, 1) for a given boundary index
  /// and salt, so each boundary curve gets its own fixed-but-varied motion
  /// parameters without needing a stored [Random] seed.
  double _hash(int i, double salt) {
    final x = sin(i * 12.9898 + salt * 78.233) * 43758.5453123;
    return x - x.floorToDouble();
  }

  /// Cycles through the palette back-and-forth (0,1,2,…,n-1,n-2,…,1,0,1,…)
  /// so a band count larger than the palette never produces a hard seam.
  Color _colorForBand(int index) {
    final n = colors.length;
    if (n == 1) {
      return colors[0];
    }
    final period = 2 * (n - 1);
    final m = index % period;
    final pos = m < n ? m : period - m;
    return colors[pos];
  }

  @override
  bool shouldRepaint(covariant _FluidBandsPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.colors != colors;
  }
}
