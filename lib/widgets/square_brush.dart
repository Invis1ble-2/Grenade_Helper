import 'dart:ui';

/// 解析笔画是否为方形笔刷（brushShape/b == 1）
bool parseSquareBrush(Map stroke) {
  final raw = stroke['brushShape'] ?? stroke['b'];
  return raw is num && raw.toInt() == 1;
}

/// 绘制轴对齐方形笔刷笔画（points 为屏幕坐标）
void paintSquareBrush(
    Canvas canvas, List<Offset> points, double side, Paint paint) {
  if (points.isEmpty) return;
  final h = side / 2;
  final fill = Paint()
    ..color = paint.color
    ..blendMode = paint.blendMode
    ..isAntiAlias = true;
  final diagonals = [Offset(h, h), Offset(h, -h)];
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    canvas.drawRect(Rect.fromCenter(center: p, width: side, height: side), fill);
    if (i == 0) continue;
    final a = points[i - 1];
    // 两条对角线沿线段扫过的平行四边形，与两端方块合并即为完整扫掠区域
    for (final d in diagonals) {
      canvas.drawPath(
          Path()..addPolygon([a - d, a + d, p + d, p - d], true), fill);
    }
  }
}
