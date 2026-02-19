import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../models.dart';
import 'tag_service.dart';

/// 迁移服务
class MigrationService {
  final Isar isar;
  const MigrationService(this.isar);
  static const String _defaultFolderName = '默认收藏夹';

  /// 生成UUID
  Future<int> migrateGrenadeUuids() async {
    // 查找空ID
    final allGrenades = await isar.grenades.where().findAll();
    final grenadesNeedingUuid = allGrenades
        .where((g) => g.uniqueId == null || g.uniqueId!.isEmpty)
        .toList();

    if (grenadesNeedingUuid.isEmpty) return 0;

    const uuid = Uuid();
    await isar.writeTxn(() async {
      for (final g in grenadesNeedingUuid) {
        // 加载关联
        await g.layer.load();
        await g.steps.load();

        // 生成
        g.uniqueId = uuid.v4();

        // 保存
        await isar.grenades.put(g);

        // 保存关联
        await g.layer.save();
        await g.steps.save();
      }
    });

    return grenadesNeedingUuid.length;
  }

  Future<int> migrateTagUuids() async {
    final tagService = TagService(isar);
    return tagService.ensureTagUuids();
  }

  String _normalizeName(String value) => value.trim().toLowerCase();

  Future<int> migrateFavoriteFolders() async {
    final allFolders = await isar.favoriteFolders.where().findAll();
    final folderById = <int, FavoriteFolder>{};
    final defaultFolderByMap = <int, FavoriteFolder>{};
    final foldersToFix = <FavoriteFolder>[];
    final defaultNameKey = _normalizeName(_defaultFolderName);

    for (final folder in allFolders) {
      folderById[folder.id] = folder;
      final normalized = _normalizeName(folder.name);
      if (folder.nameKey != normalized) {
        folder.nameKey = normalized;
        folder.updatedAt = DateTime.now();
        foldersToFix.add(folder);
      }
      if (normalized == defaultNameKey) {
        defaultFolderByMap[folder.mapId] = folder;
      }
    }

    if (foldersToFix.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.favoriteFolders.putAll(foldersToFix);
      });
    }

    Future<int> ensureDefaultFolderId(int mapId) async {
      final cached = defaultFolderByMap[mapId];
      if (cached != null) return cached.id;

      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(mapId).findAll();
      FavoriteFolder? folder;
      for (final item in folders) {
        if (_normalizeName(item.name) == defaultNameKey) {
          folder = item;
          break;
        }
      }

      if (folder == null) {
        final sortOrder = folders.isEmpty
            ? 0
            : folders.map((f) => f.sortOrder).reduce((a, b) => a > b ? a : b) +
                1;
        folder = FavoriteFolder(
          mapId: mapId,
          name: _defaultFolderName,
          nameKey: defaultNameKey,
          sortOrder: sortOrder,
        );
        await isar.writeTxn(() async {
          await isar.favoriteFolders.put(folder!);
        });
      }

      defaultFolderByMap[mapId] = folder;
      folderById[folder.id] = folder;
      return folder.id;
    }

    final allGrenades = await isar.grenades.where().findAll();
    if (allGrenades.isEmpty) return 0;

    final layerMapCache = <int, int>{};

    Future<int?> resolveMapId(Grenade grenade) async {
      await grenade.layer.load();
      final layer = grenade.layer.value;
      if (layer == null) return null;

      final cached = layerMapCache[layer.id];
      if (cached != null) return cached;

      await layer.map.load();
      final map = layer.map.value;
      if (map == null) return null;
      layerMapCache[layer.id] = map.id;
      return map.id;
    }

    final grenadesToFix = <Grenade>[];
    for (final grenade in allGrenades) {
      var changed = false;

      if (!grenade.isFavorite) {
        if (grenade.favoriteFolderId != null) {
          grenade.favoriteFolderId = null;
          changed = true;
        }
      } else {
        final mapId = await resolveMapId(grenade);
        if (mapId != null) {
          final folderId = grenade.favoriteFolderId;
          final folder = folderId == null ? null : folderById[folderId];
          final invalidFolder =
              folderId == null || folder == null || folder.mapId != mapId;
          if (invalidFolder) {
            grenade.favoriteFolderId = await ensureDefaultFolderId(mapId);
            changed = true;
          }
        }
      }

      if (changed) {
        grenade.updatedAt = DateTime.now();
        grenadesToFix.add(grenade);
      }
    }

    if (grenadesToFix.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.grenades.putAll(grenadesToFix);
      });
    }

    return grenadesToFix.length;
  }
}
