import 'package:path/path.dart' as p;
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import 'data_service.dart';
import 'favorite_folder_service.dart';
import 'tag_service.dart';

class MapManagementService {
  final Isar isar;
  final DataService _dataService;
  final TagService _tagService;
  final FavoriteFolderService _favoriteFolderService;

  MapManagementService(this.isar)
      : _dataService = DataService(isar),
        _tagService = TagService(isar),
        _favoriteFolderService = FavoriteFolderService(isar);

  static bool isCustomMap(GameMap map) {
    return !_isAssetPath(map.backgroundPath);
  }

  static bool _isAssetPath(String path) {
    return path.trim().startsWith('assets/');
  }

  Future<int> deleteCustomMaps(List<GameMap> maps) async {
    final targets = maps.where(isCustomMap).toList(growable: false);
    if (targets.isEmpty) return 0;

    for (final map in targets) {
      await _deleteMapCompletely(map);
    }
    return targets.length;
  }

  Future<void> _deleteMapCompletely(GameMap map) async {
    await map.layers.load();
    final filesToDelete = _collectMapAssetFilesToDelete(map);
    final layerIds = map.layers.map((e) => e.id).toList(growable: false);

    await _dataService.deleteAllGrenadesForMap(map);

    for (final layerId in layerIds) {
      final groups =
          await isar.impactGroups.filter().layerIdEqualTo(layerId).findAll();
      for (final group in groups) {
        await _dataService.deleteImpactGroup(group);
      }
    }

    final tags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
    for (final tag in tags) {
      await _tagService.deleteTag(tag.id, deleteRelatedAreas: true);
    }

    final remainingAreas =
        await isar.mapAreas.filter().mapIdEqualTo(map.id).findAll();
    if (remainingAreas.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.mapAreas
            .deleteAll(remainingAreas.map((e) => e.id).toList(growable: false));
      });
    }

    final folders = await _favoriteFolderService.getFoldersByMap(map.id);
    for (final folder in folders) {
      await _favoriteFolderService.deleteFolder(
        folder.id,
        FavoriteFolderDeleteStrategy.unfavorite,
      );
    }

    await isar.writeTxn(() async {
      await isar.mapLayers.deleteAll(layerIds);
      await isar.gameMaps.delete(map.id);
    });
    await _tagService.clearDeletedSystemTagRecordsForMap(map.id);

    if (filesToDelete.isNotEmpty) {
      await DataService.deleteMediaFiles(filesToDelete.toList(growable: false));
    }
  }

  Set<String> _collectMapAssetFilesToDelete(GameMap map) {
    final dataDir = (isar.directory ?? '').trim();
    final files = <String>{};

    void collect(String rawPath) {
      final trimmed = rawPath.trim();
      if (trimmed.isEmpty || _isAssetPath(trimmed)) return;
      if (dataDir.isEmpty) return;
      final normalizedPath = p.normalize(trimmed);
      final normalizedDataDir = p.normalize(dataDir);
      if (p.equals(normalizedPath, normalizedDataDir) ||
          p.isWithin(normalizedDataDir, normalizedPath)) {
        files.add(normalizedPath);
      }
    }

    collect(map.backgroundPath);
    collect(map.iconPath);
    for (final layer in map.layers) {
      collect(layer.assetPath);
    }
    return files;
  }
}
