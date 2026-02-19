import 'dart:convert';
import 'dart:ui';
import 'package:isar_community/isar.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../models/grenade_tag.dart';
import '../models.dart';

class AutoTagSummary {
  final int processedGrenades;
  final int matchedGrenades;
  final int addedLinks;
  final int removedLinks;
  final Map<String, int> areaMatches;

  const AutoTagSummary({
    required this.processedGrenades,
    required this.matchedGrenades,
    required this.addedLinks,
    required this.removedLinks,
    required this.areaMatches,
  });
}

class AreaTagSyncSummary {
  final int processedGrenades;
  final int matchedGrenades;
  final int addedLinks;
  final int removedLinks;

  const AreaTagSyncSummary({
    required this.processedGrenades,
    required this.matchedGrenades,
    required this.addedLinks,
    required this.removedLinks,
  });
}

/// 区域服务
class AreaService {
  static const double _defaultBrushRatio = 0.018;
  static const double _minBrushRatio = 0.004;
  static const double _maxBrushRatio = 0.08;

  final Isar isar;
  AreaService(this.isar);

  /// 获取地图的所有区域
  Future<List<MapArea>> getAreas(int mapId) async {
    return isar.mapAreas.filter().mapIdEqualTo(mapId).findAll();
  }

  /// 创建区域并自动创建对应标签
  Future<MapArea> createArea({
    required String name,
    required int colorValue,
    required String strokes,
    required int mapId,
    int? layerId,
    int? existingTagId,
  }) async {
    int tagId;
    if (existingTagId != null) {
      tagId = existingTagId;
      await isar.writeTxn(() async {
        final tag = await isar.tags.get(existingTagId);
        if (tag != null) {
          tag.name = name;
          tag.colorValue = colorValue;
          await isar.tags.put(tag);
        }
      });
    } else {
      // 先创建对应的区域标签
      final tag = Tag(
        name: name,
        colorValue: colorValue,
        dimension: TagDimension.area,
        isSystem: false,
        sortOrder: 0,
        mapId: mapId,
      );
      await isar.writeTxn(() async {
        await isar.tags.put(tag);
      });
      tagId = tag.id;
    }

    // 创建区域
    final area = MapArea(
      name: name,
      colorValue: colorValue,
      strokes: strokes,
      mapId: mapId,
      layerId: layerId,
      tagId: tagId,
      createdAt: DateTime.now(),
    );
    await isar.writeTxn(() async {
      await isar.mapAreas.put(area);
    });

    return area;
  }

  /// 删除区域
  /// [deleteTag] 为 true 时会同时删除区域标签与关联关系。
  /// 传 false 时仅删除区域几何数据。
  Future<void> deleteArea(MapArea area, {bool deleteTag = true}) async {
    await isar.writeTxn(() async {
      if (deleteTag) {
        // 删除标签关联
        await isar.grenadeTags.filter().tagIdEqualTo(area.tagId).deleteAll();
        await isar.tags.delete(area.tagId);
      }
      await isar.mapAreas.delete(area.id);
    });
  }

  /// 更新区域及其标签
  Future<void> updateArea({
    required MapArea area,
    required String name,
    required int colorValue,
    required String strokes,
    int? layerId,
  }) async {
    await isar.writeTxn(() async {
      // 1. 更新对应标签
      final tag = await isar.tags.get(area.tagId);
      if (tag != null) {
        tag.name = name;
        tag.colorValue = colorValue;
        await isar.tags.put(tag);
      }

      // 2. 更新区域
      area.name = name;
      area.colorValue = colorValue;
      area.strokes = strokes;
      area.layerId = layerId;
      await isar.mapAreas.put(area);
    });
  }

