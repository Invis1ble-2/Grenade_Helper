import 'package:isar_community/isar.dart';
import '../models/tag.dart';
import '../models/grenade_tag.dart';
import '../data/map_area_presets.dart';
import '../data/builtin_area_region_presets.dart';
import '../models/map_area.dart';
import '../models.dart';

class DefaultAreaTagReimportSummary {
  final int processedMaps;
  final int mapsWithPresets;
  final int addedTags;
  final int updatedTags;
  final int mapsWithAreaData;
  final int addedAreas;
  final int updatedAreas;
  final int removedDuplicateAreas;

  const DefaultAreaTagReimportSummary({
    required this.processedMaps,
    required this.mapsWithPresets,
    required this.addedTags,
    required this.updatedTags,
    required this.mapsWithAreaData,
    required this.addedAreas,
    required this.updatedAreas,
    required this.removedDuplicateAreas,
  });
}

class TagService {
  final Isar isar;

  TagService(this.isar);

  /// 初始化地图的系统标签
  Future<void> initializeSystemTags(int mapId, String mapName) async {
    final existingTags = await isar.tags.filter().mapIdEqualTo(mapId).count();
    if (existingTags > 0) return;

    await isar.writeTxn(() async {
      int order = 0;
      for (final entry in commonSystemTags.entries) {
        final dimension = entry.key;
        final color = dimensionColors[dimension] ?? 0xFF607D8B;
        for (final name in entry.value) {
          await isar.tags.put(Tag(
            name: name,
            colorValue: color,
            dimension: dimension,
            isSystem: true,
            sortOrder: order++,
            mapId: mapId,
          ));
        }
      }
      final mapKey = mapName.toLowerCase();
      final areaNames = mapAreaPresets[mapKey];
      if (areaNames != null) {
        final areaColor = dimensionColors[TagDimension.area] ?? 0xFF4CAF50;
        for (final name in areaNames) {
          await isar.tags.put(Tag(
            name: name,
            colorValue: areaColor,
            dimension: TagDimension.area,
            isSystem: true,
            sortOrder: order++,
            mapId: mapId,
          ));
        }
      }
    });

    // 首次初始化时尝试导入内置区域几何数据（不覆盖任何已有区域）。
    final map = await isar.gameMaps.get(mapId);
    if (map == null) return;
    await _reimportBuiltinAreaDataForMap(
      map,
      overwriteExisting: false,
    );
  }

