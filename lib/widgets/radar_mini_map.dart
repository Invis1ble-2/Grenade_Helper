import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models.dart';
import '../services/grenade_cluster_service.dart';
import 'path_image_provider.dart';

/// 雷达小地图
class RadarMiniMap extends StatefulWidget {
  final String mapAssetPath;
  final Grenade? currentGrenade;
  final List<Grenade> allGrenades;
  final double width;
  final double height;
  final double zoomLevel;

  // 准星位置
  final double crosshairX;
  final double crosshairY;
  final bool isSnapped;

  const RadarMiniMap({
    super.key,
    required this.mapAssetPath,
    required this.currentGrenade,
    required this.allGrenades,
    required this.crosshairX,
    required this.crosshairY,
    required this.isSnapped,
    this.width = 400,
    this.height = 150,
    this.zoomLevel = 1.3,
  });

  @override
  State<RadarMiniMap> createState() => _RadarMiniMapState();
}

class _RadarMiniMapState extends State<RadarMiniMap>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // 动画位置
  double _animatedX = 0.5;
  double _animatedY = 0.5;

  // 平滑追踪速度（0.0-1.0，值越大追踪越快）
  static const double _smoothFactor = 0.35;

  @override
  void initState() {
    super.initState();
    _animatedX = widget.crosshairX;
    _animatedY = widget.crosshairY;

    // 驱动更新
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // 计算差距
    final dx = widget.crosshairX - _animatedX;
    final dy = widget.crosshairY - _animatedY;

    // 到达目标
    if (dx.abs() < 0.001 && dy.abs() < 0.001) {
      if (_animatedX != widget.crosshairX || _animatedY != widget.crosshairY) {
        setState(() {
          _animatedX = widget.crosshairX;
          _animatedY = widget.crosshairY;
        });
      }
      return;
    }

    // 平滑插值
    setState(() {
      _animatedX += dx * _smoothFactor;
      _animatedY += dy * _smoothFactor;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 检查动画完成
    final dx = (widget.crosshairX - _animatedX).abs();
    final dy = (widget.crosshairY - _animatedY).abs();
    final animationSettled = dx < 0.005 && dy < 0.005;

    // 显示脉冲点
    final showPulsingDot = widget.isSnapped && animationSettled;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // 地图背景
            _buildZoomedMap(_animatedX, _animatedY),

            // 其他点位
            ..._buildOtherPoints(_animatedX, _animatedY),

            // 中心吸附点
            if (showPulsingDot)
              const Center(
                child: _PulsingDot(color: Colors.orange, size: 14),
              ),

            // 边框装饰
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.isSnapped
                      ? Colors.orange.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),

            // 十字准星
            CustomPaint(
              size: Size(widget.width, widget.height),
              painter: _CrosshairPainter(isSnapped: widget.isSnapped),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomedMap(double centerX, double centerY) {
    // 地图尺寸
    final mapSize = widget.width > widget.height ? widget.width : widget.height;

    // 计算偏移
    final offsetX = (0.5 - centerX) * mapSize * widget.zoomLevel;
    final offsetY = (0.5 - centerY) * mapSize * widget.zoomLevel;
    final mapImageProvider = imageProviderFromPath(widget.mapAssetPath);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: mapSize * widget.zoomLevel,
          maxHeight: mapSize * widget.zoomLevel,
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: mapImageProvider == null
                ? Container(color: Colors.grey[900])
                : Image(
                    image: mapImageProvider,
                    fit: BoxFit.cover,
                    width: mapSize * widget.zoomLevel,
                    height: mapSize * widget.zoomLevel,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[900],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildOtherPoints(double centerX, double centerY) {
    // 地图尺寸
    final mapSize = widget.width > widget.height ? widget.width : widget.height;

    // 聚合点位
    var clusters = GrenadeClusterService.buildClusters(widget.allGrenades);

    // 过滤当前
    if (widget.isSnapped && widget.currentGrenade != null) {
      clusters = clusters.where((cluster) {
        return !cluster.containsGrenade(widget.currentGrenade!.id);
      }).toList();
    }

    return clusters.map((cluster) {
      // 确定中心
      final centerGrenade = cluster.anchor;
      final relX =
          (centerGrenade.xRatio - centerX) * mapSize * widget.zoomLevel;
      final relY =
          (centerGrenade.yRatio - centerY) * mapSize * widget.zoomLevel;

      // 转换坐标
      final screenX = widget.width / 2 + relX;
      final screenY = widget.height / 2 + relY;

      // 超出隐藏
      if (screenX < -10 ||
          screenX > widget.width + 10 ||
          screenY < -10 ||
          screenY > widget.height + 10) {
        return const SizedBox.shrink();
      }

      final count = cluster.members.length;
      // 确定颜色
      final types = cluster.members.map((g) => g.type).toSet();
      final color = types.length == 1
          ? _getGrenadeColor(types.first)
          : Colors.white.withValues(alpha: 0.8);

      final size = count > 1 ? 14.0 : 8.0;

      return Positioned(
        left: screenX - size / 2,
        top: screenY - size / 2,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.6), width: 1),
            boxShadow: count > 1
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: count > 1
              ? Center(
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null,
        ),
      );
    }).toList();
  }

  Color _getGrenadeColor(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return Colors.grey;
      case GrenadeType.flash:
        return Colors.yellow;
      case GrenadeType.molotov:
        return Colors.red;
      case GrenadeType.he:
        return Colors.green;
      case GrenadeType.wallbang:
        return Colors.cyan;
      default:
        return Colors.white;
    }
  }
}

/// 准星绘制
class _CrosshairPainter extends CustomPainter {
  final bool isSnapped;

  _CrosshairPainter({this.isSnapped = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isSnapped
          ? Colors.orange.withValues(alpha: 0.4)
          : Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const gap = 20.0;
    const length = 10.0;

    // 上
    canvas.drawLine(
      Offset(centerX, centerY - gap - length),
      Offset(centerX, centerY - gap),
      paint,
    );
    // 下
    canvas.drawLine(
      Offset(centerX, centerY + gap),
      Offset(centerX, centerY + gap + length),
      paint,
    );
    // 左
    canvas.drawLine(
      Offset(centerX - gap - length, centerY),
      Offset(centerX - gap, centerY),
      paint,
    );
    // 右
    canvas.drawLine(
      Offset(centerX + gap, centerY),
      Offset(centerX + gap + length, centerY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.isSnapped != isSnapped;
}

/// 脉冲动画
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _PulsingDot({required this.color, required this.size});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size * _animation.value,
          height: widget.size * _animation.value,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5),
                blurRadius: 8 * _animation.value,
                spreadRadius: 2 * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
