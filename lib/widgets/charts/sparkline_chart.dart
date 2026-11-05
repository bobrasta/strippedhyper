import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Tiny sparkline drawn with CustomPainter — mirrors KpiSparkLine from screen1-dashboard.jsx
class SparklineChart extends StatelessWidget {
  const SparklineChart({
    super.key,
    required this.values,
    required this.color,
    this.width = 96,
    this.height = 32,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _SparkPainter(values, color)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final range = (max - min).abs() < 0.001 ? 1.0 : max - min;

    double x(int i) => (i / (values.length - 1)) * size.width;
    double y(double v) => size.height - ((v - min) / range) * size.height;

    final pts = List.generate(values.length, (i) => Offset(x(i), y(values[i])));

    // Area fill
    final areaPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0), Offset(0, size.height),
        [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
      )
      ..style = PaintingStyle.fill;

    final areaPath = Path()..moveTo(0, size.height);
    for (final p in pts) { areaPath.lineTo(p.dx, p.dy); }
    areaPath..lineTo(size.width, size.height)..close();
    canvas.drawPath(areaPath, areaPaint);

    // Line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final linePath = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) { linePath.lineTo(pts[i].dx, pts[i].dy); }
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}
