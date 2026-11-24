import 'dart:math' as math;
import 'package:flutter/rendering.dart';

/// 绘制虚线及可选终点箭头，用于投掷点到爆点或穿线方位连线
class DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final bool showArrow;
  final double arrowLength;

  DashedLinePainter({
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength = 4,
    this.gapLength = 4,
    this.showArrow = false,
    this.arrowLength = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalLength = (end - start).distance;
    if (totalLength < 1e-3) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final direction = (end - start) / totalLength;

    double currentLength = 0;
    bool draw = true;

    path.moveTo(start.dx, start.dy);

    while (currentLength < totalLength) {
      final segmentLength = draw ? dashLength : gapLength;
      final nextLength =
          (currentLength + segmentLength).clamp(0.0, totalLength);
      final nextPoint = start + direction * nextLength;

      if (draw) {
        path.lineTo(nextPoint.dx, nextPoint.dy);
      } else {
        path.moveTo(nextPoint.dx, nextPoint.dy);
      }

      currentLength = nextLength;
      draw = !draw;
    }

    canvas.drawPath(path, paint);

    if (showArrow && totalLength > 2.0) {
      final angle = math.atan2(direction.dy, direction.dx);
      const spread = 28 * math.pi / 180;
      final wingLength = math.min(arrowLength, totalLength * 0.45);
      final leftWing = Offset(
        end.dx - wingLength * math.cos(angle - spread),
        end.dy - wingLength * math.sin(angle - spread),
      );
      final rightWing = Offset(
        end.dx - wingLength * math.cos(angle + spread),
        end.dy - wingLength * math.sin(angle + spread),
      );
      final arrowPath = Path()
        ..moveTo(leftWing.dx, leftWing.dy)
        ..lineTo(end.dx, end.dy)
        ..lineTo(rightWing.dx, rightWing.dy);
      final arrowPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DashedLinePainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        dashLength != oldDelegate.dashLength ||
        gapLength != oldDelegate.gapLength ||
        showArrow != oldDelegate.showArrow ||
        arrowLength != oldDelegate.arrowLength;
  }
}
