import 'dart:math';
import 'package:flutter/material.dart';

/// 雪花飘落动画效果
///
/// 轻量级实现，使用少量雪花粒子避免性能问题
class SnowfallEffect extends StatefulWidget {
  final Widget child;
  final int snowflakeCount;
  final bool enabled;

  const SnowfallEffect({
    super.key,
    required this.child,
    this.snowflakeCount = 30,
    this.enabled = true,
  });

  @override
  State<SnowfallEffect> createState() => _SnowfallEffectState();
}

class _SnowfallEffectState extends State<SnowfallEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Snowflake> _snowflakes;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _snowflakes = List.generate(
      widget.snowflakeCount,
      (_) => _createSnowflake(),
    );
  }

  Snowflake _createSnowflake([double? startY]) {
    return Snowflake(
      x: _random.nextDouble(),
      y: startY ?? _random.nextDouble(),
      size: _random.nextDouble() * 3 + 2,
      speed: _random.nextDouble() * 0.3 + 0.1,
      wobble: _random.nextDouble() * 0.02,
      wobbleSpeed: _random.nextDouble() * 2 + 1,
      opacity: _random.nextDouble() * 0.5 + 0.3,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: SnowfallPainter(
                    snowflakes: _snowflakes,
                    time: DateTime.now().millisecondsSinceEpoch / 1000.0,
                    onUpdate: (index) {
                      // 雪花落到底部后重置到顶部
                      if (_snowflakes[index].y > 1.0) {
                        _snowflakes[index] = _createSnowflake(-0.05);
                      } else {
                        _snowflakes[index].y +=
                            _snowflakes[index].speed * 0.016;
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 单个雪花的数据
class Snowflake {
  double x;
  double y;
  final double size;
  final double speed;
  final double wobble;
  final double wobbleSpeed;
  final double opacity;

  Snowflake({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.wobble,
    required this.wobbleSpeed,
    required this.opacity,
  });
}

/// 雪花绘制器
class SnowfallPainter extends CustomPainter {
  final List<Snowflake> snowflakes;
  final double time;
  final void Function(int index)? onUpdate;

  SnowfallPainter({
    required this.snowflakes,
    required this.time,
    this.onUpdate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < snowflakes.length; i++) {
      final flake = snowflakes[i];

      // 计算水平摇摆
      final wobbleOffset = sin(time * flake.wobbleSpeed + i) * flake.wobble;
      final x = (flake.x + wobbleOffset) * size.width;
      final y = flake.y * size.height;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: flake.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), flake.size, paint);

      // 触发位置更新
      onUpdate?.call(i);
    }
  }

  @override
  bool shouldRepaint(SnowfallPainter oldDelegate) => true;
}

/// 圣诞徽章组件
class ChristmasBadge extends StatelessWidget {
  final double size;

  const ChristmasBadge({
    super.key,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(size * 0.2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFC41E3A),
            const Color(0xFF8B0000),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC41E3A).withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '🎄',
        style: TextStyle(fontSize: size * 0.6),
      ),
    );
  }
}

/// 圣诞灯带组件
class ChristmasLights extends StatefulWidget {
  final double height;

  const ChristmasLights({
    super.key,
    this.height = 20,
  });

  @override
  State<ChristmasLights> createState() => _ChristmasLightsState();
}

class _ChristmasLightsState extends State<ChristmasLights>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _LightsPainter(
              animationValue: _controller.value,
              lightSize: widget.height * 0.4,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _LightsPainter extends CustomPainter {
  final double animationValue;
  final double lightSize;

  static const _colors = [
    Color(0xFFFF0000), // 红
    Color(0xFF00FF00), // 绿
    Color(0xFFFFD700), // 金
    Color(0xFF0080FF), // 蓝
    Color(0xFFFF69B4), // 粉
  ];

  _LightsPainter({
    required this.animationValue,
    required this.lightSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = lightSize * 2.5;
    final lightCount = (size.width / spacing).ceil() + 1;
    final wireY = size.height * 0.3;

    // 画电线
    final wirePaint = Paint()
      ..color = const Color(0xFF2D5016)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final wirePath = Path();
    wirePath.moveTo(0, wireY);

    for (int i = 0; i < lightCount; i++) {
      final x = i * spacing;
      final nextX = (i + 1) * spacing;
      final midX = (x + nextX) / 2;
      // 画波浪线
      wirePath.quadraticBezierTo(midX, wireY + 8, nextX, wireY);
    }
    canvas.drawPath(wirePath, wirePaint);

    // 画灯泡
    for (int i = 0; i < lightCount; i++) {
      final x = i * spacing + spacing / 2;
      final y = wireY + 8;
      final color = _colors[i % _colors.length];

      // 交替闪烁效果
      final brightness = (i % 2 == 0) ? animationValue : (1 - animationValue);
      final glowOpacity = 0.3 + brightness * 0.5;

      // 发光效果
      final glowPaint = Paint()
        ..color = color.withValues(alpha: glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(x, y), lightSize * 0.8, glowPaint);

      // 灯泡本体
      final bulbPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), lightSize * 0.5, bulbPaint);

      // 高光
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(x - lightSize * 0.15, y - lightSize * 0.15),
        lightSize * 0.15,
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LightsPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

/// 圣诞帽组件
class ChristmasHat extends StatelessWidget {
  final double width;

  const ChristmasHat({
    super.key,
    this.width = 50,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 0.8,
      child: CustomPaint(
        painter: _ChristmasHatPainter(),
      ),
    );
  }
}

class _ChristmasHatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 红色帽子主体（三角形）
    final hatPath = Path();
    hatPath.moveTo(width * 0.5, 0); // 顶点
    hatPath.lineTo(width * 0.05, height * 0.75); // 左下
    hatPath.quadraticBezierTo(
        width * 0.5, height * 0.65, width * 0.95, height * 0.75); // 底部弧线
    hatPath.close();

    final hatPaint = Paint()
      ..color = const Color(0xFFD42426)
      ..style = PaintingStyle.fill;
    canvas.drawPath(hatPath, hatPaint);

    // 白色毛边
    final furPath = Path();
    furPath.moveTo(0, height * 0.75);
    furPath.quadraticBezierTo(width * 0.5, height * 0.6, width, height * 0.75);
    furPath.lineTo(width, height);
    furPath.quadraticBezierTo(width * 0.5, height * 0.85, 0, height);
    furPath.close();

    final furPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(furPath, furPaint);

    // 毛边纹理（小圆点）
    final dotPaint = Paint()
      ..color = const Color(0xFFF5F5F5)
      ..style = PaintingStyle.fill;
    for (double x = width * 0.1; x < width * 0.9; x += width * 0.15) {
      canvas.drawCircle(Offset(x, height * 0.88), width * 0.03, dotPaint);
    }

    // 顶部白色绒球
    final pompomPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(width * 0.5, height * 0.08), width * 0.12, pompomPaint);

    // 绒球阴影
    final pompomShadow = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(width * 0.52, height * 0.1), width * 0.06, pompomShadow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