  /// 判断点是否在区域内（基于涂画笔画与笔宽）
  bool isPointInArea(double x, double y, MapArea area) {
    final strokes = _parseStrokes(area.strokes);
    if (strokes.isEmpty) return false;

    final point = Offset(x, y);
    var isInside = false;

    // 按笔画顺序应用：普通笔画命中=加入区域，橡皮擦命中=移出区域
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      if (!_isPointOnStroke(point, stroke)) continue;
      isInside = !stroke.isEraser;
    }
    return isInside;
  }

  /// 获取点所在的所有区域
  Future<List<MapArea>> getAreasForPoint(int mapId, double x, double y,
      {int? layerId}) async {
    final areas = await getAreas(mapId);
    return areas.where((area) {
      // 自动标签时必须严格匹配楼层，避免旧数据 layerId=null 导致跨层误标
      if (layerId != null && area.layerId != layerId) {
        return false;
      }
      return isPointInArea(x, y, area);
    }).toList();
  }

  /// 自动为道具添加区域标签
  Future<void> autoTagGrenade(
    Grenade grenade,
    int mapId, {
    int? layerId,
    bool syncExistingAreaTags = false,
    Set<int>? scopedAreaTagIds,
  }) async {
    final effectiveLayerId = layerId ?? await _resolveGrenadeLayerId(grenade);
    final areas = await getAreasForPoint(
      mapId,
      grenade.xRatio,
      grenade.yRatio,
      layerId: effectiveLayerId,
    );
    final matchedAreaTagIds = areas.map((a) => a.tagId).toSet();
    final allAreaTagIds = scopedAreaTagIds ??
        (syncExistingAreaTags ? await _getAreaTagIds(mapId) : const <int>{});

    await isar.writeTxn(() async {
      if (syncExistingAreaTags && allAreaTagIds.isNotEmpty) {
        final existingLinks = await isar.grenadeTags
            .filter()
            .grenadeIdEqualTo(grenade.id)
            .findAll();
        for (final link in existingLinks) {
          if (allAreaTagIds.contains(link.tagId) &&
              !matchedAreaTagIds.contains(link.tagId)) {
            await isar.grenadeTags.delete(link.id);
          }
        }
      }

      for (final tagId in matchedAreaTagIds) {
        // 检查是否已有该区域标签
        final existing = await isar.grenadeTags
            .filter()
            .grenadeIdEqualTo(grenade.id)
            .and()
            .tagIdEqualTo(tagId)
            .findFirst();
        if (existing == null) {
          await isar.grenadeTags
              .put(GrenadeTag(grenadeId: grenade.id, tagId: tagId));
        }
      }
    });
  }

  /// 批量为地图所有道具自动标签
  /// [useImpactPoint] 为 true 时，按爆点坐标判定；否则按站位坐标判定。
  Future<AutoTagSummary> autoTagAllGrenades(
    int mapId, {
    bool useImpactPoint = false,
  }) async {
    final areas = await getAreas(mapId);
    final map = await isar.gameMaps.get(mapId);
    if (map == null) {
      return const AutoTagSummary(
        processedGrenades: 0,
        matchedGrenades: 0,
        addedLinks: 0,
        removedLinks: 0,
        areaMatches: {},
      );
    }
    await map.layers.load();
    final layers = map.layers.toList();

    final allGrenades = <Grenade>[];
    final grenadesByLayer = <int, List<Grenade>>{};
    for (final layer in layers) {
      final grenades = await isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(layer.id))
          .findAll();
      grenadesByLayer[layer.id] = grenades;
      allGrenades.addAll(grenades);
    }

    final processedGrenades = useImpactPoint
        ? allGrenades
            .where((g) => g.impactXRatio != null && g.impactYRatio != null)
            .length
        : allGrenades.length;

    if (areas.isEmpty || allGrenades.isEmpty || processedGrenades == 0) {
      return AutoTagSummary(
        processedGrenades: processedGrenades,
        matchedGrenades: 0,
        addedLinks: 0,
        removedLinks: 0,
        areaMatches: const {},
      );
    }

    final areaToGrenadeIds = <int, Set<int>>{};
    final matchedGrenadeIds = <int>{};
    final areaMatches = <String, int>{};

    for (final area in areas) {
      final candidatesRaw = area.layerId == null
          ? allGrenades
          : (grenadesByLayer[area.layerId!] ?? const <Grenade>[]);
      final candidates = useImpactPoint
          ? candidatesRaw
              .where((g) => g.impactXRatio != null && g.impactYRatio != null)
              .toList()
          : candidatesRaw;

      final matchedIds = <int>{};
      for (final grenade in candidates) {
        final x = useImpactPoint ? grenade.impactXRatio! : grenade.xRatio;
        final y = useImpactPoint ? grenade.impactYRatio! : grenade.yRatio;
        if (isPointInArea(x, y, area)) {
          matchedIds.add(grenade.id);
          matchedGrenadeIds.add(grenade.id);
        }
      }
      areaToGrenadeIds
          .putIfAbsent(area.tagId, () => <int>{})
          .addAll(matchedIds);
      areaMatches[area.name] =
          (areaMatches[area.name] ?? 0) + matchedIds.length;
    }

    int addedLinks = 0;
    int removedLinks = 0;

    await isar.writeTxn(() async {
      for (final area in areas) {
        final newIds = areaToGrenadeIds[area.tagId] ?? const <int>{};
        final existingLinks =
            await isar.grenadeTags.filter().tagIdEqualTo(area.tagId).findAll();

        final existingIds = <int>{};
        final seen = <int>{};
        for (final link in existingLinks) {
          final isDuplicate = !seen.add(link.grenadeId);
          if (isDuplicate || !newIds.contains(link.grenadeId)) {
            await isar.grenadeTags.delete(link.id);
            removedLinks++;
          } else {
            existingIds.add(link.grenadeId);
          }
        }

        for (final grenadeId in newIds) {
          if (!existingIds.contains(grenadeId)) {
            await isar.grenadeTags
                .put(GrenadeTag(grenadeId: grenadeId, tagId: area.tagId));
            addedLinks++;
          }
        }
      }
    });

    return AutoTagSummary(
      processedGrenades: processedGrenades,
      matchedGrenades: matchedGrenadeIds.length,
      addedLinks: addedLinks,
      removedLinks: removedLinks,
      areaMatches: areaMatches,
    );
  }

  /// 同步单个区域标签
  /// [useImpactPoint] 为 true 时，按爆点坐标判定；否则按站位坐标判定。
  Future<AreaTagSyncSummary> syncAreaTag(MapArea area,
      {bool useImpactPoint = false}) async {
    List<Grenade> grenades;
    if (area.layerId != null) {
      grenades = await isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(area.layerId!))
          .findAll();
    } else {
      final map = await isar.gameMaps.get(area.mapId);
      if (map == null) {
        return const AreaTagSyncSummary(
          processedGrenades: 0,
          matchedGrenades: 0,
          addedLinks: 0,
          removedLinks: 0,
        );
      }
      await map.layers.load();
      grenades = [];
      for (final layer in map.layers) {
        final layerGrenades = await isar.grenades
            .filter()
            .layer((q) => q.idEqualTo(layer.id))
            .findAll();
        grenades.addAll(layerGrenades);
      }
    }

    final candidates = useImpactPoint
        ? grenades
            .where((g) => g.impactXRatio != null && g.impactYRatio != null)
            .toList()
        : grenades;

    final matchedGrenadeIds = <int>{};
    for (final grenade in candidates) {
      final x = useImpactPoint ? grenade.impactXRatio! : grenade.xRatio;
      final y = useImpactPoint ? grenade.impactYRatio! : grenade.yRatio;
      if (isPointInArea(x, y, area)) {
        matchedGrenadeIds.add(grenade.id);
      }
    }

    int addedLinks = 0;
    int removedLinks = 0;

    await isar.writeTxn(() async {
      final existingLinks =
          await isar.grenadeTags.filter().tagIdEqualTo(area.tagId).findAll();

      final existingIds = <int>{};
      final seen = <int>{};

      for (final link in existingLinks) {
        final isDuplicate = !seen.add(link.grenadeId);
        if (isDuplicate || !matchedGrenadeIds.contains(link.grenadeId)) {
          await isar.grenadeTags.delete(link.id);
          removedLinks++;
        } else {
          existingIds.add(link.grenadeId);
        }
      }

      for (final grenadeId in matchedGrenadeIds) {
        if (!existingIds.contains(grenadeId)) {
          await isar.grenadeTags
              .put(GrenadeTag(grenadeId: grenadeId, tagId: area.tagId));
          addedLinks++;
        }
      }
    });

    return AreaTagSyncSummary(
      processedGrenades: candidates.length,
      matchedGrenades: matchedGrenadeIds.length,
      addedLinks: addedLinks,
      removedLinks: removedLinks,
    );
  }

  Future<int?> _resolveGrenadeLayerId(Grenade grenade) async {
    if (grenade.layer.value != null) {
      return grenade.layer.value!.id;
    }
    await grenade.layer.load();
    return grenade.layer.value?.id;
  }

  Future<Set<int>> _getAreaTagIds(int mapId) async {
    final areas = await getAreas(mapId);
    return areas.map((a) => a.tagId).toSet();
  }

  /// 解析笔画JSON（仅保留涂画模式数据结构）
  List<_AreaStroke> _parseStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      return data.map((stroke) {
        if (stroke is Map) {
          final pointsRaw = (stroke['q'] as List?) ??
              (stroke['points'] as List?) ??
              (stroke['p'] as List?) ??
              const [];
          final widthRatio = _normalizeWidthRatio(
            ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))
                ?.toDouble(),
          ).clamp(_minBrushRatio, _maxBrushRatio);
          final isEraser = _parseIsEraser(stroke['isEraser'] ?? stroke['e']);
          final points =
              _parseStrokePoints(pointsRaw, isDeltaPacked: stroke['q'] != null);
          return _AreaStroke(
            points: points,
            widthRatio: widthRatio,
            isEraser: isEraser,
          );
        }

        final points =
            stroke is List ? _parseStrokePoints(stroke) : const <Offset>[];
        return _AreaStroke(
          points: points,
          widthRatio: _defaultBrushRatio,
          isEraser: false,
        );
      }).toList();
    } catch (e) {
      return [];
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

  bool _isPointOnStroke(Offset point, _AreaStroke stroke) {
    final points = stroke.points;
    final radius =
        (stroke.widthRatio / 2).clamp(_minBrushRatio / 2, _maxBrushRatio / 2);
    final radiusSquared = radius * radius;

    if (points.length == 1) {
      final dx = point.dx - points.first.dx;
      final dy = point.dy - points.first.dy;
      return dx * dx + dy * dy <= radiusSquared;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final d2 = _distanceSquaredToSegment(point, points[i], points[i + 1]);
      if (d2 <= radiusSquared) {
        return true;
      }
    }
    return false;
  }

  double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;

    if (abLen2 <= 1e-12) {
      final dx = p.dx - a.dx;
      final dy = p.dy - a.dy;
      return dx * dx + dy * dy;
    }

    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLen2).clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    final dx = p.dx - closest.dx;
    final dy = p.dy - closest.dy;
    return dx * dx + dy * dy;
  }
}

class _AreaStroke {
  final List<Offset> points;
  final double widthRatio;
  final bool isEraser;

  const _AreaStroke({
    required this.points,
    required this.widthRatio,
    required this.isEraser,
  });
}
