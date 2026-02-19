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
  final int? existingTagId;
  final String? initialName;
  final int? initialColor;

  const AreaDrawScreen(
      {super.key,
      required this.gameMap,
      required this.layer,
      this.area,
      this.existingTagId,
      this.initialName,
      this.initialColor});

  @override
  ConsumerState<AreaDrawScreen> createState() => _AreaDrawScreenState();
}

class _AreaDrawScreenState extends ConsumerState<AreaDrawScreen> {
  static const List<double> _brushPresets = [0.006, 0.012, 0.018, 0.02, 0.03];
  static const int _defaultBrushLevel = 2; // 第3档
  static final double _defaultBrushRatio = _brushPresets[_defaultBrushLevel];
  static const double _minBrushRatio = 0.004;
  static const double _maxBrushRatio = 0.08;

  late final PhotoViewController _photoViewController;
  late final List<MapLayer> _availableLayers;
  late MapLayer _selectedLayer;
  final GlobalKey _stackKey = GlobalKey();
  final List<_DrawStroke> _strokes = [];
  List<Offset> _currentStroke = [];
  double _currentStrokeWidthRatio = _defaultBrushRatio;
  final _nameController = TextEditingController();
  int _selectedColor = 0xFF4CAF50;
  bool _isPenMode = false; // 默认移动模式
  bool _isEraserMode = false;
  double _brushRatio = _defaultBrushRatio; // 画刷直径占图片宽度比例
  int _brushLevel = _defaultBrushLevel;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();

    widget.gameMap.layers.loadSync();
    _availableLayers = widget.gameMap.layers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _selectedLayer = widget.layer;
    if (widget.area != null && widget.area!.layerId != null) {
      final areaLayer =
          _availableLayers.where((l) => l.id == widget.area!.layerId);
      if (areaLayer.isNotEmpty) {
        _selectedLayer = areaLayer.first;
      }
    }

