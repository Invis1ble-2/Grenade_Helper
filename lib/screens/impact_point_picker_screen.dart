import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import '../models.dart';
import '../providers.dart';

/// 爆点选择/绘制页面
class ImpactPointPickerScreen extends ConsumerStatefulWidget {
  final int grenadeId;
  final double? initialX;
  final double? initialY;
  final double throwX;
  final double throwY;
  final int layerId;
  final bool isDrawingMode;
  final String? existingStrokes; // 现有笔画 JSON
  final int grenadeType; // 道具类型（用于颜色）
  final bool readOnly; // 只读模式，仅查看不可编辑

  const ImpactPointPickerScreen({
    super.key,
    required this.grenadeId,
    this.initialX,
    this.initialY,
    required this.throwX,
    required this.throwY,
    required this.layerId,
    this.isDrawingMode = false,
    this.existingStrokes,
    this.grenadeType = GrenadeType.smoke,
    this.readOnly = false,
  });

  @override
  ConsumerState<ImpactPointPickerScreen> createState() =>
      _ImpactPointPickerScreenState();
}

class _ImpactPointPickerScreenState
    extends ConsumerState<ImpactPointPickerScreen> {
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey();

  // 选中坐标
  double? _selectedX;
  double? _selectedY;

  // 楼层信息
  MapLayer? _layer;

  // 绘制状态
  bool _isPenMode = false; // 默认移动模式
  bool _isEraserMode = false;
  double _brushSize = 15.0;
  double _shapeSize = 0.05;
  int _selectedShapeType = 0; // 0:笔刷 1:圆 2:方
  List<Map<String, dynamic>> _drawingStrokes = [];
  List<Offset> _currentStroke = [];

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    _selectedX = widget.initialX;
    _selectedY = widget.initialY;
    _loadLayer();

    // 解析笔画（绘制模式或只读模式都需要解析）
    if ((widget.isDrawingMode || widget.readOnly) &&
        widget.existingStrokes != null) {
      try {
        final parsed = jsonDecode(widget.existingStrokes!) as List;
        _drawingStrokes =
            parsed.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
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

  /// 计算图片区域
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

  /// 坐标转比例
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

  // 选择模式

  void _handleTap(TapUpDetails details) {
    final localRatio = _getLocalPosition(details.globalPosition);
    if (localRatio == null) return;

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

  /// 滚轮缩放
  void _handleMouseWheelZoom(
      PointerScrollEvent event, BoxConstraints constraints) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    final double zoomFactor = scrollDelta > 0 ? 0.9 : 1.1;
    final double currentScale = _photoViewController.scale ?? 1.0;
    final Offset currentPosition = _photoViewController.position;

    final minScale = 0.8;
    final maxScale = 5.0;
    final double newScale =
        (currentScale * zoomFactor).clamp(minScale, maxScale);

    if ((newScale - currentScale).abs() < 0.0001) return;

    final Size size = renderBox.size;
    final Offset viewportCenter = size.center(Offset.zero);
    final Offset cursorPosition = event.localPosition - viewportCenter;

    final double scaleRatio = newScale / currentScale;
    final Offset newPosition =
        cursorPosition * (1 - scaleRatio) + currentPosition * scaleRatio;

    _photoViewController.scale = newScale;
    _photoViewController.position = newPosition;
  }

  // 绘制方法

  Color _getTypeColor() {
    switch (widget.grenadeType) {
      case GrenadeType.smoke:
        return Colors.white;
      case GrenadeType.molotov:
        return Colors.orange;
      default:
        return Colors.white;
    }
  }

  List<List<double>> _generateCirclePoints(
      Offset center, double radius, int segments) {
    final points = <List<double>>[];
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * pi;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      points.add([x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)]);
    }
    return points;
  }

  List<List<double>> _generateSquarePoints(Offset center, double halfSize) {
    final left = (center.dx - halfSize).clamp(0.0, 1.0);
    final right = (center.dx + halfSize).clamp(0.0, 1.0);
    final top = (center.dy - halfSize).clamp(0.0, 1.0);
    final bottom = (center.dy + halfSize).clamp(0.0, 1.0);
    return [
      [left, top],
      [right, top],
      [right, bottom],
      [left, bottom],
      [left, top],
    ];
  }

  void _placeShapeAt(Offset center) {
    if (_selectedShapeType == 0) return;

    List<List<double>> points;
    if (_selectedShapeType == 1) {
      points = _generateCirclePoints(center, _shapeSize, 32);
    } else {
      points = _generateSquarePoints(center, _shapeSize);
    }

    setState(() {
      _drawingStrokes.removeWhere((s) => s['isShape'] == true);
      _drawingStrokes.add({
        'points': points,
        'strokeWidth': _brushSize,
        'isEraser': false,
        'isShape': true,
        'shapeType': _selectedShapeType,
        'center': [center.dx, center.dy], // 存储中心
      });
    });
  }

  void _updateActiveShapeSize() {
    final shapeIndex = _drawingStrokes.indexWhere((s) => s['isShape'] == true);
    if (shapeIndex == -1) return;

    final shape = _drawingStrokes[shapeIndex];

    // 计算中心
    Offset center;
    if (shape['center'] != null) {
      final centerList = shape['center'] as List;
      center = Offset(
          (centerList[0] as num).toDouble(), (centerList[1] as num).toDouble());
    } else {
      final pointsData = shape['points'] as List;
      if (pointsData.isEmpty) return;

      final points = pointsData.map((p) {
        final pointList = p as List;
        return Offset(
            (pointList[0] as num).toDouble(), (pointList[1] as num).toDouble());
      }).toList();

      double minX = points.first.dx;
      double maxX = points.first.dx;
      double minY = points.first.dy;
      double maxY = points.first.dy;

      for (var p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }

      center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
      shape['center'] = [center.dx, center.dy];
    }

    final type = shape['shapeType'] as int;

    // 匹配类型更新
    // if (type != _selectedShapeType) return;

    List<List<double>> points;
    if (type == 1) {
      points = _generateCirclePoints(center, _shapeSize, 32);
    } else {
      points = _generateSquarePoints(center, _shapeSize);
    }

    setState(() {
      shape['points'] = points;
    });
  }

  void _convertExistingShapeTo(int targetType) {
    if (targetType < 1) return;

    final shapeIndex = _drawingStrokes.indexWhere((s) => s['isShape'] == true);
    if (shapeIndex == -1) return;

    final shape = _drawingStrokes[shapeIndex];

    Offset center;
    if (shape['center'] != null) {
      final centerList = shape['center'] as List;
      center = Offset(
          (centerList[0] as num).toDouble(), (centerList[1] as num).toDouble());
    } else {
      _updateActiveShapeSize();
      if (shape['center'] != null) {
        final centerList = shape['center'] as List;
        center = Offset((centerList[0] as num).toDouble(),
            (centerList[1] as num).toDouble());
      } else {
        return;
      }
    }

    List<List<double>> points;
    if (targetType == 1) {
      points = _generateCirclePoints(center, _shapeSize, 32);
    } else {
      points = _generateSquarePoints(center, _shapeSize);
    }

    setState(() {
      shape['shapeType'] = targetType;
      shape['points'] = points;
    });
  }

  void _commitCurrentStrokeIfNeeded() {
    if (_selectedShapeType > 0 || _currentStroke.isEmpty) {
      return;
    }
    _drawingStrokes.add({
      'points': _currentStroke.map((o) => [o.dx, o.dy]).toList(),
      'strokeWidth': _brushSize,
      'isEraser': _isEraserMode,
    });
    _currentStroke = [];
  }

  void _confirmDrawing() {
    if (_currentStroke.isNotEmpty) {
      setState(_commitCurrentStrokeIfNeeded);
    }
    final strokesJson = jsonEncode(_drawingStrokes);
    Navigator.pop(context, {'strokes': strokesJson});
  }

  @override
  Widget build(BuildContext context) {
    if (_layer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scaffoldBg = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.readOnly
            ? '查看爆点位置'
            : (widget.isDrawingMode ? '绘制爆点区域' : '选择爆点位置')),
        centerTitle: true,
        actions: [
          if (!widget.readOnly) ...[
            if (widget.isDrawingMode) ...[
              if (_drawingStrokes.isNotEmpty)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _commitCurrentStrokeIfNeeded();
                      if (_drawingStrokes.isNotEmpty) {
                        _drawingStrokes.removeLast();
                      }
                    });
                  },
                  icon: const Icon(Icons.undo),
                  tooltip: '撤销',
                ),
              IconButton(
                onPressed: _drawingStrokes.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _currentStroke = [];
                          _drawingStrokes.clear();
                        });
                      },
                icon: const Icon(Icons.delete_outline),
                tooltip: '清除全部',
              ),
            ],
            TextButton(
              onPressed:
                  widget.isDrawingMode ? _confirmDrawing : _confirmSelection,
              child: Text(
                widget.isDrawingMode ? '保存' : '确认',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imageBounds = _getImageBounds(
                      constraints.maxWidth, constraints.maxHeight);

                  return Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _handleMouseWheelZoom(event, constraints);
                      }
                    },
                    child: PhotoView.customChild(
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
                          final double markerScale = 1.0 / scale;

                          return Stack(
                            key: _stackKey,
                            children: [
                              GestureDetector(
                                  onTapUp:
                                      (widget.isDrawingMode || widget.readOnly)
                                          ? null
                                          : _handleTap,
                                  child: Image.asset(
                                    _layer!.assetPath,
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                    fit: BoxFit.contain,
                                  )),
                              if (widget.isDrawingMode)
                                ..._buildDrawingLayers(
                                    constraints, imageBounds, markerScale)
                              else
                                ..._buildPickerLayers(
                                    constraints, imageBounds, markerScale),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (!widget.readOnly)
            widget.isDrawingMode
                ? _buildDrawingToolbar()
                : _buildPickerFooter(),
        ],
      ),
    );
  }

  // 选择视图

  List<Widget> _buildPickerLayers(
    BoxConstraints constraints,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double markerScale,
  ) {
    final color = _getTypeColor();

    return [
      _buildThrowPointMarker(imageBounds, markerScale),
      if (_selectedX != null && _selectedY != null)
        _buildConnectionLine(imageBounds),
      if (_selectedX != null && _selectedY != null)
        _buildImpactMarker(imageBounds, markerScale),
      // 只读模式下显示已绘制的爆点范围
      if (widget.readOnly && _drawingStrokes.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ImpactAreaPainter(
                strokes: _drawingStrokes,
                currentStroke: const [],
                currentStrokeWidth: 15.0,
                isCurrentEraser: false,
                color: color,
                imageBounds: imageBounds,
                opacity: 0.6,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildPickerFooter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = colorScheme.surfaceContainerHighest;
    final textColor = colorScheme.onSurfaceVariant;
    final markerColor = colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: bgColor,
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
                  border: Border.all(color: markerColor, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '投掷点',
                style: TextStyle(color: textColor, fontSize: 12),
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
              Text(
                '爆点',
                style: TextStyle(color: textColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _selectedX != null ? '已选择爆点，点击确认保存' : '💡 点击地图任意位置设置爆点',
            style: TextStyle(
              color: _selectedX != null
                  ? theme.colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // 绘制视图

  List<Widget> _buildDrawingLayers(
    BoxConstraints constraints,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double markerScale,
  ) {
    final color = _getTypeColor();

    return [
      // 爆点
      if (widget.initialX != null && widget.initialY != null)
        _buildImpactMarkerForDrawing(imageBounds, markerScale),
      // 画布 - 移动模式时忽略绘图事件
      Positioned.fill(
        child: IgnorePointer(
          ignoring: !_isPenMode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final localPos = details.localPosition;
              final ratio = Offset(
                (localPos.dx - imageBounds.offsetX) / imageBounds.width,
                (localPos.dy - imageBounds.offsetY) / imageBounds.height,
              );
              if (ratio.dx >= 0 &&
                  ratio.dx <= 1 &&
                  ratio.dy >= 0 &&
                  ratio.dy <= 1) {
                if (_selectedShapeType > 0) {
                  _placeShapeAt(ratio);
                } else {
                  setState(() => _currentStroke = [ratio]);
                }
              }
            },
            onTapUp: (_) {
              if (_selectedShapeType > 0) return;
              if (_currentStroke.isNotEmpty) {
                setState(() {
                  _commitCurrentStrokeIfNeeded();
                });
              }
            },
            onPanStart: (details) {
              if (_selectedShapeType > 0) return;
              final localPos = details.localPosition;
              final ratio = Offset(
                (localPos.dx - imageBounds.offsetX) / imageBounds.width,
                (localPos.dy - imageBounds.offsetY) / imageBounds.height,
              );
              if (ratio.dx >= 0 &&
                  ratio.dx <= 1 &&
                  ratio.dy >= 0 &&
                  ratio.dy <= 1) {
                setState(() => _currentStroke = [ratio]);
              }
            },
            onPanUpdate: (details) {
              if (_selectedShapeType > 0) return;
              final localPos = details.localPosition;
              final ratio = Offset(
                (localPos.dx - imageBounds.offsetX) / imageBounds.width,
                (localPos.dy - imageBounds.offsetY) / imageBounds.height,
              );
              if (ratio.dx >= 0 &&
                  ratio.dx <= 1 &&
                  ratio.dy >= 0 &&
                  ratio.dy <= 1) {
                setState(() => _currentStroke.add(ratio));
              }
            },
            onPanEnd: (_) {
              if (_selectedShapeType > 0) return;
              if (_currentStroke.isNotEmpty) {
                setState(() {
                  _commitCurrentStrokeIfNeeded();
                });
              }
            },
            onPanCancel: () {
              if (_selectedShapeType > 0) return;
              if (_currentStroke.isNotEmpty) {
                setState(() {
                  _commitCurrentStrokeIfNeeded();
                });
              }
            },
            child: CustomPaint(
              painter: _ImpactAreaPainter(
                strokes: _drawingStrokes,
                currentStroke: _currentStroke,
                currentStrokeWidth: _brushSize,
                isCurrentEraser: _isEraserMode,
                color: color,
                imageBounds: imageBounds,
                opacity: ref.watch(impactAreaOpacityProvider),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildImpactMarkerForDrawing(
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double markerScale,
  ) {
    const double baseHalfSize = 10.0;
    final left = imageBounds.offsetX +
        widget.initialX! * imageBounds.width -
        baseHalfSize;
    final top = imageBounds.offsetY +
        widget.initialY! * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
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
            ),
            child:
                const Icon(Icons.close, size: 12, color: Colors.purpleAccent),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    final color = _getTypeColor();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = colorScheme.surfaceContainerHighest;
    final textColor = colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 模式切换 + 工具栏
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 移动/绘制模式切换
                _buildToolButton(
                  icon: Icons.pan_tool,
                  label: "移动",
                  isSelected: !_isPenMode,
                  color: theme.colorScheme.primary,
                  onTap: () => setState(() => _isPenMode = false),
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: Icons.brush,
                  label: "笔刷",
                  isSelected:
                      _isPenMode && _selectedShapeType == 0 && !_isEraserMode,
                  color: color,
                  onTap: () => setState(() {
                    _isPenMode = true;
                    _selectedShapeType = 0;
                    _isEraserMode = false;
                  }),
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: Icons.auto_fix_high,
                  label: "橡皮",
                  isSelected: _isPenMode && _isEraserMode,
                  color: Colors.grey,
                  onTap: () => setState(() {
                    _isPenMode = true;
                    _selectedShapeType = 0;
                    _isEraserMode = true;
                  }),
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: Icons.circle,
                  label: "圆形",
                  isSelected: _isPenMode && _selectedShapeType == 1,
                  color: color,
                  onTap: () {
                    setState(() {
                      _isPenMode = true;
                      _selectedShapeType = 1;
                      _isEraserMode = false;
                    });
                    _convertExistingShapeTo(1);
                  },
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: Icons.square,
                  label: "方块",
                  isSelected: _isPenMode && _selectedShapeType == 2,
                  color: color,
                  onTap: () {
                    setState(() {
                      _isPenMode = true;
                      _selectedShapeType = 2;
                      _isEraserMode = false;
                    });
                    _convertExistingShapeTo(2);
                  },
                ),
              ],
            ),
          ),
          // 大小滑块 - 只在绘制模式时显示
          if (_isPenMode) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedShapeType > 0
                            ? "形状大小: ${(_shapeSize * 100).round()}%"
                            : "笔刷大小: ${_brushSize.round()}",
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8),
                        ),
                        child: _selectedShapeType > 0
                            ? Slider(
                                value: _shapeSize,
                                min: 0.02,
                                max: 0.15,
                                activeColor: color,
                                onChanged: (val) {
                                  setState(() => _shapeSize = val);
                                  _updateActiveShapeSize();
                                },
                              )
                            : Slider(
                                value: _brushSize,
                                min: 5,
                                max: 30,
                                activeColor:
                                    _isEraserMode ? Colors.grey : color,
                                onChanged: (val) =>
                                    setState(() => _brushSize = val),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 浅色主题下，如果选中色太浅则使用深色版本
    final displayColor = isSelected
        ? (isDark
            ? color
            : HSLColor.fromColor(color).withLightness(0.4).toColor())
        : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? displayColor : Colors.grey.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: displayColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: displayColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 选择模式标记

  Widget _buildThrowPointMarker(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds,
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

  Widget _buildImpactMarker(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds,
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

  Widget _buildConnectionLine(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
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

/// 爆点区域画笔
class _ImpactAreaPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final List<Offset> currentStroke;
  final double currentStrokeWidth;
  final bool isCurrentEraser;
  final Color color;
  final double opacity;
  final ({
    double width,
    double height,
    double offsetX,
    double offsetY
  }) imageBounds;

  _ImpactAreaPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentStrokeWidth,
    required this.isCurrentEraser,
    required this.color,
    required this.imageBounds,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: opacity));

    for (final stroke in strokes) {
      final points =
          (stroke['points'] as List).map((p) => Offset(p[0], p[1])).toList();
      final width = (stroke['strokeWidth'] as num).toDouble();
      final isEraser = stroke['isEraser'] as bool? ?? false;
      final isShape = stroke['isShape'] as bool? ?? false;
      _drawStroke(canvas, points, width, isEraser, isShape);
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(
          canvas, currentStroke, currentStrokeWidth, isCurrentEraser, false);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, List<Offset> points, double width,
      bool isEraser, bool isShape) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = isEraser ? Colors.transparent : color.withValues(alpha: 1.0)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isShape ? PaintingStyle.fill : PaintingStyle.stroke;

    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    final path = Path();
    final start = _limitPoint(points[0]);
    path.moveTo(start.dx, start.dy);

    if (points.length == 1) {
      path.lineTo(start.dx, start.dy);
    }

    for (int i = 1; i < points.length; i++) {
      final p = _limitPoint(points[i]);
      path.lineTo(p.dx, p.dy);
    }

    if (isShape) {
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  Offset _limitPoint(Offset ratio) {
    return Offset(
      imageBounds.offsetX + ratio.dx * imageBounds.width,
      imageBounds.offsetY + ratio.dy * imageBounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant _ImpactAreaPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
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