  /// 为所有地图补齐默认区域标签（非破坏性，不删除现有标签）
  Future<DefaultAreaTagReimportSummary>
      reimportDefaultAreaTagsForAllMaps() async {
    final maps = await isar.gameMaps.where().findAll();
    if (maps.isEmpty) {
      return const DefaultAreaTagReimportSummary(
        processedMaps: 0,
        mapsWithPresets: 0,
        addedTags: 0,
        updatedTags: 0,
        mapsWithAreaData: 0,
        addedAreas: 0,
        updatedAreas: 0,
        removedDuplicateAreas: 0,
      );
    }

    final areaColor = dimensionColors[TagDimension.area] ?? 0xFF4CAF50;
    int mapsWithPresets = 0;
    int addedTags = 0;
    int updatedTags = 0;
    int mapsWithAreaData = 0;
    int addedAreas = 0;
    int updatedAreas = 0;
    int removedDuplicateAreas = 0;

    for (final map in maps) {
      final presetNames = _resolveAreaPresetNames(map) ?? const <String>[];
      final builtinAreaData = _resolveBuiltinAreaRegionPresets(map) ??
          const <String, List<BuiltinAreaPreset>>{};

      final requiredNames = <String>{
        ...presetNames,
        ...builtinAreaData.values.expand((list) => list.map((e) => e.name)),
      };
      if (requiredNames.isEmpty) continue;

      if (presetNames.isNotEmpty) {
        mapsWithPresets++;
      }
      if (builtinAreaData.isNotEmpty) {
        mapsWithAreaData++;
      }

      final existingAreaTags = await isar.tags
          .filter()
          .mapIdEqualTo(map.id)
          .dimensionEqualTo(TagDimension.area)
          .findAll();
      final existingByName = {
        for (final tag in existingAreaTags) tag.name: tag
      };

      final maxOrderTag = await isar.tags
          .filter()
          .mapIdEqualTo(map.id)
          .sortBySortOrderDesc()
          .findFirst();
      int nextOrder = (maxOrderTag?.sortOrder ?? 0) + 1;

      final toCreate = <Tag>[];
      final toUpdate = <Tag>[];

      for (final name in requiredNames) {
        final existing = existingByName[name];
        if (existing == null) {
          toCreate.add(Tag(
            name: name,
            colorValue: areaColor,
            dimension: TagDimension.area,
            isSystem: true,
            sortOrder: nextOrder++,
            mapId: map.id,
          ));
          continue;
        }

        if (existing.isSystem && existing.colorValue != areaColor) {
          existing.colorValue = areaColor;
          toUpdate.add(existing);
        }
      }

      if (toCreate.isNotEmpty || toUpdate.isNotEmpty) {
        await isar.writeTxn(() async {
          for (final tag in toCreate) {
            await isar.tags.put(tag);
          }
          for (final tag in toUpdate) {
            await isar.tags.put(tag);
          }
        });

        addedTags += toCreate.length;
        updatedTags += toUpdate.length;
      }

      final upsertSummary = await _reimportBuiltinAreaDataForMap(
        map,
        overwriteExisting: true,
      );
      addedAreas += upsertSummary.addedAreas;
      updatedAreas += upsertSummary.updatedAreas;
      removedDuplicateAreas += upsertSummary.removedDuplicateAreas;
    }

    return DefaultAreaTagReimportSummary(
      processedMaps: maps.length,
      mapsWithPresets: mapsWithPresets,
      addedTags: addedTags,
      updatedTags: updatedTags,
      mapsWithAreaData: mapsWithAreaData,
      addedAreas: addedAreas,
      updatedAreas: updatedAreas,
      removedDuplicateAreas: removedDuplicateAreas,
    );
  }

  List<String>? _resolveAreaPresetNames(GameMap map) {
    final lowerName = map.name.trim().toLowerCase();
    if (mapAreaPresets.containsKey(lowerName)) {
      return mapAreaPresets[lowerName];
    }

    final iconPath = map.iconPath;
    final iconMatch = RegExp(
      r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
      caseSensitive: false,
    ).firstMatch(iconPath);
    if (iconMatch != null && iconMatch.groupCount >= 1) {
      final key = iconMatch.group(1)?.toLowerCase();
      if (key != null && mapAreaPresets.containsKey(key)) {
        return mapAreaPresets[key];
      }
    }

    final normalized = lowerName.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return mapAreaPresets[normalized];
  }

  Map<String, List<BuiltinAreaPreset>>? _resolveBuiltinAreaRegionPresets(
      GameMap map) {
    final lowerName = map.name.trim().toLowerCase();
    if (builtinAreaRegionPresets.containsKey(lowerName)) {
      return builtinAreaRegionPresets[lowerName];
    }

    final iconPath = map.iconPath;
    final iconMatch = RegExp(
      r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
      caseSensitive: false,
    ).firstMatch(iconPath);
    if (iconMatch != null && iconMatch.groupCount >= 1) {
      final key = iconMatch.group(1)?.toLowerCase();
      if (key != null && builtinAreaRegionPresets.containsKey(key)) {
        return builtinAreaRegionPresets[key];
      }
    }

    final normalized = lowerName.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return builtinAreaRegionPresets[normalized];
  }

