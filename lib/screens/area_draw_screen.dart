import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:photo_view/photo_view.dart';
import '../models.dart';
import '../providers.dart';
import '../services/area_service.dart';
import '../widgets/color_picker_widget.dart';

/// 区域绘制界面
class AreaDrawScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  final MapLayer layer;
  final MapArea? area;
  
  const AreaDrawScreen({super.key, required this.gameMap, required this.layer, this.area});
  
  @override
  ConsumerState<AreaDrawScreen> createState() => _AreaDrawScreenState();
}

class _AreaDrawScreenState extends ConsumerState<AreaDrawScreen> {
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  final _nameController = TextEditingController();
  int _selectedColor = 0xFF4CAF50;
  bool _isPenMode = false; // 默认移动模式
  double _strokeWidth = 2.5; // 笔画宽度
  
  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    if (widget.area != null) {
      _nameController.text = widget.area!.name;
      _selectedColor = widget.area!.colorValue;
      _loadStrokes(widget.area!.strokes);
    }
  }

  void _loadStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      _strokes.addAll(data.map((stroke) {
        final points = stroke as List;
        return points.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList();
      }));
    } catch (e) {
      debugPrint('Error parsing strokes: $e');
    }
  }
  
  @override
  void dispose() {
    _photoViewController.dispose();
    _nameController.dispose();
    super.dispose();
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

    const minScale = 0.8;
    const maxScale = 5.0;
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
  
  void _onPanStart(DragStartDetails details, 
      ({double width, double height, double offsetX, double offsetY}) imageBounds) {
    final localPos = details.localPosition;
    final ratio = Offset(
      (localPos.dx - imageBounds.offsetX) / imageBounds.width,
      (localPos.dy - imageBounds.offsetY) / imageBounds.height,
    );
    if (ratio.dx >= 0 && ratio.dx <= 1 && ratio.dy >= 0 && ratio.dy <= 1) {
      setState(() {
        _currentStroke = [ratio];
      });
    }
  }
  
  void _onPanUpdate(DragUpdateDetails details, 
      ({double width, double height, double offsetX, double offsetY}) imageBounds) {
    final localPos = details.localPosition;
    final ratio = Offset(
      ((localPos.dx - imageBounds.offsetX) / imageBounds.width).clamp(0.0, 1.0),
      ((localPos.dy - imageBounds.offsetY) / imageBounds.height).clamp(0.0, 1.0),
    );
    setState(() {
      _currentStroke.add(ratio);
    });
  }
  
  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.length > 2) {
      setState(() {
        _strokes.add(List.from(_currentStroke));
        _currentStroke = [];
      });
    }
  }
  
  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    }
  }
  
  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }
  
  String _strokesAsJson() {
    final data = _strokes.map((stroke) => 
      stroke.map((p) => {'x': p.dx, 'y': p.dy}).toList()
    ).toList();
    return jsonEncode(data);
  }
  
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入区域名称'), backgroundColor: Colors.orange)
      );
      return;
    }
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请绘制区域范围'), backgroundColor: Colors.orange)
      );
      return;
    }
    
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    
    if (widget.area != null) {
      await areaService.updateArea(
        area: widget.area!,
        name: name,
        colorValue: _selectedColor,
        strokes: _strokesAsJson(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('区域 "$name" 更新成功'), backgroundColor: Colors.green)
      );
    } else {
      await areaService.createArea(
        name: name,
        colorValue: _selectedColor,
        strokes: _strokesAsJson(),
        mapId: widget.gameMap.id,
        layerId: widget.layer.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('区域 "$name" 创建成功'), backgroundColor: Colors.green)
      );
    }
    
    Navigator.pop(context, true);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('绘制区域 - ${widget.layer.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _strokes.isEmpty ? null : _undo, tooltip: '撤销'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _strokes.isEmpty ? null : _clear, tooltip: '清除'),
        ],
      ),
      body: Column(
        children: [
          // 输入区域名称和颜色
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '区域名称',
                      hintText: '如: A大, 中路...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () async {
                    final color = await showTagColorPickerDialog(context, initialColor: _selectedColor);
                    if (color != null) setState(() => _selectedColor = color);
                  },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Color(_selectedColor),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.palette, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // 地图绘制区域
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(builder: (context, constraints) {
              final imageBounds = _getImageBounds(constraints.maxWidth, constraints.maxHeight);
              return Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _handleMouseWheelZoom(event, constraints);
                  }
                },
                child: PhotoView.customChild(
                  controller: _photoViewController,
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  initialScale: PhotoViewComputedScale.contained,
                  child: StreamBuilder<PhotoViewControllerValue>(
                    stream: _photoViewController.outputStateStream,
                    builder: (context, snapshot) {
                      return Stack(
                        key: _stackKey,
                        children: [
                          // 地图底图
                          Image.asset(
                            widget.layer.assetPath,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            fit: BoxFit.contain,
                          ),
                          // 绘制层 - 移动模式时忽略绘图事件
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !_isPenMode,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (d) => _onPanStart(d, imageBounds),
                                onPanUpdate: (d) => _onPanUpdate(d, imageBounds),
                                onPanEnd: _onPanEnd,
                                child: CustomPaint(
                                  size: constraints.biggest,
                                  painter: _StrokePainter(
                                    strokes: _strokes,
                                    currentStroke: _currentStroke,
                                    color: Color(_selectedColor),
                                    imageBounds: imageBounds,
                                    strokeWidth: _strokeWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            }),
            ),
          ),
          // 工具栏和保存按钮
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // 移动/绘制模式切换
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.pan_tool, size: 16),
                          label: Text('移动'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.brush, size: 16),
                          label: Text('绘制'),
                        ),
                      ],
                      selected: {_isPenMode},
                      onSelectionChanged: (value) => setState(() => _isPenMode = value.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('保存区域', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ],
                ),
                // 笔画宽度滑块（仅绘制模式显示）
                if (_isPenMode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('笔画宽度', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _strokeWidth,
                          min: 1.0,
                          max: 8.0,
                          divisions: 14,
                          label: _strokeWidth.toStringAsFixed(1),
                          onChanged: (v) => setState(() => _strokeWidth = v),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('${_strokeWidth.toStringAsFixed(1)}', 
                          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 笔画绘制器
class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color color;
  final ({double width, double height, double offsetX, double offsetY}) imageBounds;
  final double strokeWidth;
  
  _StrokePainter({
    required this.strokes, 
    required this.currentStroke, 
    required this.color,
    required this.imageBounds,
    required this.strokeWidth,
  });

  Offset _toScreen(Offset ratio) => Offset(
    imageBounds.offsetX + ratio.dx * imageBounds.width,
    imageBounds.offsetY + ratio.dy * imageBounds.height,
  );

  Path _buildSmoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    
    final screenPoints = points.map(_toScreen).toList();
    path.moveTo(screenPoints.first.dx, screenPoints.first.dy);
    
    if (screenPoints.length < 3) {
      for (int i = 1; i < screenPoints.length; i++) {
        path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
      }
    } else {
      // 使用二次贝塞尔曲线平滑路径
      for (int i = 1; i < screenPoints.length - 1; i++) {
        final p1 = screenPoints[i];
        final p2 = screenPoints[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      // 连接到最后一点
      final last = screenPoints.last;
      path.lineTo(last.dx, last.dy);
    }
    return path;
  }
  
  @override
  void paint(Canvas canvas, Size size) {
    // 先绘制所有填充区域（避免分层）
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    
    for (final stroke in strokes) {
      if (stroke.length < 3) continue;
      final path = _buildSmoothPath(stroke);
      path.close();
      canvas.drawPath(path, fillPaint);
    }
    
    // 再绘制所有描边（在填充之上）
    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = _buildSmoothPath(stroke);
      path.close();
      canvas.drawPath(path, strokePaint);
    }
    
    // 绘制当前笔画（实时预览）
    if (currentStroke.length >= 2) {
      final path = _buildSmoothPath(currentStroke);
      final previewPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(path, previewPaint);
    }
  }
  
  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
