import 'dart:convert';
import 'dart:math' as math;
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../models/map_area.dart';
import '../models/tag.dart';

class DefaultAreaExportService {
  const DefaultAreaExportService();

  Future<String> exportCurrentMapDefaultAreaPresets({
    required GameMap map,
    required Isar isar,
  }) async {
    await map.layers.load();
    final layers = map.layers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final layerById = {for (final layer in layers) layer.id: layer};

    final areaTags = await isar.tags
        .filter()
        .mapIdEqualTo(map.id)
        .dimensionEqualTo(TagDimension.area)
        .isSystemEqualTo(true)
        .sortBySortOrder()
        .findAll();

    if (areaTags.isEmpty) {
      return _buildEmptyTemplate(_resolveMapKey(map));
    }

    final tagById = {for (final tag in areaTags) tag.id: tag};

    final allAreas =
        await isar.mapAreas.filter().mapIdEqualTo(map.id).findAll();
    final deduped = <String, MapArea>{};

    for (final area in allAreas) {
      final layerId = area.layerId;
      if (!tagById.containsKey(area.tagId)) continue;
      if (layerId == null) continue;
      if (!layerById.containsKey(layerId)) continue;
      if (!_hasValidStrokes(area.strokes)) continue;

      final key = '${area.tagId}_$layerId';
      final previous = deduped[key];
      if (previous == null ||
          area.createdAt.isAfter(previous.createdAt) ||
          (area.createdAt.isAtSameMomentAs(previous.createdAt) &&
              area.id > previous.id)) {
        deduped[key] = area;
      }
    }

    if (deduped.isEmpty) {
      return _buildEmptyTemplate(_resolveMapKey(map));
    }

    final areasByLayer = <int, List<MapArea>>{};
    for (final area in deduped.values) {
      final layerId = area.layerId!;
      areasByLayer.putIfAbsent(layerId, () => []).add(area);
    }

    for (final entry in areasByLayer.entries) {
      entry.value.sort((a, b) {
        final t1 = tagById[a.tagId]?.sortOrder ?? 0;
        final t2 = tagById[b.tagId]?.sortOrder ?? 0;
        if (t1 != t2) return t1.compareTo(t2);
        return a.name.compareTo(b.name);
      });
    }

    final mapKey = _resolveMapKey(map);
    final sb = StringBuffer();
    sb.writeln('class BuiltinAreaPreset {');
    sb.writeln('  final String name;');
    sb.writeln('  final int colorValue;');
    sb.writeln('  final String strokesJson;');
    sb.writeln();
    sb.writeln('  const BuiltinAreaPreset({');
    sb.writeln('    required this.name,');
    sb.writeln('    required this.colorValue,');
    sb.writeln('    required this.strokesJson,');
    sb.writeln('  });');
    sb.writeln('}');
    sb.writeln();
    sb.writeln(
        'const Map<String, Map<String, List<BuiltinAreaPreset>>> builtinAreaRegionPresets = {');
    sb.writeln("  '$mapKey': {");

    var hasAnyFloor = false;
    for (final layer in layers) {
      final layerAreas = areasByLayer[layer.id];
      if (layerAreas == null || layerAreas.isEmpty) continue;
      hasAnyFloor = true;

      final floorKey = _extractFileName(layer.assetPath);
      sb.writeln("    '$floorKey': [");
      for (final area in layerAreas) {
        final tag = tagById[area.tagId];
        if (tag == null) continue;

        sb.writeln('      BuiltinAreaPreset(');
        sb.writeln("        name: '${_escapeDartString(tag.name)}',");
        sb.writeln('        colorValue: ${_toHexColor(tag.colorValue)},');
        final compactStrokes = _compactStrokesJson(area.strokes);
        sb.writeln("        strokesJson: r'''$compactStrokes''',");
        sb.writeln('      ),');
      }
      sb.writeln('    ],');
    }

    if (!hasAnyFloor) {
      sb.writeln('    // 当前地图暂无可导出的默认区域数据');
    }

    sb.writeln('  },');
    sb.writeln('};');
    return sb.toString();
  }