  Future<_BuiltinAreaUpsertSummary> _reimportBuiltinAreaDataForMap(
    GameMap map, {
    required bool overwriteExisting,
  }) async {
    final presetByFloor = _resolveBuiltinAreaRegionPresets(map);
    if (presetByFloor == null || presetByFloor.isEmpty) {
      return const _BuiltinAreaUpsertSummary(
        addedAreas: 0,
        updatedAreas: 0,
        removedDuplicateAreas: 0,
      );
    }

    await map.layers.load();
    final layers = map.layers.toList();
    if (layers.isEmpty) {
      return const _BuiltinAreaUpsertSummary(
        addedAreas: 0,
        updatedAreas: 0,
        removedDuplicateAreas: 0,
      );
    }

    final layerByFloorKey = <String, MapLayer>{};
    for (final layer in layers) {
      final fileName = _extractFileName(layer.assetPath).toLowerCase();
      layerByFloorKey[fileName] = layer;
      layerByFloorKey[_stripFileExtension(fileName)] = layer;
    }

    final areaTags = await isar.tags
        .filter()
        .mapIdEqualTo(map.id)
        .dimensionEqualTo(TagDimension.area)
        .findAll();
    final tagByName = <String, Tag>{for (final tag in areaTags) tag.name: tag};

    final existingAreas =
        await isar.mapAreas.filter().mapIdEqualTo(map.id).findAll();
    final grouped = <String, List<MapArea>>{};
    for (final area in existingAreas) {
      final layerId = area.layerId;
      if (layerId == null) continue;
      final key = '${area.tagId}:$layerId';
      grouped.putIfAbsent(key, () => []).add(area);
    }

    int addedAreas = 0;
    int updatedAreas = 0;
    final deleteIds = <int>{};
    final toPut = <MapArea>[];

    for (final entry in presetByFloor.entries) {
      final floorKey = entry.key.toLowerCase();
      final layer = layerByFloorKey[floorKey] ??
          layerByFloorKey[_stripFileExtension(floorKey)];
      if (layer == null) continue;

      for (final preset in entry.value) {
        final tag = tagByName[preset.name];
        if (tag == null) continue;

        final key = '${tag.id}:${layer.id}';
        final currentList = grouped[key] ?? const <MapArea>[];

        MapArea? newest;
        if (currentList.isNotEmpty) {
          newest = currentList.reduce((a, b) => _isAreaNewer(a, b) ? a : b);
          for (final area in currentList) {
            if (area.id != newest.id) {
              deleteIds.add(area.id);
            }
          }
        }

        if (newest == null) {
          toPut.add(MapArea(
            name: preset.name,
            colorValue: preset.colorValue,
            strokes: preset.strokesJson,
            mapId: map.id,
            layerId: layer.id,
            tagId: tag.id,
            createdAt: DateTime.now(),
          ));
          addedAreas++;
          continue;
        }

        if (!overwriteExisting) continue;

        final changed = newest.name != preset.name ||
            newest.colorValue != preset.colorValue ||
            newest.strokes != preset.strokesJson ||
            newest.layerId != layer.id ||
            newest.tagId != tag.id;

        if (changed) {
          newest.name = preset.name;
          newest.colorValue = preset.colorValue;
          newest.strokes = preset.strokesJson;
          newest.layerId = layer.id;
          newest.tagId = tag.id;
          toPut.add(newest);
          updatedAreas++;
        }
      }
    }

    if (toPut.isNotEmpty || deleteIds.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final area in toPut) {
          await isar.mapAreas.put(area);
        }
        for (final id in deleteIds) {
          await isar.mapAreas.delete(id);
        }
      });
    }

    return _BuiltinAreaUpsertSummary(
      addedAreas: addedAreas,
      updatedAreas: updatedAreas,
      removedDuplicateAreas: deleteIds.length,
    );
  }

  bool _isAreaNewer(MapArea a, MapArea b) {
    if (a.createdAt.isAfter(b.createdAt)) return true;
    if (a.createdAt.isBefore(b.createdAt)) return false;
    return a.id > b.id;
  }

  String _extractFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _stripFileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return fileName;
    return fileName.substring(0, dot);
  }

  /// 获取地图的所有标签 (按维度分组)
  Future<Map<int, List<Tag>>> getTagsByDimension(int mapId) async {
    final tags = await isar.tags
        .filter()
        .mapIdEqualTo(mapId)
        .sortBySortOrder()
        .findAll();
    final grouped = <int, List<Tag>>{};
    for (final tag in tags) {
      grouped.putIfAbsent(tag.dimension, () => []).add(tag);
    }
    return grouped;
  }

  /// 获取地图的所有标签
  Future<List<Tag>> getAllTags(int mapId) async {
    return await isar.tags
        .filter()
        .mapIdEqualTo(mapId)
        .sortBySortOrder()
        .findAll();
  }

  /// 创建标签
  Future<Tag> createTag(int mapId, String name, int color,
      {int dimension = TagDimension.custom}) async {
    final maxOrder = await isar.tags
        .filter()
        .mapIdEqualTo(mapId)
        .sortBySortOrderDesc()
        .findFirst();
    final tag = Tag(
      name: name,
      colorValue: color,
      dimension: dimension,
      isSystem: false,
      sortOrder: (maxOrder?.sortOrder ?? 0) + 1,
      mapId: mapId,
    );
    await isar.writeTxn(() async {
      await isar.tags.put(tag);
    });
    return tag;
  }

  /// 更新标签
  Future<void> updateTag(Tag tag) async {
    await isar.writeTxn(() async {
      await isar.tags.put(tag);
    });
  }

  /// 删除标签
  Future<void> deleteTag(int tagId) async {
    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().tagIdEqualTo(tagId).deleteAll();
      await isar.tags.delete(tagId);
    });
  }

  /// 为道具添加标签
  Future<void> addTagToGrenade(int grenadeId, int tagId) async {
    final exists = await isar.grenadeTags
        .filter()
        .grenadeIdEqualTo(grenadeId)
        .and()
        .tagIdEqualTo(tagId)
        .findFirst();
    if (exists != null) return;
    await isar.writeTxn(() async {
      await isar.grenadeTags
          .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
    });
  }

  /// 移除道具标签
  Future<void> removeTagFromGrenade(int grenadeId, int tagId) async {
    await isar.writeTxn(() async {
      await isar.grenadeTags
          .filter()
          .grenadeIdEqualTo(grenadeId)
          .and()
          .tagIdEqualTo(tagId)
          .deleteAll();
    });
  }

  /// 获取道具的所有标签ID
  Future<Set<int>> getGrenadeTagIds(int grenadeId) async {
    final grenadeTags =
        await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).findAll();
    return grenadeTags.map((gt) => gt.tagId).toSet();
  }

  /// 获取道具的所有标签
  Future<List<Tag>> getGrenadeTags(int grenadeId) async {
    final tagIds = await getGrenadeTagIds(grenadeId);
    if (tagIds.isEmpty) return [];
    final tags = <Tag>[];
    for (final id in tagIds) {
      final tag = await isar.tags.get(id);
      if (tag != null) tags.add(tag);
    }
    return tags;
  }

  /// 按标签筛选道具 (并集筛选 - 道具只需包含任一选中标签)
  Future<List<Grenade>> filterByTags(
      List<Grenade> grenades, Set<int> selectedTagIds) async {
    if (selectedTagIds.isEmpty) return grenades;
    final result = <Grenade>[];
    for (final grenade in grenades) {
      final grenadeTags = await getGrenadeTagIds(grenade.id);
      if (selectedTagIds.any((t) => grenadeTags.contains(t))) {
        result.add(grenade);
      }
    }
    return result;
  }

  /// 获取战术包 (相同标签组合的道具集合)
  Future<Map<String, List<Grenade>>> getTacticalPackages(
      List<Grenade> grenades) async {
    final packages = <String, List<Grenade>>{};
    for (final grenade in grenades) {
      final tagIds = await getGrenadeTagIds(grenade.id);
      if (tagIds.isEmpty) continue;
      final key = (tagIds.toList()..sort()).join(',');
      packages.putIfAbsent(key, () => []).add(grenade);
    }
    return packages;
  }

  /// 批量设置道具标签
  Future<void> setGrenadeTags(int grenadeId, Set<int> tagIds) async {
    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).deleteAll();
      for (final tagId in tagIds) {
        await isar.grenadeTags
            .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
      }
    });
  }
}

class _BuiltinAreaUpsertSummary {
  final int addedAreas;
  final int updatedAreas;
  final int removedDuplicateAreas;

  const _BuiltinAreaUpsertSummary({
    required this.addedAreas,
    required this.updatedAreas,
    required this.removedDuplicateAreas,
  });
}
