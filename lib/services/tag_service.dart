import 'package:isar_community/isar.dart';
import '../models/tag.dart';
import '../models/grenade_tag.dart';
import '../data/map_area_presets.dart';
import '../models.dart';

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
  }

  /// 获取地图的所有标签 (按维度分组)
  Future<Map<int, List<Tag>>> getTagsByDimension(int mapId) async {
    final tags = await isar.tags.filter().mapIdEqualTo(mapId).sortBySortOrder().findAll();
    final grouped = <int, List<Tag>>{};
    for (final tag in tags) {
      grouped.putIfAbsent(tag.dimension, () => []).add(tag);
    }
    return grouped;
  }

  /// 获取地图的所有标签
  Future<List<Tag>> getAllTags(int mapId) async {
    return await isar.tags.filter().mapIdEqualTo(mapId).sortBySortOrder().findAll();
  }

  /// 创建标签
  Future<Tag> createTag(int mapId, String name, int color, {int dimension = TagDimension.custom}) async {
    final maxOrder = await isar.tags.filter().mapIdEqualTo(mapId).sortBySortOrderDesc().findFirst();
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
    final exists = await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).and().tagIdEqualTo(tagId).findFirst();
    if (exists != null) return;
    await isar.writeTxn(() async {
      await isar.grenadeTags.put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
    });
  }

  /// 移除道具标签
  Future<void> removeTagFromGrenade(int grenadeId, int tagId) async {
    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).and().tagIdEqualTo(tagId).deleteAll();
    });
  }

  /// 获取道具的所有标签ID
  Future<Set<int>> getGrenadeTagIds(int grenadeId) async {
    final grenadeTags = await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).findAll();
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
  Future<List<Grenade>> filterByTags(List<Grenade> grenades, Set<int> selectedTagIds) async {
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
  Future<Map<String, List<Grenade>>> getTacticalPackages(List<Grenade> grenades) async {
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
        await isar.grenadeTags.put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
      }
    });
  }
}