  String _buildEmptyTemplate(String mapKey) {
    return '''
class BuiltinAreaPreset {
  final String name;
  final int colorValue;
  final String strokesJson;

  const BuiltinAreaPreset({
    required this.name,
    required this.colorValue,
    required this.strokesJson,
  });
}

const Map<String, Map<String, List<BuiltinAreaPreset>>> builtinAreaRegionPresets = {
  '$mapKey': {
    // 当前地图暂无可导出的默认区域数据
  },
};
''';
  }

  bool _hasValidStrokes(String strokesJson) {
    try {
      final strokes = _parseStrokes(strokesJson);
      return strokes.any((s) => !s.isEraser && s.points.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  String _compactStrokesJson(String rawJson) {
    try {
      final strokes = _parseStrokes(rawJson);
      if (strokes.isEmpty) return rawJson;

      final compact = <Map<String, dynamic>>[];
      for (final stroke in strokes) {
        final simplified =
            _simplifyStrokePoints(stroke.points, stroke.widthRatio);
        if (simplified.isEmpty) continue;

        final points = <List<double>>[];
        List<double>? lastPoint;
        for (final p in simplified) {
          final current = [_roundTo(p.x, 3), _roundTo(p.y, 3)];
          if (lastPoint != null &&
              lastPoint[0] == current[0] &&
              lastPoint[1] == current[1]) {
            continue;
          }
          points.add(current);
          lastPoint = current;
        }
        if (points.isEmpty) continue;

        final packed = _packQuantizedDelta(points);
        if (packed.isEmpty) continue;

        final entry = <String, dynamic>{'q': packed};
        if ((stroke.widthRatio - _defaultBrushRatio).abs() > 1e-4) {
          entry['w'] = (stroke.widthRatio * _quantizeScale).round();
        }
        if (stroke.isEraser) {
          entry['e'] = 1;
        }
        compact.add(entry);
      }

      if (compact.isEmpty) return rawJson;
      return jsonEncode(compact);
    } catch (_) {
      return rawJson;
    }
  }

  List<_ExportStroke> _parseStrokes(String json) {
    final data = jsonDecode(json);
    if (data is! List) return const [];

    final result = <_ExportStroke>[];
    for (final stroke in data) {
      if (stroke is Map) {
        final points = _parseStrokePoints(stroke);
        if (points.isEmpty) continue;
        final widthRatio = _parseWidthRatio(stroke);
        final isEraser = _parseIsEraser(stroke);
        result.add(
          _ExportStroke(
            points: points,
            widthRatio: widthRatio,
            isEraser: isEraser,
          ),
        );
        continue;
      }

      // 兼容旧格式：每条笔画直接是 points 数组
      if (stroke is List) {
        final points = _parsePoints(stroke);
        if (points.isEmpty) continue;
        result.add(
          _ExportStroke(
            points: points,
            widthRatio: _defaultBrushRatio,
            isEraser: false,
          ),
        );
      }
    }
    return result;
  }

  List<_Pt> _parseStrokePoints(Map stroke) {
    final qRaw = stroke['q'];
    if (qRaw is List) {
      final decoded = _decodeQuantizedDelta(qRaw);
      if (decoded.isNotEmpty) return decoded;
    }

    final pointsRaw = stroke['points'] ?? stroke['p'];
    if (pointsRaw is! List) return const [];
    return _parsePoints(pointsRaw);
  }

  double _parseWidthRatio(Map stroke) {
    final raw = (stroke['widthRatio'] as num?) ?? (stroke['w'] as num?);
    if (raw == null) return _defaultBrushRatio;
    var value = raw.toDouble();
    if (value > 1.0) {
      value /= _quantizeScale;
    }
    return value.clamp(_minBrushRatio, _maxBrushRatio);
  }

  bool _parseIsEraser(Map stroke) {
    final raw = stroke['isEraser'] ?? stroke['e'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return false;
  }

  List<_Pt> _parsePoints(List pointsRaw) {
    if (pointsRaw.length >= 2 && pointsRaw.first is num) {
      final points = <_Pt>[];
      for (int i = 0; i + 1 < pointsRaw.length; i += 2) {
        final xRaw = pointsRaw[i];
        final yRaw = pointsRaw[i + 1];
        if (xRaw is! num || yRaw is! num) continue;
        var x = xRaw.toDouble();
        var y = yRaw.toDouble();
        if (x > 1.0 || y > 1.0) {
          x /= _quantizeScale;
          y /= _quantizeScale;
        }
        points.add(_Pt(x, y));
      }
      return points;
    }

    final points = <_Pt>[];
    for (final p in pointsRaw) {
      if (p is Map && p['x'] is num && p['y'] is num) {
        points.add(_Pt((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
        continue;
      }
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        points.add(_Pt((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }
    return points;
  }

  List<int> _packQuantizedDelta(List<List<double>> points) {
    if (points.isEmpty) return const [];

    final packed = <int>[];
    int? lastX;
    int? lastY;
    for (final p in points) {
      final qx = (p[0] * _quantizeScale).round().clamp(0, _quantizeScale);
      final qy = (p[1] * _quantizeScale).round().clamp(0, _quantizeScale);
      if (lastX == null || lastY == null) {
        packed.add(qx);
        packed.add(qy);
      } else {
        packed.add(qx - lastX);
        packed.add(qy - lastY);
      }
      lastX = qx;
      lastY = qy;
    }
    return packed;
  }

  List<_Pt> _decodeQuantizedDelta(List raw) {
    if (raw.length < 2) return const [];

    final points = <_Pt>[];
    int? x;
    int? y;
    for (int i = 0; i + 1 < raw.length; i += 2) {
      final dxRaw = raw[i];
      final dyRaw = raw[i + 1];
      if (dxRaw is! num || dyRaw is! num) continue;
      final dx = dxRaw.round();
      final dy = dyRaw.round();
      if (x == null || y == null) {
        x = dx;
        y = dy;
      } else {
        x += dx;
        y += dy;
      }
      points.add(_Pt(x / _quantizeScale, y / _quantizeScale));
    }
    return points;
  }

  List<_Pt> _simplifyStrokePoints(List<_Pt> points, double widthRatio) {
    if (points.length <= 2) return points;
    final epsilon = (widthRatio * 0.22).clamp(0.0008, 0.01);
    return _rdp(points, epsilon);
  }

  List<_Pt> _rdp(List<_Pt> points, double epsilon) {
    if (points.length <= 2) return points;

    var index = -1;
    var dmax = 0.0;
    final end = points.length - 1;

    for (var i = 1; i < end; i++) {
      final d = _perpendicularDistance(points[i], points[0], points[end]);
      if (d > dmax) {
        index = i;
        dmax = d;
      }
    }

    if (dmax <= epsilon || index <= 0) {
      return [points.first, points.last];
    }

    final left = _rdp(points.sublist(0, index + 1), epsilon);
    final right = _rdp(points.sublist(index), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  double _perpendicularDistance(_Pt p, _Pt a, _Pt b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 <= 1e-12) {
      final px = p.x - a.x;
      final py = p.y - a.y;
      return math.sqrt(px * px + py * py);
    }

    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
    final projX = a.x + dx * t;
    final projY = a.y + dy * t;
    final ddx = p.x - projX;
    final ddy = p.y - projY;
    return math.sqrt(ddx * ddx + ddy * ddy);
  }

  double _roundTo(double value, int precision) {
    final f = math.pow(10, precision).toDouble();
    return (value * f).round() / f;
  }

  String _resolveMapKey(GameMap map) {
    final iconPath = map.iconPath;
    final iconMatch = RegExp(
      r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
      caseSensitive: false,
    ).firstMatch(iconPath);

    if (iconMatch != null && iconMatch.groupCount >= 1) {
      final key = iconMatch.group(1);
      if (key != null && key.isNotEmpty) {
        return key.toLowerCase();
      }
    }

    final fallback =
        map.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (fallback.isNotEmpty) return fallback;
    return 'map_${map.id}';
  }

  String _extractFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _toHexColor(int value) {
    return '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  String _escapeDartString(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  }
}

const double _defaultBrushRatio = 0.018;
const double _minBrushRatio = 0.004;
const double _maxBrushRatio = 0.08;
const int _quantizeScale = 1000;

class _ExportStroke {
  final List<_Pt> points;
  final double widthRatio;
  final bool isEraser;

  const _ExportStroke({
    required this.points,
    required this.widthRatio,
    required this.isEraser,
  });
}

class _Pt {
  final double x;
  final double y;

  const _Pt(this.x, this.y);
}