    if (widget.area != null) {
      _nameController.text = widget.area!.name;
      _selectedColor = widget.area!.colorValue;
      _loadStrokes(widget.area!.strokes);
    } else {
      if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
        _nameController.text = widget.initialName!.trim();
      }
      if (widget.initialColor != null) {
        _selectedColor = widget.initialColor!;
      }
    }
  }

  void _loadStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      _strokes.addAll(data.map((stroke) {
        if (stroke is Map) {
          final pointsRaw = (stroke['q'] as List?) ??
              (stroke['points'] as List?) ??
              (stroke['p'] as List?) ??
              const [];
          final points = _parseStrokePoints(
            pointsRaw,
            isDeltaPacked: stroke['q'] != null,
          );
          final widthRatio = _normalizeWidthRatio(
            ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))
                ?.toDouble(),
          ).clamp(_minBrushRatio, _maxBrushRatio);
          final isEraser = _parseIsEraser(stroke['isEraser'] ?? stroke['e']);
          return _DrawStroke(
            points: points,
            widthRatio: widthRatio,
            isEraser: isEraser,
          );
        }

        // 兼容旧数据：无宽度时用默认值加载
        final points =
            stroke is List ? _parseStrokePoints(stroke) : const <Offset>[];
        return _DrawStroke(
          points: points,
          widthRatio: _defaultBrushRatio,
          isEraser: false,
        );
      }).where((s) => s.points.isNotEmpty));
      if (_strokes.isNotEmpty) {
        _brushRatio =
            _strokes.last.widthRatio.clamp(_minBrushRatio, _maxBrushRatio);
        _brushLevel = _nearestBrushLevel(_brushRatio);
        _brushRatio = _brushPresets[_brushLevel];
      }
    } catch (e) {
      debugPrint('Error parsing strokes: $e');
    }
  }

  double _normalizeWidthRatio(double? raw) {
    if (raw == null) return _defaultBrushRatio;
    var value = raw;
    if (value > 1.0) {
      value /= 1000.0;
    }
    return value;
  }

  bool _parseIsEraser(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  List<Offset> _parseStrokePoints(List raw, {bool isDeltaPacked = false}) {
    if (raw.isEmpty) return const [];

    if (raw.first is num) {
      return _parseFlatNumericPoints(raw, isDeltaPacked: isDeltaPacked);
    }

    return raw
        .map((p) {
          if (p is Map && p['x'] is num && p['y'] is num) {
            return Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            );
          }
          if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
            return Offset(
              (p[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            );
          }
          return null;
        })
        .whereType<Offset>()
        .toList();
  }

  List<Offset> _parseFlatNumericPoints(List raw,
      {required bool isDeltaPacked}) {
    if (raw.length < 2) return const [];
    final points = <Offset>[];
    double? x;
    double? y;
    for (int i = 0; i + 1 < raw.length; i += 2) {
      final xRaw = raw[i];
      final yRaw = raw[i + 1];
      if (xRaw is! num || yRaw is! num) continue;

      if (isDeltaPacked) {
        final dx = xRaw.toDouble() / 1000.0;
        final dy = yRaw.toDouble() / 1000.0;
        if (x == null || y == null) {
          x = dx;
          y = dy;
        } else {
          x += dx;
          y += dy;
        }
      } else {
        x = xRaw.toDouble();
        y = yRaw.toDouble();
        if (x > 1.0 || y > 1.0) {
          x /= 1000.0;
          y /= 1000.0;
        }
      }

      points.add(Offset(x, y));
    }
    return points;
  }

  int _nearestBrushLevel(double value) {
    var best = 0;
    var bestDelta = (value - _brushPresets.first).abs();
    for (var i = 1; i < _brushPresets.length; i++) {
      final d = (value - _brushPresets[i]).abs();
      if (d < bestDelta) {
        best = i;
        bestDelta = d;
      }
    }
    return best;
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

  void _onPanStart(
      DragStartDetails details,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    final localPos = details.localPosition;
    final ratio = Offset(
      (localPos.dx - imageBounds.offsetX) / imageBounds.width,
      (localPos.dy - imageBounds.offsetY) / imageBounds.height,
    );
    if (ratio.dx >= 0 && ratio.dx <= 1 && ratio.dy >= 0 && ratio.dy <= 1) {
      setState(() {
        _currentStroke = [ratio];
        _currentStrokeWidthRatio = _brushRatio;
      });
    }
  }

  void _onPanUpdate(
      DragUpdateDetails details,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    if (_currentStroke.isEmpty) return;
    final localPos = details.localPosition;
    final ratio = Offset(
      ((localPos.dx - imageBounds.offsetX) / imageBounds.width).clamp(0.0, 1.0),
      ((localPos.dy - imageBounds.offsetY) / imageBounds.height)
          .clamp(0.0, 1.0),
    );

    final last = _currentStroke.last;
    final delta = ratio - last;
    final distance = delta.distance;
    final step = (_currentStrokeWidthRatio * 0.35).clamp(0.001, 0.04);

    setState(() {
      if (distance <= step) {
        _currentStroke.add(ratio);
        return;
      }
      final unit = delta / distance;
      var travelled = step;
      while (travelled < distance) {
        _currentStroke.add(last + unit * travelled);
        travelled += step;
      }
      _currentStroke.add(ratio);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.isNotEmpty) {
      setState(() {
        _strokes.add(_DrawStroke(
          points: List.from(_currentStroke),
          widthRatio: _currentStrokeWidthRatio,
          isEraser: _isEraserMode,
        ));
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
    final data = _strokes
        .map((stroke) => {
              'widthRatio': stroke.widthRatio,
              'isEraser': stroke.isEraser,
              'points': stroke.points
                  .map((p) => {'x': p.dx, 'y': p.dy})
                  .toList(growable: false),
            })
        .toList();
    return jsonEncode(data);
  }

  Future<void> _selectLayer() async {
    if (_availableLayers.length <= 1) return;
    final selected = await showDialog<MapLayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择区域所属楼层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _availableLayers
              .map(
                (l) => ListTile(
                  title: Text(l.name),
                  trailing: l.id == _selectedLayer.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, l),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || selected.id == _selectedLayer.id) return;
    setState(() => _selectedLayer = selected);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请输入区域名称'), backgroundColor: Colors.orange));
      return;
    }
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请绘制区域范围'), backgroundColor: Colors.orange));
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
        layerId: _selectedLayer.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('区域 "$name" 更新成功'), backgroundColor: Colors.green));
    } else {
      await areaService.createArea(
        name: name,
        colorValue: _selectedColor,
        strokes: _strokesAsJson(),
        mapId: widget.gameMap.id,
        layerId: _selectedLayer.id,
        existingTagId: widget.existingTagId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('区域 "$name" 创建成功'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ));
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('绘制区域 - ${_selectedLayer.name}'),
        actions: [
          if (_availableLayers.length > 1)
            IconButton(
              icon: const Icon(Icons.layers_outlined),
              tooltip: '切换所属楼层',
              onPressed: _selectLayer,
            ),
          IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _strokes.isEmpty ? null : _undo,
              tooltip: '撤销'),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _strokes.isEmpty ? null : _clear,
              tooltip: '清除'),
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
                    final color = await showTagColorPickerDialog(context,
                        initialColor: _selectedColor);
                    if (color != null) setState(() => _selectedColor = color);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Icon(Icons.palette,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 20),
                  ),
                ),
              ],
            ),
          ),
          // 地图绘制区域
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(builder: (context, constraints) {
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
                        return Stack(
                          key: _stackKey,
                          children: [
                            // 地图底图
                            Image.asset(
                              _selectedLayer.assetPath,
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
                                  onPanStart: (d) =>
                                      _onPanStart(d, imageBounds),
                                  onPanUpdate: (d) =>
                                      _onPanUpdate(d, imageBounds),
                                  onPanEnd: _onPanEnd,
                                  child: CustomPaint(
                                    size: constraints.biggest,
                                    painter: _StrokePainter(
                                      strokes: _strokes,
                                      currentStroke: _currentStroke,
                                      currentStrokeWidthRatio:
                                          _currentStrokeWidthRatio,
                                      currentIsEraser: _isEraserMode,
                                      color: Color(_selectedColor),
                                      imageBounds: imageBounds,
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
                      onSelectionChanged: (value) =>
                          setState(() => _isPenMode = value.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('保存区域',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                    ),
                  ],
                ),
                // 圆形画刷大小（仅绘制模式显示）
                if (_isPenMode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.brush, size: 16),
                            label: Text('画笔'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.auto_fix_off, size: 16),
                            label: Text('橡皮擦'),
                          ),
                        ],
                        selected: {_isEraserMode},
                        onSelectionChanged: (values) {
                          setState(() => _isEraserMode = values.first);
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('画刷档位',
                          style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                              fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(value: 0, label: Text('1')),
                            ButtonSegment<int>(value: 1, label: Text('2')),
                            ButtonSegment<int>(value: 2, label: Text('3')),
                            ButtonSegment<int>(value: 3, label: Text('4')),
                            ButtonSegment<int>(value: 4, label: Text('5')),
                          ],
                          selected: {_brushLevel},
                          onSelectionChanged: (values) {
                            final level = values.first;
                            setState(() {
                              _brushLevel = level;
                              _brushRatio = _brushPresets[level];
                            });
                          },
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
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
  static const double _overlayOpacity = 0.5;

  final List<_DrawStroke> strokes;
  final List<Offset> currentStroke;
  final double currentStrokeWidthRatio;
  final bool currentIsEraser;
  final Color color;
  final ({
    double width,
    double height,
    double offsetX,
    double offsetY
  }) imageBounds;

  _StrokePainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentStrokeWidthRatio,
    required this.currentIsEraser,
    required this.color,
    required this.imageBounds,
  });

  Offset _toScreen(Offset ratio) => Offset(
        imageBounds.offsetX + ratio.dx * imageBounds.width,
        imageBounds.offsetY + ratio.dy * imageBounds.height,
      );

  void _drawStroke(
      Canvas canvas, List<Offset> points, double widthRatio, bool isEraser) {
    if (points.isEmpty) return;
    final diameterPx = (widthRatio * imageBounds.width).clamp(3.0, 120.0);
    final radiusPx = diameterPx / 2;

    final fillPaint = isEraser
        ? (Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.fill
          ..isAntiAlias = true)
        : (Paint()
          ..color = color.withValues(alpha: 1.0)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true);

    final bridgePaint = isEraser
        ? (Paint()
          ..blendMode = BlendMode.clear
          ..strokeWidth = diameterPx
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true)
        : (Paint()
          ..color = color.withValues(alpha: 1.0)
          ..strokeWidth = diameterPx
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true);

    final screenPoints = points.map(_toScreen).toList(growable: false);
    for (int i = 0; i < screenPoints.length; i++) {
      canvas.drawCircle(screenPoints[i], radiusPx, fillPaint);
      if (i > 0) {
        canvas.drawLine(screenPoints[i - 1], screenPoints[i], bridgePaint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: _overlayOpacity),
    );

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, stroke.widthRatio, stroke.isEraser);
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(
          canvas, currentStroke, currentStrokeWidthRatio, currentIsEraser);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}

class _DrawStroke {
  final List<Offset> points;
  final double widthRatio;
  final bool isEraser;

  const _DrawStroke({
    required this.points,
    required this.widthRatio,
    required this.isEraser,
  });
}
