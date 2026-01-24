import 'dart:convert';
import 'dart:ui';
import 'package:isar_community/isar.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../models/grenade_tag.dart';
import '../models.dart';

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

    // 合并所有笔画点形成边界
    final allPoints = <Offset>[];
    for (final stroke in strokes) {
      allPoints.addAll(stroke);
    }
    if (allPoints.length < 3) return false;

    // 使用射线法判断点是否在多边形内
    return _isPointInPolygon(Offset(x, y), allPoints);
  }

  /// 获取点所在的所有区域
  Future<List<MapArea>> getAreasForPoint(int mapId, double x, double y, {int? layerId}) async {
    final areas = await getAreas(mapId);
    return areas.where((area) {
      if (layerId != null && area.layerId != null && area.layerId != layerId) return false;
      return isPointInArea(x, y, area);
    }).toList();
  }

  /// 自动为道具添加区域标签
  Future<void> autoTagGrenade(Grenade grenade, int mapId) async {
    final areas = await getAreasForPoint(mapId, grenade.xRatio, grenade.yRatio);
    
    await isar.writeTxn(() async {
      for (final area in areas) {
        // 检查是否已有此标签
        final existing = await isar.grenadeTags.filter()
            .grenadeIdEqualTo(grenade.id)
            .tagIdEqualTo(area.tagId)
            .findFirst();
        if (existing == null) {
          await isar.grenadeTags.put(GrenadeTag(grenadeId: grenade.id, tagId: area.tagId));
        }
      }
    });
  }

  /// 批量为地图所有道具自动标签
  Future<int> autoTagAllGrenades(int mapId) async {
    final areas = await getAreas(mapId);
    if (areas.isEmpty) return 0;

    // 获取该地图所有道具
    final layers = await isar.mapLayers.filter().map((q) => q.idEqualTo(mapId)).findAll();
    int count = 0;
    
    for (final layer in layers) {
      final grenades = await isar.grenades.filter().layer((q) => q.idEqualTo(layer.id)).findAll();
      for (final grenade in grenades) {
        await autoTagGrenade(grenade, mapId);
        count++;
      }
    }
    return count;
  }

  /// 解析笔画JSON
  List<List<Offset>> _parseStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      return data.map((stroke) {
        final points = stroke as List;
        return points.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList();
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 射线法判断点是否在多边形内
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    int intersections = 0;
    final n = polygon.length;
    
    for (int i = 0; i < n; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % n];
      
      if ((p1.dy <= point.dy && p2.dy > point.dy) || (p2.dy <= point.dy && p1.dy > point.dy)) {
        final xIntersect = p1.dx + (point.dy - p1.dy) / (p2.dy - p1.dy) * (p2.dx - p1.dx);
        if (point.dx < xIntersect) {
          intersections++;
        }
      }
    }
    
    return intersections % 2 == 1;
  }
}
