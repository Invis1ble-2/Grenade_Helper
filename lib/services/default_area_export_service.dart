import 'dart:convert';
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
        sb.writeln("        strokesJson: r'''${area.strokes}''',");
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
      final data = jsonDecode(strokesJson);
      if (data is! List || data.isEmpty) return false;
      for (final stroke in data) {
        if (stroke is List && stroke.length >= 3) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
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
