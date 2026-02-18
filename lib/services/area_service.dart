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
  }) async {
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

    // 创建区域
    final area = MapArea(
      name: name,
      colorValue: colorValue,
      strokes: strokes,
      mapId: mapId,
      layerId: layerId,
      tagId: tag.id,
      createdAt: DateTime.now(),
    );
    await isar.writeTxn(() async {
      await isar.mapAreas.put(area);
    });

    return area;
  }

  /// 删除区域及其标签
  Future<void> deleteArea(MapArea area) async {
    await isar.writeTxn(() async {
      // 删除标签关联
      await isar.grenadeTags.filter().tagIdEqualTo(area.tagId).deleteAll();
      await isar.tags.delete(area.tagId);
      await isar.mapAreas.delete(area.id);
    });
  }

  /// 更新区域及其标签
  Future<void> updateArea({
    required MapArea area,
    required String name,
    required int colorValue,
    required String strokes,
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
      await isar.mapAreas.put(area);
    });
  }

  /// 判断点是否在区域内 (基于笔画围成的区域)
  bool isPointInArea(double x, double y, MapArea area) {
    final strokes = _parseStrokes(area.strokes);
    if (strokes.isEmpty) return false;

    final point = Offset(x, y);

    // 每条笔画都是一个独立闭合区域，命中任意一条即视为命中该区域
    for (final stroke in strokes) {
      if (stroke.length < 3) continue;
      if (_isPointInPolygon(point, stroke)) {
        return true;
      }
    }
    return false;
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
  Future<AutoTagSummary> autoTagAllGrenades(int mapId) async {
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

    if (areas.isEmpty || allGrenades.isEmpty) {
      return AutoTagSummary(
        processedGrenades: allGrenades.length,
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
      final candidates = area.layerId == null
          ? allGrenades
          : (grenadesByLayer[area.layerId!] ?? const <Grenade>[]);
      final matchedIds = <int>{};
      for (final grenade in candidates) {
        if (isPointInArea(grenade.xRatio, grenade.yRatio, area)) {
          matchedIds.add(grenade.id);
          matchedGrenadeIds.add(grenade.id);
        }
      }
      areaToGrenadeIds[area.tagId] = matchedIds;
      areaMatches[area.name] = matchedIds.length;
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
      processedGrenades: allGrenades.length,
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

  /// 解析笔画JSON
  List<List<Offset>> _parseStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      return data.map((stroke) {
        final points = stroke as List;
        return points
            .map((p) =>
                Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList();
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 使用 Path.contains 判断点是否在笔画闭合区域内
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;

    double minX = polygon.first.dx;
    double maxX = polygon.first.dx;
    double minY = polygon.first.dy;
    double maxY = polygon.first.dy;
    for (final p in polygon) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (point.dx < minX ||
        point.dx > maxX ||
        point.dy < minY ||
        point.dy > maxY) {
      return false;
    }

    final path = Path()..fillType = PathFillType.evenOdd;
    path.moveTo(polygon.first.dx, polygon.first.dy);

    if (polygon.length < 3) {
      for (int i = 1; i < polygon.length; i++) {
        path.lineTo(polygon[i].dx, polygon[i].dy);
      }
    } else {
      // 与绘制页保持一致：使用二次贝塞尔平滑
      for (int i = 1; i < polygon.length - 1; i++) {
        final p1 = polygon[i];
        final p2 = polygon[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      final last = polygon.last;
      path.lineTo(last.dx, last.dy);
    }

    path.close();
    return path.contains(point);
  }
}
