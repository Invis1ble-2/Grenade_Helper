import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import '../models.dart';
import '../providers.dart';

/// 爆点选择页面
/// 允许用户在地图上点击选择爆点位置
class ImpactPointPickerScreen extends ConsumerStatefulWidget {
  final int grenadeId;
  final double? initialX; // 当前爆点 X（如果已设置）
  final double? initialY; // 当前爆点 Y（如果已设置）
  final double throwX; // 投掷点 X（用于显示参考）
  final double throwY; // 投掷点 Y
  final int layerId; // 所在楼层

  const ImpactPointPickerScreen({
    super.key,
    required this.grenadeId,
    this.initialX,
    this.initialY,
    required this.throwX,
    required this.throwY,
    required this.layerId,
  });

  @override
  ConsumerState<ImpactPointPickerScreen> createState() =>
      _ImpactPointPickerScreenState();
}

class _ImpactPointPickerScreenState
    extends ConsumerState<ImpactPointPickerScreen> {
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey();

  // 选中的爆点位置
  double? _selectedX;
  double? _selectedY;

  // 当前楼层信息
  MapLayer? _layer;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    _selectedX = widget.initialX;
    _selectedY = widget.initialY;
    _loadLayer();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  Future<void> _loadLayer() async {
    final isar = ref.read(isarProvider);
    _layer = await isar.mapLayers.get(widget.layerId);
    if (mounted) setState(() {});
  }

  /// 计算 BoxFit.contain 模式下正方形图片的实际显示区域
  ({double width, double height, double offsetX, double offsetY})
      _getImageBounds(double containerWidth, double containerHeight) {
    const double imageAspectRatio = 1.0;
    final double containerAspectRatio = containerWidth / containerHeight;

    if (containerAspectRatio > imageAspectRatio) {
      final imageHeight = containerHeight;
      final imageWidth = containerHeight * imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: (containerWidth - imageWidth) / 2,
        offsetY: 0.0,
      );
    } else {
      final imageWidth = containerWidth;
      final imageHeight = containerWidth / imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: 0.0,
        offsetY: (containerHeight - imageHeight) / 2,
      );
    }
  }

  /// 将全局坐标转换为图片坐标比例 (0-1)
  Offset? _getLocalPosition(Offset globalPosition) {
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final localPosition = box.globalToLocal(globalPosition);
    final size = box.size;
    final bounds = _getImageBounds(size.width, size.height);

    final tapX = localPosition.dx - bounds.offsetX;
    final tapY = localPosition.dy - bounds.offsetY;

    return Offset(tapX / bounds.width, tapY / bounds.height);
  }

  void _handleTap(TapUpDetails details) {
    final localRatio = _getLocalPosition(details.globalPosition);
    if (localRatio == null) return;

    // 边界检查
    if (localRatio.dx < 0 ||
        localRatio.dx > 1 ||
        localRatio.dy < 0 ||
        localRatio.dy > 1) {
      return;
    }

    setState(() {
      _selectedX = localRatio.dx;
      _selectedY = localRatio.dy;
    });
  }

  void _confirmSelection() {
    if (_selectedX != null && _selectedY != null) {
      Navigator.pop(context, Offset(_selectedX!, _selectedY!));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击地图选择爆点位置')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_layer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D21),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('选择爆点位置'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _confirmSelection,
            child: const Text(
              '确认',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imageBounds =
                    _getImageBounds(constraints.maxWidth, constraints.maxHeight);

                return PhotoView.customChild(
                  controller: _photoViewController,
                  backgroundDecoration:
                      const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  initialScale: PhotoViewComputedScale.contained,
                  child: StreamBuilder<PhotoViewControllerValue>(
                    stream: _photoViewController.outputStateStream,
                    builder: (context, snapshot) {
                      final double scale = snapshot.data?.scale ?? 1.0;
                      // 标记反向缩放：地图放大时标记缩小，地图缩小时标记放大
                      final double markerScale = 1.0 / scale;
                      
                      return GestureDetector(
                        onTapUp: _handleTap,
                        child: Stack(
                          key: _stackKey,
                          children: [
                            // 地图图片
                            Image.asset(
                              _layer!.assetPath,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              fit: BoxFit.contain,
                            ),
                            // 投掷点标记（不可移动）
                            _buildThrowPointMarker(imageBounds, markerScale),
                            // 连线（如果已选择爆点）
                            if (_selectedX != null && _selectedY != null)
                              _buildConnectionLine(imageBounds),
                            // 爆点标记（可点击选择）
                            if (_selectedX != null && _selectedY != null)
                              _buildImpactMarker(imageBounds, markerScale),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // 底部提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1A1D21),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '投掷点',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 24),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.purpleAccent, width: 2),
                      ),
                      child: const Icon(Icons.close,
                          size: 8, color: Colors.purpleAccent),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '爆点',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedX != null
                      ? '已选择爆点，点击确认保存'
                      : '💡 点击地图任意位置设置爆点',
                  style: TextStyle(
                    color: _selectedX != null
                        ? Colors.greenAccent
                        : Colors.grey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建投掷点标记
  Widget _buildThrowPointMarker(
      ({double width, double height, double offsetX, double offsetY})
          imageBounds,
      double markerScale) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + widget.throwX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + widget.throwY * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.place, size: 12, color: Colors.white),
        ),
      ),
    );
  }

  /// 构建爆点标记
  Widget _buildImpactMarker(
      ({double width, double height, double offsetX, double offsetY})
          imageBounds,
      double markerScale) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + _selectedX! * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + _selectedY! * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.purpleAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withValues(alpha: 0.4),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 12, color: Colors.purpleAccent),
        ),
      ),
    );
  }

  /// 构建连线
  Widget _buildConnectionLine(
      ({double width, double height, double offsetX, double offsetY})
          imageBounds) {
    final startX = imageBounds.offsetX + widget.throwX * imageBounds.width;
    final startY = imageBounds.offsetY + widget.throwY * imageBounds.height;
    final endX = imageBounds.offsetX + _selectedX! * imageBounds.width;
    final endY = imageBounds.offsetY + _selectedY! * imageBounds.height;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DashedLinePainter(
            start: Offset(startX, startY),
            end: Offset(endX, endY),
            color: Colors.purpleAccent.withValues(alpha: 0.7),
            strokeWidth: 2,
            dashLength: 5,
            gapLength: 5,
          ),
        ),
      ),
    );
  }
}

/// 虚线画笔
class _DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedLinePainter({
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength = 4,
    this.gapLength = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final totalLength = (end - start).distance;
    if (totalLength == 0) return;

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
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        color != oldDelegate.color;
  }
}
