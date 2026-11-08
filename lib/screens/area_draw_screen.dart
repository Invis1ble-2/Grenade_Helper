import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:isar_community/isar.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../providers.dart';
import '../services/area_service.dart';
import '../widgets/color_picker_widget.dart';
import '../widgets/path_image_provider.dart';
import '../widgets/square_brush.dart';

enum _DrawTool {
  move,
  brush,
  pen,
  eraser,
  circle,
  square,
}

/// 统一区域/爆点范围绘制界面
class AreaDrawScreen extends ConsumerStatefulWidget {
  final GameMap? gameMap;
  final MapLayer? layer;
  final int? layerId;
  final MapArea? area;
  final int? existingTagId;
  final String? initialName;
  final int? initialColor;
  final bool lockName;

  // 爆点绘制模式参数
  final bool isImpactAreaMode;
  final String? existingStrokes;
  final int grenadeType;
  final double? impactX;
  final double? impactY;

  const AreaDrawScreen({
    super.key,
    required GameMap this.gameMap,
    required MapLayer this.layer,
    this.area,
    this.existingTagId,
    this.initialName,
    this.initialColor,
    this.lockName = false,
  })  : isImpactAreaMode = false,
        layerId = null,
        existingStrokes = null,
        grenadeType = GrenadeType.smoke,
        impactX = null,
        impactY = null;

  const AreaDrawScreen.impactArea({
    super.key,
    this.layer,
    this.layerId,
    this.existingStrokes,
    this.grenadeType = GrenadeType.smoke,
    this.impactX,
    this.impactY,
  })  : isImpactAreaMode = true,
        gameMap = null,
        area = null,
        existingTagId = null,
        initialName = null,
        initialColor = null,
        lockName = true;

  @override
  ConsumerState<AreaDrawScreen> createState() => _AreaDrawScreenState();
}

class _AreaDrawScreenState extends ConsumerState<AreaDrawScreen> {
  static const String _lastUsedColorKey = 'area_draw_last_used_color';
  static const double _defaultBrushRatio = 0.018;
  static const double _minBrushRatio = 0.004;
  static const double _maxBrushRatio = 0.08;

  late final PhotoViewController _photoViewController;
  List<MapLayer> _availableLayers = [];
  MapLayer? _selectedLayer;
  final GlobalKey _stackKey = GlobalKey();
  final List<_DrawStroke> _strokes = [];
  List<Offset> _currentStroke = [];
  double _currentStrokeWidthRatio = _defaultBrushRatio;
  bool _currentStrokeSquare = false;

  // 钢笔工具锚点状态
  final List<Offset> _penPoints = [];
  int? _draggingPenPointIndex;

  // 形状工具状态
  double _shapeSize = 0.05;
  _DrawStroke? _activeShape;

  // 重做栈：元素为被撤销的笔画或钢笔锚点
  final List<Object> _redoStack = [];

  final _nameController = TextEditingController();
  int _selectedColor = 0xFF4CAF50;
  _DrawTool _activeTool = _DrawTool.move;
  double _brushRatio = _defaultBrushRatio;
  bool _squareBrush = false;
  Map<int, MapArea> _tagAreasByLayerId = {};
  final Map<int, _LayerDraft> _draftByLayerId = {};
  int? _lastUsedColor;

  bool get _isTagBoundMultiLayerMode =>
      !widget.isImpactAreaMode && widget.existingTagId != null;

  bool get _isDrawingActive => _activeTool != _DrawTool.move;
  bool get _isEraserMode => _activeTool == _DrawTool.eraser;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();

    if (widget.isImpactAreaMode) {
      _selectedColor = _resolveImpactColor(widget.grenadeType).toARGB32();
      if (widget.existingStrokes != null &&
          widget.existingStrokes!.isNotEmpty) {
        _loadStrokes(widget.existingStrokes!);
      }
      if (widget.layer != null) {
        _selectedLayer = widget.layer;
      } else if (widget.layerId != null) {
        _loadImpactLayer(widget.layerId!);
      }
      return;
    }

    final gameMap = widget.gameMap!;
    gameMap.layers.loadSync();
    _availableLayers = gameMap.layers.toList()
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

