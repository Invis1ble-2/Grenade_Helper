import 'dart:async';

import 'package:isar_community/isar.dart';

import '../models.dart';

enum FavoriteFolderDeleteStrategy {
  moveToDefault,
  unfavorite,
}

class FolderWithGrenades {
  final FavoriteFolder folder;
  final List<Grenade> grenades;

  const FolderWithGrenades({
    required this.folder,
    required this.grenades,
  });
}

class FavoriteFolderService {
  static const String defaultFolderName = '默认收藏夹';

  final Isar isar;

  const FavoriteFolderService(this.isar);

  String normalizeFolderName(String value) {
    return value.trim().toLowerCase();
  }

  bool isDefaultFolder(FavoriteFolder folder) {
    return normalizeFolderName(folder.name) ==
        normalizeFolderName(defaultFolderName);
  }

  Future<List<FavoriteFolder>> getFoldersByMap(int mapId) async {
    final folders =
        await isar.favoriteFolders.filter().mapIdEqualTo(mapId).findAll();
    folders.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.createdAt.compareTo(b.createdAt);
    });
    return folders;
  }

  Future<FavoriteFolder?> _findByNameKey(int mapId, String nameKey) async {
    final folders =
        await isar.favoriteFolders.filter().mapIdEqualTo(mapId).findAll();
    for (final folder in folders) {
      if (folder.nameKey == nameKey) return folder;
    }
    return null;
  }

  Future<FavoriteFolder?> getFolderById(int folderId) async {
    return isar.favoriteFolders.get(folderId);
  }

  Future<FavoriteFolder> getOrCreateDefaultFolder(int mapId) async {
    final defaultKey = normalizeFolderName(defaultFolderName);
    final existing = await _findByNameKey(mapId, defaultKey);
    if (existing != null) return existing;
    return createFolder(mapId, defaultFolderName);
  }

  Future<FavoriteFolder> createFolder(int mapId, String name) async {
    final displayName = name.trim();
    if (displayName.isEmpty) {
      throw StateError('收藏夹名称不能为空');
    }

    final nameKey = normalizeFolderName(displayName);
    final duplicated = await _findByNameKey(mapId, nameKey);
    if (duplicated != null) {
      throw StateError('收藏夹名称已存在');
    }

    final existing = await getFoldersByMap(mapId);
    final sortOrder = existing.isEmpty ? 0 : existing.last.sortOrder + 1;
    final now = DateTime.now();
    final folder = FavoriteFolder(
      mapId: mapId,
      name: displayName,
      nameKey: nameKey,
      sortOrder: sortOrder,
      created: now,
      updated: now,
    );

    await isar.writeTxn(() async {
      await isar.favoriteFolders.put(folder);
    });
    return folder;
  }

  Future<void> renameFolder(int folderId, String newName) async {
    final folder = await isar.favoriteFolders.get(folderId);
    if (folder == null) return;

    final displayName = newName.trim();
    if (displayName.isEmpty) {
      throw StateError('收藏夹名称不能为空');
    }

    final newKey = normalizeFolderName(displayName);
    if (newKey == folder.nameKey) return;

    final duplicated = await _findByNameKey(folder.mapId, newKey);
    if (duplicated != null && duplicated.id != folder.id) {
      throw StateError('收藏夹名称已存在');
    }

    folder.name = displayName;
    folder.nameKey = newKey;
    folder.updatedAt = DateTime.now();

    await isar.writeTxn(() async {
      await isar.favoriteFolders.put(folder);
    });
  }

  Future<List<Grenade>> _getFavoriteGrenadesInFolder(int folderId) async {
    return isar.grenades
        .filter()
        .isFavoriteEqualTo(true)
        .favoriteFolderIdEqualTo(folderId)
        .findAll();
  }

  Future<int> _resolveGrenadeMapId(Grenade grenade) async {
    await grenade.layer.load();
    final layer = grenade.layer.value;
    if (layer == null) {
      throw StateError('道具未关联楼层');
    }
    await layer.map.load();
    final map = layer.map.value;
    if (map == null) {
      throw StateError('楼层未关联地图');
    }
    return map.id;
  }

  Future<List<Grenade>> getMapFavoriteGrenades(int mapId) async {
    return isar.grenades
        .filter()
        .isFavoriteEqualTo(true)
        .layer((q) => q.map((m) => m.idEqualTo(mapId)))
        .findAll();
  }

  Future<List<FolderWithGrenades>> loadMapFavorites(int mapId) async {
    final folders = await getFoldersByMap(mapId);
    final favorites = await getMapFavoriteGrenades(mapId);
    final grouped = <int, List<Grenade>>{};

    for (final grenade in favorites) {
      final folderId = grenade.favoriteFolderId;
      if (folderId == null) continue;
      grouped.putIfAbsent(folderId, () => <Grenade>[]).add(grenade);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    return folders
        .map((f) =>
            FolderWithGrenades(folder: f, grenades: grouped[f.id] ?? const []))
        .toList();
  }

  Stream<List<FolderWithGrenades>> watchMapFavorites(int mapId) {
    late final StreamController<List<FolderWithGrenades>> controller;
    StreamSubscription<void>? folderSub;
    StreamSubscription<void>? grenadeSub;

    Future<void> emit() async {
      if (controller.isClosed) return;
      try {
        final data = await loadMapFavorites(mapId);
        if (!controller.isClosed) {
          controller.add(data);
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    controller = StreamController<List<FolderWithGrenades>>(
      onListen: () {
        folderSub = isar.favoriteFolders
            .filter()
            .mapIdEqualTo(mapId)
            .watchLazy(fireImmediately: true)
            .listen((_) {
          emit();
        });
        grenadeSub = isar.grenades
            .filter()
            .layer((q) => q.map((m) => m.idEqualTo(mapId)))
            .watchLazy(fireImmediately: true)
            .listen((_) {
          emit();
        });
      },
      onCancel: () async {
        await folderSub?.cancel();
        await grenadeSub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> setFavorite(int grenadeId,
      {required bool favorite, int? folderId}) async {
    final grenade = await isar.grenades.get(grenadeId);
    if (grenade == null) return;

    if (!favorite) {
      await isar.writeTxn(() async {
        grenade.isFavorite = false;
        grenade.favoriteFolderId = null;
        grenade.updatedAt = DateTime.now();
        await isar.grenades.put(grenade);
      });
      return;
    }

    final mapId = await _resolveGrenadeMapId(grenade);
    FavoriteFolder folder;

    if (folderId != null) {
      final target = await isar.favoriteFolders.get(folderId);
      if (target == null) {
        throw StateError('目标收藏夹不存在');
      }
      if (target.mapId != mapId) {
        throw StateError('不能跨地图收藏到其他收藏夹');
      }
      folder = target;
    } else {
      folder = await getOrCreateDefaultFolder(mapId);
    }

    await isar.writeTxn(() async {
      grenade.isFavorite = true;
      grenade.favoriteFolderId = folder.id;
      grenade.updatedAt = DateTime.now();
      await isar.grenades.put(grenade);
    });
  }

  Future<void> moveFavorite(int grenadeId, int targetFolderId) async {
    final grenade = await isar.grenades.get(grenadeId);
    if (grenade == null) return;

    final targetFolder = await isar.favoriteFolders.get(targetFolderId);
    if (targetFolder == null) {
      throw StateError('目标收藏夹不存在');
    }

    final grenadeMapId = await _resolveGrenadeMapId(grenade);
    if (grenadeMapId != targetFolder.mapId) {
      throw StateError('不能移动到其他地图收藏夹');
    }

    await isar.writeTxn(() async {
      grenade.isFavorite = true;
      grenade.favoriteFolderId = targetFolder.id;
      grenade.updatedAt = DateTime.now();
      await isar.grenades.put(grenade);
    });
  }

  Future<void> deleteFolder(
      int folderId, FavoriteFolderDeleteStrategy strategy) async {
    final folder = await isar.favoriteFolders.get(folderId);
    if (folder == null) return;

    final folderGrenades = await _getFavoriteGrenadesInFolder(folder.id);
    FavoriteFolder? moveTarget;

    if (folderGrenades.isNotEmpty &&
        strategy == FavoriteFolderDeleteStrategy.moveToDefault) {
      if (isDefaultFolder(folder)) {
        throw StateError('默认收藏夹不可使用“迁移到默认收藏夹”删除');
      }
      moveTarget = await getOrCreateDefaultFolder(folder.mapId);
    }

    await isar.writeTxn(() async {
      if (folderGrenades.isNotEmpty) {
        if (strategy == FavoriteFolderDeleteStrategy.unfavorite) {
          for (final grenade in folderGrenades) {
            grenade.isFavorite = false;
            grenade.favoriteFolderId = null;
            grenade.updatedAt = DateTime.now();
            await isar.grenades.put(grenade);
          }
        } else if (moveTarget != null) {
          for (final grenade in folderGrenades) {
            grenade.isFavorite = true;
            grenade.favoriteFolderId = moveTarget.id;
            grenade.updatedAt = DateTime.now();
            await isar.grenades.put(grenade);
          }
        }
      }
      await isar.favoriteFolders.delete(folder.id);
    });
  }
}
