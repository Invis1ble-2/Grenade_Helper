import 'package:flutter/material.dart';
import '../models.dart';

/// 雷达小地图组件 - 以当前道具为中心显示放大的地图区域
class RadarMiniMap extends StatelessWidget {
  final String mapAssetPath;
  final Grenade? currentGrenade;
  final List<Grenade> allGrenades;
  final double width;
  final double height;
  final double zoomLevel;

  const RadarMiniMap({
    super.key,
    required this.mapAssetPath,
    required this.currentGrenade,
    required this.allGrenades,
    this.width = 400, // 更宽
    this.height = 150, // 更矮 - 长方形
    this.zoomLevel = 1.3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
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
            // 地图背景（放大并居中于当前点位）
            _buildZoomedMap(),

            // 其他道具点位
            ..._buildOtherPoints(),

            // 当前道具点位（中心，带动画）
            if (currentGrenade != null)
              Center(
                child: _PulsingDot(color: Colors.orange, size: 14),
              ),

            // 边框装饰
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),

            // 十字准星
            CustomPaint(
              size: Size(width, height),
              painter: _CrosshairPainter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomedMap() {
    if (currentGrenade == null) {
      return Image.asset(
        mapAssetPath,
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[900],
          child: const Center(
            child: Icon(Icons.map, size: 48, color: Colors.grey),
          ),
        ),
      );
    }

    // 计算偏移量使当前点位居中
    final centerX = currentGrenade!.xRatio;
    final centerY = currentGrenade!.yRatio;

    // 使用方形地图尺寸，取宽高中较大者确保覆盖整个容器
    final mapSize = width > height ? width : height;

    // 计算偏移量：让当前点位位于容器中心
    // 地图以容器中心为基准点进行偏移
    final offsetX = (0.5 - centerX) * mapSize * zoomLevel;
    final offsetY = (0.5 - centerY) * mapSize * zoomLevel;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: mapSize * zoomLevel,
          maxHeight: mapSize * zoomLevel,
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: Image.asset(
              mapAssetPath,
              fit: BoxFit.cover,
              width: mapSize * zoomLevel,
              height: mapSize * zoomLevel,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[900],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildOtherPoints() {
    if (currentGrenade == null) return [];

    final centerX = currentGrenade!.xRatio;
    final centerY = currentGrenade!.yRatio;

    // 使用与 _buildZoomedMap 一致的地图尺寸
    final mapSize = width > height ? width : height;

    return allGrenades.where((g) => g.id != currentGrenade!.id).map((g) {
      // 计算相对于当前点的偏移（基于地图坐标系）
      // 其他点相对于当前中心点的位置差，乘以缩放后的地图尺寸
      final relX = (g.xRatio - centerX) * mapSize * zoomLevel;
      final relY = (g.yRatio - centerY) * mapSize * zoomLevel;

      // 转换为容器坐标（以容器中心为原点）
      final screenX = width / 2 + relX;
      final screenY = height / 2 + relY;

      // 如果超出容器可见范围，不显示
      if (screenX < 0 || screenX > width || screenY < 0 || screenY > height) {
        return const SizedBox.shrink();
      }

      return Positioned(
        left: screenX - 4,
        top: screenY - 4,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _getGrenadeColor(g.type).withValues(alpha: 0.7),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), width: 1),
          ),
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
      default:
        return Colors.white;
    }
  }
}

/// 脉冲动画点
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

/// 十字准星绘制器
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