    if (_isTagBoundMultiLayerMode && _selectedLayer != null) {
      _loadTagBoundAreas(preferredLayerId: _selectedLayer!.id);
    }
    _loadLastUsedColor();
  }

  Future<void> _loadImpactLayer(int layerId) async {
    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(layerId);
    if (mounted) {
      setState(() => _selectedLayer = layer);
    }
  }

  Color _resolveImpactColor(int grenadeType) {
    switch (grenadeType) {
      case GrenadeType.molotov:
        return Colors.orange;
      case GrenadeType.smoke:
      default:
        return Colors.white;
    }
  }

  Future<void> _loadLastUsedColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedColor = prefs.getInt(_lastUsedColorKey);
      if (savedColor == null || !mounted) return;
      _lastUsedColor = savedColor;

      if (widget.area != null) return;

      setState(() {
        _selectedColor = savedColor;
      });
      if (_isTagBoundMultiLayerMode) {
        _cacheCurrentLayerDraft();
      }
    } catch (_) {}
  }

  Future<void> _rememberLastUsedColor(int colorValue) async {
    _lastUsedColor = colorValue;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastUsedColorKey, colorValue);
    } catch (_) {}
  }

  bool _isAreaNewer(MapArea a, MapArea b) {
    if (a.updatedAt.isAfter(b.updatedAt)) return true;
    if (a.updatedAt.isBefore(b.updatedAt)) return false;
    if (a.createdAt.isAfter(b.createdAt)) return true;
    if (a.createdAt.isBefore(b.createdAt)) return false;
    return a.id > b.id;
  }

  Future<void> _loadTagBoundAreas({int? preferredLayerId}) async {
    if (!_isTagBoundMultiLayerMode || widget.gameMap == null) return;
    final isar = ref.read(isarProvider);
    final tagId = widget.existingTagId!;
    final all = await isar.mapAreas
        .filter()
        .mapIdEqualTo(widget.gameMap!.id)
        .tagIdEqualTo(tagId)
        .findAll();

    final latestByLayer = <int, MapArea>{};
    for (final area in all) {
      final layerId = area.layerId;
      if (layerId == null) continue;
      final previous = latestByLayer[layerId];
      if (previous == null || _isAreaNewer(area, previous)) {
        latestByLayer[layerId] = area;
      }
    }

    _tagAreasByLayerId = latestByLayer;
    for (final entry in latestByLayer.entries) {
      final layerId = entry.key;
      final area = entry.value;
      _draftByLayerId.putIfAbsent(
        layerId,
        () => _LayerDraft(
          name: area.name,
          colorValue: area.colorValue,
          strokes: _decodeStrokes(area.strokes),
        ),
      );
    }
    await _loadLayerAreaState(preferredLayerId ?? _selectedLayer!.id);
  }

  Future<void> _loadLayerAreaState(int layerId) async {
    if (!_isTagBoundMultiLayerMode || !mounted) return;
    final area = _tagAreasByLayerId[layerId];
    final draft = _draftByLayerId[layerId];
    final selected = _availableLayers.firstWhere(
      (l) => l.id == layerId,
      orElse: () => _selectedLayer!,
    );

    setState(() {
      _selectedLayer = selected;
      _strokes.clear();
      _currentStroke = [];
      _penPoints.clear();
      _activeShape = null;
      _redoStack.clear();

      if (draft != null) {
        if (!widget.lockName) {
          _nameController.text = draft.name;
        }
        _selectedColor = draft.colorValue;
        _strokes.addAll(_cloneStrokes(draft.strokes));
      } else if (area != null) {
        if (!widget.lockName) {
          _nameController.text = area.name;
        }
        _selectedColor = area.colorValue;
        _loadStrokes(area.strokes);
      } else {
        if (!widget.lockName) {
          final fallbackName =
              (widget.initialName ?? widget.area?.name ?? '').trim();
          if (fallbackName.isNotEmpty) {
            _nameController.text = fallbackName;
          }
        }
        if (_lastUsedColor != null) {
          _selectedColor = _lastUsedColor!;
        } else if (widget.initialColor != null) {
          _selectedColor = widget.initialColor!;
        }
      }
    });
  }

  void _loadStrokes(String json) {
    final parsed = _decodeStrokes(json);
    _strokes.addAll(parsed);
    final brushStrokes = _strokes.where((s) => !s.isShape).toList();
    if (brushStrokes.isNotEmpty) {
      _brushRatio =
          brushStrokes.last.widthRatio.clamp(_minBrushRatio, _maxBrushRatio);
      _squareBrush = brushStrokes.last.isSquare;
    }
  }

  List<_DrawStroke> _decodeStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      return data
          .map((stroke) {
            if (stroke is Map) {
              final pointsRaw = (stroke['q'] as List?) ??
                  (stroke['points'] as List?) ??
                  (stroke['p'] as List?) ??
                  const [];
              final points = _parseStrokePoints(
                pointsRaw,
                isDeltaPacked: stroke['q'] != null,
              );
              final rawWidthRatio =
                  ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))
                      ?.toDouble();
              final rawStrokeWidth =
                  (stroke['strokeWidth'] as num?)?.toDouble();
              final widthRatio = (rawWidthRatio != null
                      ? _normalizeWidthRatio(rawWidthRatio)
                      : (rawStrokeWidth != null
                          ? (rawStrokeWidth / 800.0)
                          : _defaultBrushRatio))
                  .clamp(_minBrushRatio, _maxBrushRatio);
              final isEraser =
                  _parseBoolFlag(stroke['isEraser'] ?? stroke['e']);
              final isShape = _parseBoolFlag(stroke['isShape'] ?? stroke['s']);
              final shapeType = (stroke['shapeType'] as num?)?.toInt() ?? 0;
              Offset? center;
              if (stroke['center'] is List &&
                  (stroke['center'] as List).length >= 2) {
                final c = stroke['center'] as List;
                if (c[0] is num && c[1] is num) {
                  center = Offset(
                    (c[0] as num).toDouble(),
                    (c[1] as num).toDouble(),
                  );
                }
              }
              return _DrawStroke(
                points: points,
                widthRatio: widthRatio,
                isEraser: isEraser,
                isShape: isShape,
                shapeType: shapeType,
                center: center,
                isSquare: parseSquareBrush(stroke),
              );
            }

            final points =
                stroke is List ? _parseStrokePoints(stroke) : const <Offset>[];
            return _DrawStroke(
              points: points,
              widthRatio: _defaultBrushRatio,
              isEraser: false,
            );
          })
          .where((s) => s.points.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Error parsing strokes: $e');
      return const <_DrawStroke>[];
    }
  }

  List<_DrawStroke> _cloneStrokes(List<_DrawStroke> source) {
    return source
        .map(
          (stroke) => _DrawStroke(
            points: List<Offset>.from(stroke.points),
            widthRatio: stroke.widthRatio,
            isEraser: stroke.isEraser,
            isShape: stroke.isShape,
            shapeType: stroke.shapeType,
            center: stroke.center,
            isSquare: stroke.isSquare,
          ),
        )
        .toList(growable: true);
  }

  void _cacheCurrentLayerDraft() {
    if (!_isTagBoundMultiLayerMode || _selectedLayer == null) return;
    final fallbackName = widget.area?.name ?? widget.initialName ?? '';
    final draftName = _nameController.text.trim().isEmpty
        ? fallbackName.trim()
        : _nameController.text.trim();
    final mergedStrokes = _cloneStrokes(_strokes);
    if (_currentStroke.isNotEmpty) {
      mergedStrokes.add(_DrawStroke(
        points: List<Offset>.from(_currentStroke),
        widthRatio: _currentStrokeWidthRatio,
        isEraser: _isEraserMode,
        isSquare: _currentStrokeSquare,
      ));
    }
    if (_penPoints.length >= 3) {
      mergedStrokes.add(_DrawStroke(
        points: List<Offset>.from(_penPoints),
        widthRatio: _defaultBrushRatio,
        isEraser: false,
        isShape: true,
      ));
    }
    _draftByLayerId[_selectedLayer!.id] = _LayerDraft(
      name: draftName,
      colorValue: _selectedColor,
      strokes: mergedStrokes,
    );
  }

  double _normalizeWidthRatio(double? raw) {
    if (raw == null) return _defaultBrushRatio;
    var value = raw;
    if (value > 1.0) {
      value /= 1000.0;
    }
    return value;
  }

  bool _parseBoolFlag(dynamic value) {
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

  @override
  void dispose() {
    _photoViewController.dispose();
    _nameController.dispose();
    super.dispose();
  }

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

  Offset? _localToRatio(
    Offset localPos,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
  ) {
    final ratio = Offset(
      (localPos.dx - imageBounds.offsetX) / imageBounds.width,
      (localPos.dy - imageBounds.offsetY) / imageBounds.height,
    );
    if (ratio.dx < 0 || ratio.dx > 1 || ratio.dy < 0 || ratio.dy > 1) {
      return null;
    }
    return ratio;
  }

  int? _hitTestPenVertex(
    Offset ratio,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double scale,
  ) {
    if (_penPoints.isEmpty) return null;
    final hitRadiusRatio =
        (16.0 / (imageBounds.width * scale)).clamp(0.008, 0.045);
    final hitRadiusSq = hitRadiusRatio * hitRadiusRatio;
    for (int i = 0; i < _penPoints.length; i++) {
      final d = _penPoints[i] - ratio;
      if (d.dx * d.dx + d.dy * d.dy <= hitRadiusSq) {
        return i;
      }
    }
    return null;
  }

  void _commitPenPolygon({bool clearIfIncomplete = true}) {
    if (_penPoints.length >= 3) {
      _strokes.add(_DrawStroke(
        points: List<Offset>.from(_penPoints),
        widthRatio: _defaultBrushRatio,
        isEraser: false,
        isShape: true,
        shapeType: 0,
      ));
      _penPoints.clear();
      _draggingPenPointIndex = null;
      _redoStack.clear();
      _cacheCurrentLayerDraft();
    } else if (clearIfIncomplete && _penPoints.isNotEmpty) {
      _penPoints.clear();
      _draggingPenPointIndex = null;
    }
  }

  List<Offset> _generateCirclePoints(
      Offset center, double radius, int segments) {
    final points = <Offset>[];
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      final x = (center.dx + radius * math.cos(angle)).clamp(0.0, 1.0);
      final y = (center.dy + radius * math.sin(angle)).clamp(0.0, 1.0);
      points.add(Offset(x, y));
    }
    return points;
  }

  List<Offset> _generateSquarePoints(Offset center, double halfSize) {
    final left = (center.dx - halfSize).clamp(0.0, 1.0);
    final right = (center.dx + halfSize).clamp(0.0, 1.0);
    final top = (center.dy - halfSize).clamp(0.0, 1.0);
    final bottom = (center.dy + halfSize).clamp(0.0, 1.0);
    return [
      Offset(left, top),
      Offset(right, top),
      Offset(right, bottom),
      Offset(left, bottom),
      Offset(left, top),
    ];
  }

  void _placePresetShapeAt(Offset center) {
    final shapeType = _activeTool == _DrawTool.circle
        ? 1
        : (_activeTool == _DrawTool.square ? 2 : 0);
    if (shapeType == 0) return;

    final points = shapeType == 1
        ? _generateCirclePoints(center, _shapeSize, 32)
        : _generateSquarePoints(center, _shapeSize);

    final shape = _DrawStroke(
      points: points,
      widthRatio: _defaultBrushRatio,
      isEraser: false,
      isShape: true,
      shapeType: shapeType,
      center: center,
    );
    setState(() {
      final idx = _activeShapeIndex;
      if (idx == -1) {
        _strokes.add(shape);
        _redoStack.clear();
      } else {
        _strokes[idx] = shape;
      }
      _activeShape = shape;
    });
    _cacheCurrentLayerDraft();
  }

  int get _activeShapeIndex => _activeShape == null
      ? -1
      : _strokes.indexWhere((s) => identical(s, _activeShape));

  void _startNewShape() {
    setState(() => _activeShape = null);
  }

  void _updateActivePresetShape({int? targetShapeType}) {
    final idx = _activeShapeIndex;
    if (idx == -1) return;

    final existing = _strokes[idx];
    final center = existing.center ?? _computePolygonCenter(existing.points);
    final shapeType = targetShapeType ?? existing.shapeType;
    final points = shapeType == 1
        ? _generateCirclePoints(center, _shapeSize, 32)
        : _generateSquarePoints(center, _shapeSize);

    setState(() {
      final updated = _DrawStroke(
        points: points,
        widthRatio: existing.widthRatio,
        isEraser: false,
        isShape: true,
        shapeType: shapeType,
        center: center,
      );
      _strokes[idx] = updated;
      _activeShape = updated;
    });
    _cacheCurrentLayerDraft();
  }

  Offset _computePolygonCenter(List<Offset> points) {
    if (points.isEmpty) return const Offset(0.5, 0.5);
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  void _onCanvasTapDown(
    TapDownDetails details,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double scale,
  ) {
    final ratio = _localToRatio(details.localPosition, imageBounds);
    if (ratio == null) return;

    if (_activeTool == _DrawTool.pen) {
      final hitIdx = _hitTestPenVertex(ratio, imageBounds, scale);
      if (hitIdx == 0 && _penPoints.length >= 3) {
        setState(() => _commitPenPolygon());
        return;
      }
      if (hitIdx != null) {
        return;
      }
      setState(() {
        _penPoints.add(ratio);
        _redoStack.clear();
      });
      _cacheCurrentLayerDraft();
      return;
    }

    if (_activeTool == _DrawTool.circle || _activeTool == _DrawTool.square) {
      _placePresetShapeAt(ratio);
      return;
    }

    if (_activeTool == _DrawTool.brush || _activeTool == _DrawTool.eraser) {
      setState(() {
        _currentStroke = [ratio];
        _currentStrokeWidthRatio = _brushRatio;
        _currentStrokeSquare = _squareBrush;
      });
    }
  }

  void _onCanvasTapUp(TapUpDetails details) {
    if (_activeTool == _DrawTool.brush || _activeTool == _DrawTool.eraser) {
      _finishFreehandStroke();
    }
  }

  void _onPanStart(
    DragStartDetails details,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double scale,
  ) {
    final ratio = _localToRatio(details.localPosition, imageBounds);
    if (ratio == null) return;

    if (_activeTool == _DrawTool.pen) {
      final hitIdx = _hitTestPenVertex(ratio, imageBounds, scale);
      if (hitIdx != null) {
        _draggingPenPointIndex = hitIdx;
      }
      return;
    }

    if (_activeTool == _DrawTool.circle || _activeTool == _DrawTool.square) {
      _placePresetShapeAt(ratio);
      return;
    }

    if (_activeTool == _DrawTool.brush || _activeTool == _DrawTool.eraser) {
      setState(() {
        _currentStroke = [ratio];
        _currentStrokeWidthRatio = _brushRatio;
        _currentStrokeSquare = _squareBrush;
      });
    }
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
  ) {
    final clampedRatio = Offset(
      ((details.localPosition.dx - imageBounds.offsetX) / imageBounds.width)
          .clamp(0.0, 1.0),
      ((details.localPosition.dy - imageBounds.offsetY) / imageBounds.height)
          .clamp(0.0, 1.0),
    );

    if (_activeTool == _DrawTool.pen) {
      final idx = _draggingPenPointIndex;
      if (idx != null && idx >= 0 && idx < _penPoints.length) {
        setState(() => _penPoints[idx] = clampedRatio);
      }
      return;
    }

    if (_activeTool == _DrawTool.circle || _activeTool == _DrawTool.square) {
      _placePresetShapeAt(clampedRatio);
      return;
    }

    if (_currentStroke.isEmpty) return;

    final last = _currentStroke.last;
    final delta = clampedRatio - last;
    final distance = delta.distance;
    final step = (_currentStrokeWidthRatio * 0.35).clamp(0.001, 0.04);

    setState(() {
      if (distance <= step) {
        _currentStroke.add(clampedRatio);
        return;
      }
      final unit = delta / distance;
      var travelled = step;
      while (travelled < distance) {
        _currentStroke.add(last + unit * travelled);
        travelled += step;
      }
      _currentStroke.add(clampedRatio);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activeTool == _DrawTool.pen) {
      if (_draggingPenPointIndex != null) {
        _draggingPenPointIndex = null;
        _cacheCurrentLayerDraft();
      }
      return;
    }
    _finishFreehandStroke();
  }

  void _finishFreehandStroke() {
    if (_currentStroke.isNotEmpty) {
      setState(() {
        _strokes.add(_DrawStroke(
          points: List.from(_currentStroke),
          widthRatio: _currentStrokeWidthRatio,
          isEraser: _isEraserMode,
          isSquare: _currentStrokeSquare,
        ));
        _currentStroke = [];
        _redoStack.clear();
      });
      _cacheCurrentLayerDraft();
    }
  }

  void _switchTool(_DrawTool nextTool) {
    if (_activeTool == nextTool) return;
    setState(() {
      if (_activeTool == _DrawTool.pen) {
        _commitPenPolygon();
      }
      _activeTool = nextTool;
      if (nextTool == _DrawTool.circle) {
        _updateActivePresetShape(targetShapeType: 1);
      } else if (nextTool == _DrawTool.square) {
        _updateActivePresetShape(targetShapeType: 2);
      }
    });
  }

  bool get _canUndo => _penPoints.isNotEmpty || _strokes.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  void _undo() {
    setState(() {
      if (_penPoints.isNotEmpty) {
        _redoStack.add(_penPoints.removeLast());
      } else if (_strokes.isNotEmpty) {
        _redoStack.add(_strokes.removeLast());
      }
    });
    _cacheCurrentLayerDraft();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      final item = _redoStack.removeLast();
      if (item is Offset) {
        _penPoints.add(item);
      } else if (item is _DrawStroke) {
        _strokes.add(item);
      }
    });
    _cacheCurrentLayerDraft();
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _penPoints.clear();
      _draggingPenPointIndex = null;
      _activeShape = null;
      _redoStack.clear();
    });
    _cacheCurrentLayerDraft();
  }

  String _strokesAsJson([List<_DrawStroke>? source]) {
    final strokes = source ?? _strokes;
    final data = strokes
        .map((stroke) => <String, dynamic>{
              'points': stroke.points
                  .map((p) => [p.dx, p.dy])
                  .toList(growable: false),
              'widthRatio': stroke.widthRatio,
              'strokeWidth': (stroke.widthRatio * 800.0).clamp(4.0, 64.0),
              'isEraser': stroke.isEraser,
              if (stroke.isSquare) 'brushShape': 1,
              if (stroke.isShape) 'isShape': true,
              if (stroke.shapeType > 0) 'shapeType': stroke.shapeType,
              if (stroke.center != null)
                'center': [stroke.center!.dx, stroke.center!.dy],
            })
        .toList();
    return jsonEncode(data);
  }

  Future<void> _selectLayer() async {
    if (_availableLayers.length <= 1 || _selectedLayer == null) return;
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
                  trailing: l.id == _selectedLayer!.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, l),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || selected.id == _selectedLayer!.id) return;
    if (_penPoints.isNotEmpty) {
      _commitPenPolygon();
    }
    if (_isTagBoundMultiLayerMode) {
      _cacheCurrentLayerDraft();
      await _loadLayerAreaState(selected.id);
      return;
    }
    setState(() => _selectedLayer = selected);
  }

  Future<void> _save() async {
    if (_currentStroke.isNotEmpty) {
      _finishFreehandStroke();
    }
    if (_penPoints.isNotEmpty) {
      setState(() => _commitPenPolygon());
    }

    if (widget.isImpactAreaMode) {
      Navigator.pop(context, {'strokes': _strokesAsJson()});
      return;
    }

    final fallbackName = widget.area?.name ?? widget.initialName ?? '';
    final typedName = _nameController.text.trim();
    final name = typedName.isNotEmpty ? typedName : fallbackName.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请输入区域名称'), backgroundColor: Colors.orange));
      return;
    }
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);

    if (_isTagBoundMultiLayerMode) {
      _cacheCurrentLayerDraft();
      final hasAnyStroke =
          _draftByLayerId.values.any((e) => e.strokes.isNotEmpty);
      if (!hasAnyStroke) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请至少绘制一个楼层的区域范围'), backgroundColor: Colors.orange));
        return;
      }

      final tagId = widget.existingTagId!;
      int savedCount = 0;
      int deletedCount = 0;

      for (final entry in _draftByLayerId.entries) {
        final layerId = entry.key;
        final draft = entry.value;
        final existing = _tagAreasByLayerId[layerId];
        if (draft.strokes.isEmpty) {
          if (existing != null) {
            await areaService.deleteArea(existing, deleteTag: false);
            _tagAreasByLayerId.remove(layerId);
            deletedCount++;
          }
          continue;
        }

        final strokesJson = _strokesAsJson(draft.strokes);
        if (existing == null) {
          final created = await areaService.createArea(
            name: name,
            colorValue: draft.colorValue,
            strokes: strokesJson,
            mapId: widget.gameMap!.id,
            layerId: layerId,
            existingTagId: tagId,
          );
          _tagAreasByLayerId[layerId] = created;
          savedCount++;
          continue;
        }

        final changed = existing.name != name ||
            existing.colorValue != draft.colorValue ||
            existing.strokes != strokesJson ||
            existing.layerId != layerId;
        if (!changed) continue;

        await areaService.updateArea(
          area: existing,
          name: name,
          colorValue: draft.colorValue,
          strokes: strokesJson,
          layerId: layerId,
        );
        savedCount++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('区域 "$name" 已保存：更新/新建$savedCount层，清除$deletedCount层'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ));
    } else if (widget.area != null) {
      if (_strokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请绘制区域范围'), backgroundColor: Colors.orange));
        return;
      }
      await areaService.updateArea(
        area: widget.area!,
        name: name,
        colorValue: _selectedColor,
        strokes: _strokesAsJson(),
        layerId: _selectedLayer!.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('区域 "$name" 更新成功'), backgroundColor: Colors.green));
    } else {
      if (_strokes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('请绘制区域范围'), backgroundColor: Colors.orange));
        return;
      }
      await areaService.createArea(
        name: name,
        colorValue: _selectedColor,
        strokes: _strokesAsJson(),
        mapId: widget.gameMap!.id,
        layerId: _selectedLayer!.id,
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
    if (_selectedLayer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isCompactToolbar = MediaQuery.of(context).size.width < 700;
    final overlayOpacity =
        widget.isImpactAreaMode ? ref.watch(impactAreaOpacityProvider) : 0.5;
    final drawColor = Color(_selectedColor);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isImpactAreaMode ? '绘制爆点区域' : '绘制区域 - ${_selectedLayer!.name}',
        ),
        actions: [
          if (!widget.isImpactAreaMode && _availableLayers.length > 1)
            IconButton(
              icon: const Icon(Icons.layers_outlined),
              tooltip: '切换所属楼层',
              onPressed: _selectLayer,
            ),
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _canUndo ? _undo : null,
            tooltip: '撤销 (Ctrl+Z)',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _canRedo ? _redo : null,
            tooltip: '重做 (Ctrl+Y)',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _canUndo ? _clear : null,
            tooltip: '清除',
          ),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
            if (_canUndo) _undo();
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              if (!widget.isImpactAreaMode)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      if (!widget.lockName)
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
                        )
                      else
                        Expanded(
                          child: Container(
                            height: 40,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                            ),
                            child: Text(
                              '绑定标签：${_nameController.text.trim().isEmpty ? "未命名标签" : _nameController.text.trim()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () async {
                          final color = await showTagColorPickerDialog(context,
                              initialColor: _selectedColor);
                          if (color != null) {
                            setState(() => _selectedColor = color);
                            _cacheCurrentLayerDraft();
                            _rememberLastUsedColor(color);
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                Color(_selectedColor).withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Color(_selectedColor)),
                          ),
                          child: Icon(Icons.palette,
                              color: Color(_selectedColor), size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
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
                            final scale = snapshot.data?.scale ?? 1.0;
                            final markerScale = 1.0 / scale;

                            return Stack(
                              key: _stackKey,
                              children: [
                                Builder(builder: (context) {
                                  final provider = imageProviderFromPath(
                                      _selectedLayer!.assetPath);
                                  if (provider == null) {
                                    return Container(
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      color: Colors.black,
                                    );
                                  }
                                  return Image(
                                    image: provider,
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                    fit: BoxFit.contain,
                                  );
                                }),
                                if (widget.isImpactAreaMode &&
                                    widget.impactX != null &&
                                    widget.impactY != null)
                                  _buildImpactReferenceMarker(
                                      imageBounds, markerScale),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: !_isDrawingActive,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (d) => _onCanvasTapDown(
                                          d, imageBounds, scale),
                                      onTapUp: _onCanvasTapUp,
                                      onPanStart: (d) =>
                                          _onPanStart(d, imageBounds, scale),
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
                                          currentIsSquare: _currentStrokeSquare,
                                          penPoints: _penPoints,
                                          color: drawColor,
                                          opacity: overlayOpacity,
                                          imageBounds: imageBounds,
                                          markerScale: markerScale,
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
              _buildBottomToolbar(isCompactToolbar, drawColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImpactReferenceMarker(
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double markerScale,
  ) {
    const double baseHalfSize = 10.0;
    final left = imageBounds.offsetX +
        widget.impactX! * imageBounds.width -
        baseHalfSize;
    final top = imageBounds.offsetY +
        widget.impactY! * imageBounds.height -
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

  Widget _buildBottomToolbar(bool compact, Color drawColor) {
    final theme = Theme.of(context);
    final accentColor =
        widget.isImpactAreaMode ? theme.colorScheme.primary : drawColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 10,
      ),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildToolChip(
                        icon: Icons.pan_tool_alt_outlined,
                        label: '移动',
                        selected: _activeTool == _DrawTool.move,
                        color: theme.colorScheme.primary,
                        onTap: () => _switchTool(_DrawTool.move),
                      ),
                      const SizedBox(width: 6),
                      _buildToolChip(
                        icon: Icons.brush_rounded,
                        label: '画笔',
                        selected: _activeTool == _DrawTool.brush,
                        color: accentColor,
                        onTap: () => _switchTool(_DrawTool.brush),
                      ),
                      const SizedBox(width: 6),
                      _buildToolChip(
                        icon: Icons.polyline_rounded,
                        label: '钢笔',
                        selected: _activeTool == _DrawTool.pen,
                        color: accentColor,
                        onTap: () => _switchTool(_DrawTool.pen),
                      ),
                      const SizedBox(width: 6),
                      _buildToolChip(
                        icon: Icons.auto_fix_off_rounded,
                        label: '橡皮',
                        selected: _activeTool == _DrawTool.eraser,
                        color: Colors.grey,
                        onTap: () => _switchTool(_DrawTool.eraser),
                      ),
                      const SizedBox(width: 6),
                      _buildToolChip(
                        icon: Icons.circle_outlined,
                        label: '圆形',
                        selected: _activeTool == _DrawTool.circle,
                        color: accentColor,
                        onTap: () => _switchTool(_DrawTool.circle),
                      ),
                      const SizedBox(width: 6),
                      _buildToolChip(
                        icon: Icons.crop_square_rounded,
                        label: '方块',
                        selected: _activeTool == _DrawTool.square,
                        color: accentColor,
                        onTap: () => _switchTool(_DrawTool.square),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _save,
                icon: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: compact ? 16 : 18,
                ),
                label: Text(
                  '保存',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 16,
                    vertical: compact ? 8 : 10,
                  ),
                ),
              ),
            ],
          ),
          if (_activeTool == _DrawTool.brush ||
              _activeTool == _DrawTool.eraser) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _buildBrushShapeButton(
                  icon: Icons.circle,
                  tooltip: '圆形笔刷',
                  square: false,
                ),
                const SizedBox(width: 6),
                _buildBrushShapeButton(
                  icon: Icons.square,
                  tooltip: '方形笔刷',
                  square: true,
                ),
                const SizedBox(width: 12),
                Text(
                  '粗细',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _brushRatio,
                      min: _minBrushRatio,
                      max: _maxBrushRatio,
                      activeColor: theme.colorScheme.primary,
                      onChanged: (val) => setState(() => _brushRatio = val),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(_brushRatio * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_activeTool == _DrawTool.pen) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _penPoints.length < 3
                        ? '点击地图依次打点（至少3个点自动围成填充区域），可拖拽调整锚点'
                        : '已打 ${_penPoints.length} 个锚点，点击起点或右侧按钮完成闭合',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                if (_penPoints.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _penPoints.length >= 3
                        ? () => setState(() => _commitPenPolygon())
                        : () => setState(() => _penPoints.clear()),
                    icon: Icon(
                      _penPoints.length >= 3
                          ? Icons.done_all_rounded
                          : Icons.close_rounded,
                      size: 15,
                    ),
                    label: Text(
                      _penPoints.length >= 3 ? '闭合填充' : '取消锚点',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ] else if (_activeTool == _DrawTool.circle ||
              _activeTool == _DrawTool.square) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '形状大小: ${(_shapeSize * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _shapeSize,
                      min: 0.02,
                      max: 0.15,
                      activeColor: accentColor,
                      onChanged: (val) {
                        setState(() => _shapeSize = val);
                        _updateActivePresetShape();
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: '新建形状',
                  iconSize: 22,
                  visualDensity: VisualDensity.compact,
                  color: accentColor,
                  onPressed: _activeShapeIndex == -1 ? null : _startNewShape,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBrushShapeButton({
    required IconData icon,
    required String tooltip,
    required bool square,
  }) {
    final theme = Theme.of(context);
    final selected = _squareBrush == square;
    final color = selected
        ? theme.colorScheme.primary
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _squareBrush = square),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildToolChip({
    required IconData icon,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = selected
        ? (isDark
            ? color
            : HSLColor.fromColor(color).withLightness(0.38).toColor())
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7) ??
            Colors.grey;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? activeColor
                : theme.dividerColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: activeColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: activeColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 笔画与多边形绘制器
class _StrokePainter extends CustomPainter {
  final List<_DrawStroke> strokes;
  final List<Offset> currentStroke;
  final double currentStrokeWidthRatio;
  final bool currentIsEraser;
  final bool currentIsSquare;
  final List<Offset> penPoints;
  final Color color;
  final double opacity;
  final ({
    double width,
    double height,
    double offsetX,
    double offsetY
  }) imageBounds;
  final double markerScale;

  _StrokePainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentStrokeWidthRatio,
    required this.currentIsEraser,
    required this.currentIsSquare,
    required this.penPoints,
    required this.color,
    required this.opacity,
    required this.imageBounds,
    required this.markerScale,
  });

  Offset _toScreen(Offset ratio) => Offset(
        imageBounds.offsetX + ratio.dx * imageBounds.width,
        imageBounds.offsetY + ratio.dy * imageBounds.height,
      );

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    double widthRatio,
    bool isEraser,
    bool isShape, {
    bool isSquare = false,
  }) {
    if (points.isEmpty) return;
    final screenPoints = points.map(_toScreen).toList(growable: false);

    if (isShape && screenPoints.length >= 3) {
      final polyPaint = isEraser
          ? (Paint()
            ..blendMode = BlendMode.clear
            ..style = PaintingStyle.fill
            ..isAntiAlias = true)
          : (Paint()
            ..color = color.withValues(alpha: 1.0)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true);
      final path = Path()..addPolygon(screenPoints, true);
      canvas.drawPath(path, polyPaint);
      return;
    }

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

    if (isSquare) {
      paintSquareBrush(canvas, screenPoints, diameterPx, fillPaint);
      return;
    }

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

    for (int i = 0; i < screenPoints.length; i++) {
      canvas.drawCircle(screenPoints[i], radiusPx, fillPaint);
      if (i > 0) {
        canvas.drawLine(screenPoints[i - 1], screenPoints[i], bridgePaint);
      }
    }
  }

  void _drawActivePenOverlay(Canvas canvas) {
    if (penPoints.isEmpty) return;
    final screenPts = penPoints.map(_toScreen).toList(growable: false);

    final outlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = (1.6 * markerScale).clamp(0.8, 2.5)
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final path = Path()..moveTo(screenPts.first.dx, screenPts.first.dy);
    for (int i = 1; i < screenPts.length; i++) {
      path.lineTo(screenPts[i].dx, screenPts[i].dy);
    }
    if (screenPts.length >= 3) {
      path.close();
    }
    canvas.drawPath(path, outlinePaint);

    final handleRadius = (5.0 * markerScale).clamp(2.5, 7.0);
    for (int i = 0; i < screenPts.length; i++) {
      final isFirst = i == 0 && screenPts.length >= 3;
      final fillPaint = Paint()
        ..color = isFirst ? Colors.greenAccent : Colors.white
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.black87
        ..strokeWidth = (1.4 * markerScale).clamp(0.7, 2.0)
        ..style = PaintingStyle.stroke;

      final r = isFirst ? handleRadius * 1.25 : handleRadius;
      canvas.drawCircle(screenPts[i], r, fillPaint);
      canvas.drawCircle(screenPts[i], r, strokePaint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );

    for (final stroke in strokes) {
      _drawStroke(
        canvas,
        stroke.points,
        stroke.widthRatio,
        stroke.isEraser,
        stroke.isShape,
        isSquare: stroke.isSquare,
      );
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(
        canvas,
        currentStroke,
        currentStrokeWidthRatio,
        currentIsEraser,
        false,
        isSquare: currentIsSquare,
      );
    }

    if (penPoints.length >= 3) {
      _drawStroke(
        canvas,
        penPoints,
        currentStrokeWidthRatio,
        false,
        true,
      );
    }

    canvas.restore();

    if (penPoints.isNotEmpty) {
      _drawActivePenOverlay(canvas);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}

class _DrawStroke {
  final List<Offset> points;
  final double widthRatio;
  final bool isEraser;
  final bool isShape;
  final int shapeType;
  final Offset? center;
  final bool isSquare;

  const _DrawStroke({
    required this.points,
    required this.widthRatio,
    required this.isEraser,
    this.isShape = false,
    this.shapeType = 0,
    this.center,
    this.isSquare = false,
  });
}

class _LayerDraft {
  final String name;
  final int colorValue;
  final List<_DrawStroke> strokes;

  const _LayerDraft({
    required this.name,
    required this.colorValue,
    required this.strokes,
  });
}
