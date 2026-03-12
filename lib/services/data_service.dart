import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models.dart';
import '../models/tag.dart';
import '../models/map_area.dart';
import '../models/grenade_tag.dart';
import 'favorite_folder_service.dart';
import 'lan_sync/lan_sync_local_store.dart';

/// 导入状态
enum ImportStatus { newItem, update, skip }

/// 道具预览项
class GrenadePreviewItem {
  final Map<String, dynamic> rawData;
  final String uniqueId;
  final String title;
  final int type;
  final String mapName;
  final String layerName;
  final String? author;
  final ImportStatus status;
  final DateTime updatedAt;

  GrenadePreviewItem({
    required this.rawData,
    required this.uniqueId,
    required this.title,
    required this.type,
    required this.mapName,
    required this.layerName,
    this.author,
    required this.status,
    required this.updatedAt,
  });
}

/// 道具包预览结果
class PackagePreviewResult {
  final Map<String, List<GrenadePreviewItem>> grenadesByMap;
  final String filePath;
  final Map<String, List<int>> memoryImages;
  final int schemaVersion;
  final Map<String, PackageTagData> tagsByUuid;
  final List<PackageAreaData> areas;
  final List<PackageFavoriteFolderData> favoriteFolders;
  final List<PackageImpactGroupData> impactGroups;
  final List<PackageGrenadeTombstoneData> grenadeTombstones;
  final List<PackageEntityTombstoneData> entityTombstones;

  PackagePreviewResult({
    required this.grenadesByMap,
    required this.filePath,
    required this.memoryImages,
    this.schemaVersion = 1,
    this.tagsByUuid = const {},
    this.areas = const [],
    this.favoriteFolders = const [],
    this.impactGroups = const [],
    this.grenadeTombstones = const [],
    this.entityTombstones = const [],
  });

  bool get isMultiMap => mapNames.length > 1;

  int get totalCount =>
      grenadesByMap.values.fold(0, (sum, list) => sum + list.length);

  List<String> get mapNames {
    final ordered = <String>[];
    final seen = <String>{};
    for (final name in grenadesByMap.keys) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    for (final tombstone in grenadeTombstones) {
      final trimmed = tombstone.mapName.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    for (final tombstone in entityTombstones) {
      final trimmed = tombstone.mapName.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    for (final tag in tagsByUuid.values) {
      final trimmed = tag.mapName.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    for (final area in areas) {
      final trimmed = area.mapName.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    for (final folder in favoriteFolders) {
      final trimmed = folder.mapName.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    for (final group in impactGroups) {
      final trimmed = group.mapName.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      ordered.add(trimmed);
    }
    return ordered;
  }
}

class PackageGrenadeTombstoneData {
  final String uniqueId;
  final String mapName;
  final int deletedAt;

  const PackageGrenadeTombstoneData({
    required this.uniqueId,
    required this.mapName,
    required this.deletedAt,
  });

  factory PackageGrenadeTombstoneData.fromJson(Map<String, dynamic> json) {
    return PackageGrenadeTombstoneData(
      uniqueId: (json['uniqueId'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'uniqueId': uniqueId,
        'mapName': mapName,
        'deletedAt': deletedAt,
      };
}

class PackageEntityTombstoneData {
  final String entityType;
  final String entityKey;
  final String mapName;
  final int deletedAt;
  final Map<String, dynamic> payload;

  const PackageEntityTombstoneData({
    required this.entityType,
    required this.entityKey,
    required this.mapName,
    required this.deletedAt,
    this.payload = const {},
  });

  factory PackageEntityTombstoneData.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return PackageEntityTombstoneData(
      entityType: (json['entityType'] as String? ?? '').trim(),
      entityKey: (json['entityKey'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'entityKey': entityKey,
        'mapName': mapName,
        'deletedAt': deletedAt,
        'payload': payload,
      };
}

class PackageTagData {
  final String tagUuid;
  final String mapName;
  final String name;
  final int dimension;
  final int colorValue;
  final String? groupName;
  final bool isSystem;
  final int updatedAt;

  const PackageTagData({
    required this.tagUuid,
    required this.mapName,
    required this.name,
    required this.dimension,
    required this.colorValue,
    this.groupName,
    required this.isSystem,
    required this.updatedAt,
  });

  factory PackageTagData.fromJson(Map<String, dynamic> json) {
    return PackageTagData(
      tagUuid: (json['tagUuid'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      dimension: json['dimension'] as int? ?? TagDimension.custom,
      colorValue: json['colorValue'] as int? ?? 0xFF607D8B,
      groupName: json['groupName'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'tagUuid': tagUuid,
        'mapName': mapName,
        'name': name,
        'dimension': dimension,
        'colorValue': colorValue,
        'groupName': groupName,
        'isSystem': isSystem,
        'updatedAt': updatedAt,
      };
}

class PackageAreaData {
  final String tagUuid;
  final String mapName;
  final String layerName;
  final String name;
  final int colorValue;
  final String strokes;
  final int createdAt;
  final int updatedAt;

  const PackageAreaData({
    required this.tagUuid,
    required this.mapName,
    required this.layerName,
    required this.name,
    required this.colorValue,
    required this.strokes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PackageAreaData.fromJson(Map<String, dynamic> json) {
    return PackageAreaData(
      tagUuid: (json['tagUuid'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      layerName: (json['layerName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      colorValue: json['colorValue'] as int? ?? 0xFF4CAF50,
      strokes: json['strokes'] as String? ?? '[]',
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] as int? ??
          (json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toJson() => {
        'tagUuid': tagUuid,
        'mapName': mapName,
        'layerName': layerName,
        'name': name,
        'colorValue': colorValue,
        'strokes': strokes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class PackageFavoriteFolderData {
  final String mapName;
  final String name;
  final String nameKey;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  const PackageFavoriteFolderData({
    required this.mapName,
    required this.name,
    required this.nameKey,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PackageFavoriteFolderData.fromJson(Map<String, dynamic> json) {
    return PackageFavoriteFolderData(
      mapName: (json['mapName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      nameKey: (json['nameKey'] as String? ?? '').trim(),
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'mapName': mapName,
        'name': name,
        'nameKey': nameKey,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class PackageImpactGroupData {
  final String mapName;
  final String layerName;
  final String name;
  final int type;
  final double impactXRatio;
  final double impactYRatio;
  final int createdAt;
  final int updatedAt;

  const PackageImpactGroupData({
    required this.mapName,
    required this.layerName,
    required this.name,
    required this.type,
    required this.impactXRatio,
    required this.impactYRatio,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PackageImpactGroupData.fromJson(Map<String, dynamic> json) {
    return PackageImpactGroupData(
      mapName: (json['mapName'] as String? ?? '').trim(),
      layerName: (json['layerName'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      type: json['type'] as int? ?? GrenadeType.smoke,
      impactXRatio: (json['impactXRatio'] as num?)?.toDouble() ?? 0.0,
      impactYRatio: (json['impactYRatio'] as num?)?.toDouble() ?? 0.0,
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] as int? ??
          (json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toJson() => {
        'mapName': mapName,
        'layerName': layerName,
        'name': name,
        'type': type,
        'impactXRatio': impactXRatio,
        'impactYRatio': impactYRatio,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class LanSyncManifestItem {
  final String key;
  final String mapName;
  final String digest;
  final int updatedAtMs;
  final Map<String, dynamic> rawData;
  final Set<String> filesToZip;

  const LanSyncManifestItem({
    required this.key,
    required this.mapName,
    required this.digest,
    required this.updatedAtMs,
    this.rawData = const {},
    this.filesToZip = const <String>{},
  });

  Map<String, dynamic> toManifestJson() => {
        'digest': digest,
        'updatedAtMs': updatedAtMs,
        'mapName': mapName,
      };
}

class LanSyncManifestBundle {
  final Map<String, LanSyncManifestItem> grenades;
  final Map<String, LanSyncManifestItem> tags;
  final Map<String, LanSyncManifestItem> areas;
  final Map<String, LanSyncManifestItem> favoriteFolders;
  final Map<String, LanSyncManifestItem> impactGroups;

  const LanSyncManifestBundle({
    this.grenades = const {},
    this.tags = const {},
    this.areas = const {},
    this.favoriteFolders = const {},
    this.impactGroups = const {},
  });

  Map<String, dynamic> toManifestJson() {
    final grenadesByMap = <String, Map<String, dynamic>>{};
    for (final entry in grenades.entries) {
      grenadesByMap.putIfAbsent(entry.value.mapName, () => <String, dynamic>{});
      grenadesByMap[entry.value.mapName]![entry.key] =
          entry.value.toManifestJson();
    }
    return {
      'manifestSchemaVersion': 1,
      'generatedAtMs': DateTime.now().millisecondsSinceEpoch,
      'grenadesByMap': grenadesByMap,
      'entitiesByType': {
        LanSyncEntityTombstoneType.tag: {
          for (final entry in tags.entries)
            entry.key: entry.value.toManifestJson(),
        },
        LanSyncEntityTombstoneType.area: {
          for (final entry in areas.entries)
            entry.key: entry.value.toManifestJson(),
        },
        LanSyncEntityTombstoneType.favoriteFolder: {
          for (final entry in favoriteFolders.entries)
            entry.key: entry.value.toManifestJson(),
        },
        LanSyncEntityTombstoneType.impactGroup: {
          for (final entry in impactGroups.entries)
            entry.key: entry.value.toManifestJson(),
        },
      },
    };
  }
}

enum TagConflictType { uuidMismatch, semanticMatch }

enum ImportTagConflictResolution { local, shared }

enum ImportAreaConflictResolution { keepLocal, overwriteShared }

class TagConflictItem {
  final TagConflictType type;
  final PackageTagData sharedTag;
  final Tag localTag;

  const TagConflictItem({
    required this.type,
    required this.sharedTag,
    required this.localTag,
  });
}

class AreaConflictGroup {
  final String tagUuid;
  final String tagName;
  final String mapName;
  final List<String> layers;

  const AreaConflictGroup({
    required this.tagUuid,
    required this.tagName,
    required this.mapName,
    required this.layers,
  });
}

class ImportConflictBundle {
  final List<TagConflictItem> tagConflicts;
  final Map<String, Tag> localTagByUuid;

  const ImportConflictBundle({
    required this.tagConflicts,
    required this.localTagByUuid,
  });
}

class ImportConflictNotice {
  final List<GrenadePreviewItem> newerLocalGrenades;
  final List<GrenadePreviewItem> newerLocalDeleteConflicts;
  final List<String> newerLocalFavoriteFolderDeletes;

  const ImportConflictNotice({
    this.newerLocalGrenades = const [],
    this.newerLocalDeleteConflicts = const [],
    this.newerLocalFavoriteFolderDeletes = const [],
  });

  bool get hasConflicts =>
      newerLocalGrenades.isNotEmpty ||
      newerLocalDeleteConflicts.isNotEmpty ||
      newerLocalFavoriteFolderDeletes.isNotEmpty;
}

class EntityTombstoneApplyResult {
  final int deletedCount;
  final int skippedCount;
  final Map<String, int> deletedByType;
  final Map<String, int> skippedByType;

  const EntityTombstoneApplyResult({
    required this.deletedCount,
    required this.skippedCount,
    this.deletedByType = const {},
    this.skippedByType = const {},
  });
}

/// isolate 中执行的打包参数
class _PackageParams {
  final String exportDirPath;
  final String zipPath;
  final String jsonData;
  final List<String> filesToCopy;

  _PackageParams({
    required this.exportDirPath,
    required this.zipPath,
    required this.jsonData,
    required this.filesToCopy,
  });
}

class _ExportBundle {
  final List<Map<String, dynamic>> grenades;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> areas;
  final Set<String> filesToZip;

  const _ExportBundle({
    required this.grenades,
    required this.tags,
    required this.areas,
    required this.filesToZip,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'grenades': grenades,
        'tags': tags,
        'areas': areas,
      };
}

class OrphanMediaFileEntry {
  final String path;
  final int sizeBytes;

  const OrphanMediaFileEntry({
    required this.path,
    required this.sizeBytes,
  });
}

class OrphanMediaScanResult {
  final List<OrphanMediaFileEntry> orphanFiles;

  const OrphanMediaScanResult({
    required this.orphanFiles,
  });

  int get totalSizeBytes =>
      orphanFiles.fold(0, (sum, item) => sum + item.sizeBytes);
}

class OrphanMediaCleanupResult {
  final List<OrphanMediaFileEntry> deletedFiles;
  final List<OrphanMediaFileEntry> failedFiles;

  const OrphanMediaCleanupResult({
    required this.deletedFiles,
    required this.failedFiles,
  });

  int get deletedBytes =>
      deletedFiles.fold(0, (sum, item) => sum + item.sizeBytes);
}

class _PackageFavoriteFolderRef {
  final String mapName;
  final String nameKey;

  const _PackageFavoriteFolderRef({
    required this.mapName,
    required this.nameKey,
  });
}

class _PackageImpactGroupRef {
  final String mapName;
  final String layerName;
  final String name;
  final int type;
  final double impactXRatio;
  final double impactYRatio;

  const _PackageImpactGroupRef({
    required this.mapName,
    required this.layerName,
    required this.name,
    required this.type,
    required this.impactXRatio,
    required this.impactYRatio,
  });
}

class _LanSyncExportBundle {
  final List<Map<String, dynamic>> grenades;
  final List<Map<String, dynamic>> tags;
  final List<Map<String, dynamic>> areas;
  final List<Map<String, dynamic>> favoriteFolders;
  final List<Map<String, dynamic>> impactGroups;
  final List<Map<String, dynamic>> grenadeTombstones;
  final List<Map<String, dynamic>> entityTombstones;
  final Set<String> filesToZip;

  const _LanSyncExportBundle({
    required this.grenades,
    required this.tags,
    required this.areas,
    required this.favoriteFolders,
    required this.impactGroups,
    required this.grenadeTombstones,
    required this.entityTombstones,
    required this.filesToZip,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': 6,
        'grenades': grenades,
        'tags': tags,
        'areas': areas,
        'favoriteFolders': favoriteFolders,
        'impactGroups': impactGroups,
        'grenadeTombstones': grenadeTombstones,
        'entityTombstones': entityTombstones,
      };
}

/// 在 isolate 中执行文件复制和压缩（顶层函数）
Future<void> _packageFilesInIsolate(_PackageParams params) async {
  final exportDir = Directory(params.exportDirPath);

  // 清理并创建目录
  if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
  exportDir.createSync(recursive: true);

  // 写入 data.json
  final jsonFile = File(p.join(exportDir.path, "data.json"));
  jsonFile.writeAsStringSync(params.jsonData);

  // 复制媒体文件
  for (var filePath in params.filesToCopy) {
    final file = File(filePath);
    if (file.existsSync()) {
      file.copySync(p.join(exportDir.path, p.basename(filePath)));
    }
  }

  // 压缩为 .cs2pkg
  final encoder = ZipFileEncoder();
  encoder.create(params.zipPath);
  // archive 4.x 的 addDirectory/close 是异步方法，必须等待完成，否则会生成空包/半成品包
  await encoder.addDirectory(exportDir, includeDirName: false);
  await encoder.close();
}

class DataService {
  final Isar isar;
  DataService(this.isar);

  static const Set<String> _trackedMediaExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.mp4',
    '.mov',
    '.m4v',
    '.avi',
    '.mkv',
    '.webm',
  };

  static String normalizeMediaPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    final normalized = p.normalize(File(trimmed).absolute.path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  /// 删除媒体文件（静态方法，可在其他地方调用）
  static Future<void> deleteMediaFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除媒体文件失败: $e');
    }
  }

  /// 批量删除媒体文件
  static Future<void> deleteMediaFiles(List<String> paths) async {
    for (final path in paths) {
      await deleteMediaFile(path);
    }
  }

  Future<bool> deleteMediaFileIfUnused(
    String localPath, {
    int? excludingMediaId,
  }) async {
    final normalizedPath = localPath.trim();
    if (normalizedPath.isEmpty) return false;

    final medias = await isar.stepMedias
        .filter()
        .localPathEqualTo(normalizedPath)
        .findAll();
    final stillReferenced = medias.any((media) => media.id != excludingMediaId);
    if (stillReferenced) return false;

    await deleteMediaFile(normalizedPath);
    return true;
  }

  Future<OrphanMediaScanResult> scanOrphanMediaFiles() async {
    final dataPath = (isar.directory ?? '').trim();
    if (dataPath.isEmpty) {
      return const OrphanMediaScanResult(orphanFiles: []);
    }

    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) {
      return const OrphanMediaScanResult(orphanFiles: []);
    }

    final referencedPaths = <String>{};
    final medias = await isar.stepMedias.where().findAll();
    for (final media in medias) {
      final normalized = normalizeMediaPath(media.localPath);
      if (normalized.isNotEmpty) {
        referencedPaths.add(normalized);
      }
    }

    final orphanFiles = <OrphanMediaFileEntry>[];
    await for (final entity
        in dataDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path).toLowerCase();
      if (!_trackedMediaExtensions.contains(extension)) continue;

      final normalized = normalizeMediaPath(entity.path);
      if (normalized.isEmpty || referencedPaths.contains(normalized)) continue;

      int sizeBytes = 0;
      try {
        sizeBytes = await entity.length();
      } catch (_) {}

      orphanFiles.add(
        OrphanMediaFileEntry(
          path: entity.path,
          sizeBytes: sizeBytes,
        ),
      );
    }

    orphanFiles.sort((a, b) => a.path.compareTo(b.path));
    return OrphanMediaScanResult(orphanFiles: orphanFiles);
  }

  Future<OrphanMediaCleanupResult> cleanupOrphanMediaFiles(
    Iterable<OrphanMediaFileEntry> files,
  ) async {
    final deletedFiles = <OrphanMediaFileEntry>[];
    final failedFiles = <OrphanMediaFileEntry>[];

    for (final item in files) {
      final file = File(item.path);
      try {
        if (await file.exists()) {
          await file.delete();
        }
        deletedFiles.add(item);
      } catch (_) {
        failedFiles.add(item);
      }
    }

    return OrphanMediaCleanupResult(
      deletedFiles: deletedFiles,
      failedFiles: failedFiles,
    );
  }

  Future<int> deleteGrenades(
    List<Grenade> grenades, {
    bool recordSyncTombstones = true,
  }) async {
    if (grenades.isEmpty) return 0;

    final tombstones = <LanSyncGrenadeTombstoneEntry>[];
    final mediaPathsToCleanup = <String>{};
    for (final grenade in grenades) {
      await grenade.layer.load();
      final layer = grenade.layer.value;
      if (layer == null) continue;
      await layer.map.load();
      final map = layer.map.value;
      final uniqueId = (grenade.uniqueId ?? '').trim();
      final mapName = map?.name.trim() ?? '';
      if (recordSyncTombstones && uniqueId.isNotEmpty && mapName.isNotEmpty) {
        tombstones.add(LanSyncGrenadeTombstoneEntry(
          uniqueId: uniqueId,
          mapName: mapName,
          deletedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      await grenade.steps.load();
      for (final step in grenade.steps) {
        await step.medias.load();
      }
    }

    for (final grenade in grenades) {
      for (final step in grenade.steps) {
        for (final media in step.medias) {
          final path = media.localPath.trim();
          if (path.isNotEmpty) {
            mediaPathsToCleanup.add(path);
          }
        }
      }
    }

    await isar.writeTxn(() async {
      for (final grenade in grenades) {
        for (final step in grenade.steps) {
          await isar.stepMedias
              .deleteAll(step.medias.map((media) => media.id).toList());
        }
        await isar.grenadeSteps
            .deleteAll(grenade.steps.map((step) => step.id).toList());
        await isar.grenades.delete(grenade.id);
      }
    });

    for (final path in mediaPathsToCleanup) {
      await deleteMediaFileIfUnused(path);
    }

    if (recordSyncTombstones && tombstones.isNotEmpty) {
      await LanSyncLocalStore().upsertGrenadeTombstones(tombstones);
    }
    return grenades.length;
  }

  /// 删除某个地图的所有道具
  Future<int> deleteAllGrenadesForMap(GameMap map) async {
    await map.layers.load();
    final grenades = <Grenade>[];
    for (final layer in map.layers) {
      await layer.grenades.load();
      grenades.addAll(layer.grenades.toList());
    }
    return deleteGrenades(grenades);
  }

  Future<void> deleteImpactGroup(
    ImpactGroup group, {
    bool recordSyncTombstone = true,
  }) async {
    MapLayer? layer;
    GameMap? map;
    if (recordSyncTombstone) {
      layer = await isar.mapLayers.get(group.layerId);
      if (layer != null) {
        await layer.map.load();
        map = layer.map.value;
      }
    }

    final grenades =
        await isar.grenades.filter().impactGroupIdEqualTo(group.id).findAll();
    await isar.writeTxn(() async {
      for (final g in grenades) {
        g.impactGroupId = null;
        g.updatedAt = DateTime.now();
        await isar.grenades.put(g);
      }
      await isar.impactGroups.delete(group.id);
    });

    if (recordSyncTombstone && map != null && layer != null) {
      final entityKey = buildImpactGroupEntityKey(
        mapName: map.name,
        layerName: layer.name,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      );
      await LanSyncLocalStore().upsertEntityTombstones([
        LanSyncEntityTombstoneEntry(
          entityType: LanSyncEntityTombstoneType.impactGroup,
          entityKey: entityKey,
          mapName: map.name,
          deletedAt: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'name': group.name,
            'layerName': layer.name,
            'type': group.type,
            'impactXRatio': group.impactXRatio,
            'impactYRatio': group.impactYRatio,
          },
        ),
      ]);
    }
  }

  /// 预览包
  Future<PackagePreviewResult?> previewPackage(String filePath) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return null;
    }

    final file = File(filePath);
    if (!file.existsSync()) return null;

    // 解压
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    List<dynamic> grenadesData = [];
    int schemaVersion = 1;
    final tagsByUuid = <String, PackageTagData>{};
    final areas = <PackageAreaData>[];
    final favoriteFolders = <PackageFavoriteFolderData>[];
    final impactGroups = <PackageImpactGroupData>[];
    final grenadeTombstones = <PackageGrenadeTombstoneData>[];
    final entityTombstones = <PackageEntityTombstoneData>[];
    final Map<String, List<int>> memoryImages = {};

    for (var archiveFile in archive) {
      final fileName = p.basename(archiveFile.name);
      if (fileName == "data.json") {
        final decoded =
            jsonDecode(utf8.decode(archiveFile.content as List<int>));
        if (decoded is Map<String, dynamic>) {
          schemaVersion = decoded['schemaVersion'] as int? ?? 1;
          final grenadesRaw = decoded['grenades'];
          if (grenadesRaw is List) {
            grenadesData = grenadesRaw;
          }
          final tagsRaw = decoded['tags'];
          if (tagsRaw is List) {
            for (final raw in tagsRaw) {
              if (raw is! Map<String, dynamic>) continue;
              final tag = PackageTagData.fromJson(raw);
              if (tag.tagUuid.isEmpty) continue;
              tagsByUuid[tag.tagUuid] = tag;
            }
          }
          final areasRaw = decoded['areas'];
          if (areasRaw is List) {
            for (final raw in areasRaw) {
              if (raw is! Map<String, dynamic>) continue;
              final area = PackageAreaData.fromJson(raw);
              if (area.tagUuid.isEmpty) continue;
              areas.add(area);
            }
          }
          final favoriteFoldersRaw = decoded['favoriteFolders'];
          if (favoriteFoldersRaw is List) {
            for (final raw in favoriteFoldersRaw) {
              if (raw is! Map<String, dynamic>) continue;
              final folder = PackageFavoriteFolderData.fromJson(raw);
              if (folder.mapName.isEmpty || folder.nameKey.isEmpty) continue;
              favoriteFolders.add(folder);
            }
          }
          final impactGroupsRaw = decoded['impactGroups'];
          if (impactGroupsRaw is List) {
            for (final raw in impactGroupsRaw) {
              if (raw is! Map<String, dynamic>) continue;
              final group = PackageImpactGroupData.fromJson(raw);
              if (group.mapName.isEmpty ||
                  group.layerName.isEmpty ||
                  group.name.isEmpty) {
                continue;
              }
              impactGroups.add(group);
            }
          }
          final grenadeTombstonesRaw = decoded['grenadeTombstones'];
          if (grenadeTombstonesRaw is List) {
            for (final raw in grenadeTombstonesRaw) {
              if (raw is! Map<String, dynamic>) continue;
              final tombstone = PackageGrenadeTombstoneData.fromJson(raw);
              if (tombstone.uniqueId.isEmpty || tombstone.mapName.isEmpty) {
                continue;
              }
              grenadeTombstones.add(tombstone);
            }
          }
          final entityTombstonesRaw = decoded['entityTombstones'];
          if (entityTombstonesRaw is List) {
            for (final raw in entityTombstonesRaw) {
              if (raw is! Map<String, dynamic>) continue;
              final tombstone = PackageEntityTombstoneData.fromJson(raw);
              if (!LanSyncEntityTombstoneType.values
                      .contains(tombstone.entityType) ||
                  tombstone.entityKey.isEmpty ||
                  tombstone.mapName.isEmpty) {
                continue;
              }
              entityTombstones.add(tombstone);
            }
          }
        } else if (decoded is List) {
          grenadesData = decoded;
          schemaVersion = 1;
        }
      } else {
        if (archiveFile.isFile) {
          memoryImages[fileName] = archiveFile.content as List<int>;
        }
      }
    }

    if (grenadesData.isEmpty &&
        tagsByUuid.isEmpty &&
        areas.isEmpty &&
        favoriteFolders.isEmpty &&
        impactGroups.isEmpty &&
        grenadeTombstones.isEmpty &&
        entityTombstones.isEmpty) {
      return null;
    }

    // 按地图分组
    final Map<String, List<GrenadePreviewItem>> grenadesByMap = {};

    for (var item in grenadesData) {
      final mapName = item['mapName'] as String? ?? 'Unknown';
      final layerName = item['layerName'] as String? ?? 'Default';
      final title = item['title'] as String? ?? '';
      final type = item['type'] as int? ?? 0;
      final author = item['author'] as String?;
      final importedUniqueId = item['uniqueId'] as String?;
      final xRatio = (item['x'] as num?)?.toDouble() ?? 0.0;
      final yRatio = (item['y'] as num?)?.toDouble() ?? 0.0;
      final importedUpdatedAt = item['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
          : DateTime.now();

      // 生成临时 uniqueId（如果没有）
      final uniqueId =
          importedUniqueId ?? '${mapName}_${title}_${xRatio}_$yRatio';

      // 计算导入状态
      ImportStatus status = ImportStatus.newItem;

      // 查找地图
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map != null) {
        await map.layers.load();
        MapLayer? layer;
        for (var l in map.layers) {
          if (l.name == layerName) {
            layer = l;
            break;
          }
        }
        layer ??= map.layers.isNotEmpty ? map.layers.first : null;

        if (layer != null) {
          // 查找已有道具
          Grenade? existing;

          if (importedUniqueId != null && importedUniqueId.isNotEmpty) {
            final allGrenades = await isar.grenades.where().findAll();
            existing = allGrenades
                .where((g) => g.uniqueId == importedUniqueId)
                .firstOrNull;
          }

          if (existing == null && importedUniqueId == null) {
            await layer.grenades.load();
            existing = layer.grenades
                .where((g) =>
                    g.title == title &&
                    (g.xRatio - xRatio).abs() < 0.01 &&
                    (g.yRatio - yRatio).abs() < 0.01)
                .firstOrNull;
          }

          if (existing != null) {
            if (await _shouldImportGrenadeOverLocal(
              existing,
              item,
              memoryImages,
            )) {
              status = ImportStatus.update;
            } else {
              status = ImportStatus.skip;
            }
          }
        }
      }

      final previewItem = GrenadePreviewItem(
        rawData: item,
        uniqueId: uniqueId,
        title: title,
        type: type,
        mapName: mapName,
        layerName: layerName,
        author: author,
        status: status,
        updatedAt: importedUpdatedAt,
      );

      grenadesByMap.putIfAbsent(mapName, () => []);
      grenadesByMap[mapName]!.add(previewItem);
    }

    return PackagePreviewResult(
      grenadesByMap: grenadesByMap,
      filePath: filePath,
      memoryImages: memoryImages,
      schemaVersion: schemaVersion,
      tagsByUuid: tagsByUuid,
      areas: areas,
      favoriteFolders: favoriteFolders,
      impactGroups: impactGroups,
      grenadeTombstones: grenadeTombstones,
      entityTombstones: entityTombstones,
    );
  }

  // --- 导出 (分享) ---

  Future<int> _ensureExportTagUuids(Iterable<int> tagIds) async {
    final toFix = <Tag>[];
    final occupied = <String>{};
    final tags = <Tag>[];

    for (final tagId in tagIds) {
      final tag = await isar.tags.get(tagId);
      if (tag != null) {
        tags.add(tag);
      }
    }

    for (final tag in tags) {
      final uuid = tag.tagUuid.trim();
      if (uuid.isNotEmpty) {
        occupied.add(uuid);
      }
    }

    const uuid = Uuid();
    for (final tag in tags) {
      if (tag.tagUuid.trim().isNotEmpty) continue;
      String value;
      do {
        value = uuid.v4();
      } while (occupied.contains(value));
      tag.tagUuid = value;
      occupied.add(value);
      toFix.add(tag);
    }

    if (toFix.isEmpty) return 0;
    await isar.writeTxn(() async {
      await isar.tags.putAll(toFix);
    });
    return toFix.length;
  }

  Future<_ExportBundle> _buildExportBundle(List<Grenade> grenades) async {
    final exportList = <Map<String, dynamic>>[];
    final exportTagIdsByIndex = <Set<int>>[];
    final filesToZip = <String>{};
    final usedTagIds = <int>{};
    final usedMapIds = <int>{};

    for (final g in grenades) {
      g.layer.loadSync();
      g.layer.value?.map.loadSync();
      g.steps.loadSync();

      final stepsData = <Map<String, dynamic>>[];
      for (final s in g.steps) {
        s.medias.loadSync();
        final mediaData = <Map<String, dynamic>>[];
        for (final m in s.medias) {
          mediaData.add({'path': p.basename(m.localPath), 'type': m.type});
          filesToZip.add(m.localPath);
        }
        stepsData.add({
          'title': s.title,
          'description': s.description,
          'index': s.stepIndex,
          'medias': mediaData,
        });
      }

      final grenadeTags =
          await isar.grenadeTags.filter().grenadeIdEqualTo(g.id).findAll();
      final tagIds = grenadeTags.map((gt) => gt.tagId).toSet();
      usedTagIds.addAll(tagIds);
      if (g.layer.value?.map.value != null) {
        usedMapIds.add(g.layer.value!.map.value!.id);
      }

      exportList.add({
        'uniqueId': g.uniqueId,
        'mapName': g.layer.value?.map.value?.name ?? "Unknown",
        'layerName': g.layer.value?.name ?? "Default",
        'title': g.title,
        'type': g.type,
        'team': g.team,
        'author': g.author,
        'sourceUrl': g.sourceUrl,
        'sourceNote': g.sourceNote,
        'x': g.xRatio,
        'y': g.yRatio,
        'impactX': g.impactXRatio,
        'impactY': g.impactYRatio,
        'impactAreaStrokes': g.impactAreaStrokes,
        'tagUuids': <String>[],
        'steps': stepsData,
        'createdAt': g.createdAt.millisecondsSinceEpoch,
        'updatedAt': g.updatedAt.millisecondsSinceEpoch,
      });
      exportTagIdsByIndex.add(tagIds);
    }

    await _ensureExportTagUuids(usedTagIds);

    final mapById = <int, GameMap>{};
    for (final id in usedMapIds) {
      final map = await isar.gameMaps.get(id);
      if (map != null) {
        mapById[id] = map;
      }
    }

    final tagById = <int, Tag>{};
    for (final id in usedTagIds) {
      final tag = await isar.tags.get(id);
      if (tag != null) {
        tagById[id] = tag;
      }
    }

    // 反填 grenade 的 tagUuids
    for (var i = 0; i < exportList.length; i++) {
      final item = exportList[i];
      final tagIds = exportTagIdsByIndex[i];
      final uuids = <String>[];
      for (final tagId in tagIds) {
        final tag = tagById[tagId];
        if (tag == null || tag.tagUuid.trim().isEmpty) continue;
        uuids.add(tag.tagUuid.trim());
      }
      item['tagUuids'] = uuids.toSet().toList(growable: false);
    }

    final tagsData = <Map<String, dynamic>>[];
    final usedTagUuids = <String>{};
    for (final tag in tagById.values) {
      final uuid = tag.tagUuid.trim();
      if (uuid.isEmpty || usedTagUuids.contains(uuid)) continue;
      usedTagUuids.add(uuid);
      final mapName = mapById[tag.mapId]?.name ?? '';
      tagsData.add({
        'tagUuid': uuid,
        'mapName': mapName,
        'name': tag.name,
        'dimension': tag.dimension,
        'colorValue': tag.colorValue,
        'groupName': tag.groupName,
        'isSystem': tag.isSystem,
        'updatedAt': tag.updatedAt.millisecondsSinceEpoch,
      });
    }

    final areaTagIdSet = tagById.values
        .where((t) => t.dimension == TagDimension.area)
        .map((t) => t.id)
        .toSet();
    final areasData = <Map<String, dynamic>>[];
    if (areaTagIdSet.isNotEmpty) {
      final mapLayerNameById = <int, String>{};
      final maps = mapById.values.toList();
      for (final map in maps) {
        await map.layers.load();
        for (final layer in map.layers) {
          mapLayerNameById[layer.id] = layer.name;
        }
      }

      final areas = await isar.mapAreas.where().findAll();
      for (final area in areas) {
        if (!areaTagIdSet.contains(area.tagId)) continue;
        final tag = tagById[area.tagId];
        if (tag == null) continue;
        final tagUuid = tag.tagUuid.trim();
        if (tagUuid.isEmpty) continue;
        final mapName = mapById[area.mapId]?.name ?? '';
        final layerName = area.layerId == null
            ? 'Default'
            : (mapLayerNameById[area.layerId!] ?? 'Default');
        areasData.add({
          'tagUuid': tagUuid,
          'mapName': mapName,
          'layerName': layerName,
          'name': area.name,
          'colorValue': area.colorValue,
          'strokes': area.strokes,
          'createdAt': area.createdAt.millisecondsSinceEpoch,
          'updatedAt': area.updatedAt.millisecondsSinceEpoch,
        });
      }
    }

    return _ExportBundle(
      grenades: exportList,
      tags: tagsData,
      areas: areasData,
      filesToZip: filesToZip,
    );
  }

  String _normalizeFolderNameKey(String value) {
    return value.trim().toLowerCase();
  }

  String _normalizeImpactGroupName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  double _roundRatio3(double value) => (value * 1000).round() / 1000.0;

  String _impactGroupSemanticKey({
    required String mapName,
    required String layerName,
    required int type,
    required String name,
    required double impactXRatio,
    required double impactYRatio,
  }) {
    return '${mapName.trim().toLowerCase()}|'
        '${layerName.trim().toLowerCase()}|'
        '$type|'
        '${_normalizeImpactGroupName(name)}|'
        '${_roundRatio3(impactXRatio).toStringAsFixed(3)}|'
        '${_roundRatio3(impactYRatio).toStringAsFixed(3)}';
  }

  String _favoriteFolderRefKey({
    required String mapName,
    required String nameKey,
  }) {
    return '${mapName.trim().toLowerCase()}|${nameKey.trim().toLowerCase()}';
  }

  String entityTombstoneKey({
    required String entityType,
    required String entityKey,
  }) {
    return '${entityType.trim()}|${entityKey.trim()}';
  }

  String buildAreaEntityKey({
    required String tagUuid,
    required String layerName,
  }) {
    return '${tagUuid.trim()}|${layerName.trim().toLowerCase()}';
  }

  String buildFavoriteFolderEntityKey({
    required String mapName,
    required String nameKey,
  }) {
    return _favoriteFolderRefKey(mapName: mapName, nameKey: nameKey);
  }

  String buildImpactGroupEntityKey({
    required String mapName,
    required String layerName,
    required int type,
    required String name,
    required double impactXRatio,
    required double impactYRatio,
  }) {
    return _impactGroupSemanticKey(
      mapName: mapName,
      layerName: layerName,
      type: type,
      name: name,
      impactXRatio: impactXRatio,
      impactYRatio: impactYRatio,
    );
  }

  Future<Map<String, GameMap>> _resolveScopeMaps(Set<String> mapKeys) async {
    final normalized =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const {};
    final maps = await isar.gameMaps.where().findAll();
    return {
      for (final map in maps)
        if (normalized.contains(map.name.trim())) map.name.trim(): map,
    };
  }

  Future<List<Grenade>> _loadScopedGrenades(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const [];
    final grenades = <Grenade>[];
    for (final map in scopedMaps.values) {
      await map.layers.load();
      for (final layer in map.layers) {
        await layer.grenades.load();
        grenades.addAll(layer.grenades);
      }
    }
    return grenades;
  }

  Future<Set<String>> _collectGrenadeFilesToZip(Grenade grenade) async {
    await grenade.steps.load();
    final files = <String>{};
    for (final step in grenade.steps) {
      await step.medias.load();
      for (final media in step.medias) {
        final path = media.localPath.trim();
        if (path.isNotEmpty) {
          files.add(path);
        }
      }
    }
    return files;
  }

  Future<Map<int, String>> _buildLayerNameById(
    Iterable<GameMap> maps,
  ) async {
    final result = <int, String>{};
    for (final map in maps) {
      await map.layers.load();
      for (final layer in map.layers) {
        result[layer.id] = layer.name;
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildGrenadeManifestItems(
    List<Grenade> grenades,
  ) async {
    if (grenades.isEmpty) return const {};
    final syncBundle = await _buildLanSyncBundle(grenades);
    final result = <String, LanSyncManifestItem>{};
    for (var i = 0; i < grenades.length; i++) {
      final grenade = grenades[i];
      final rawData = Map<String, dynamic>.from(syncBundle.grenades[i]);
      final uniqueId = (rawData['uniqueId'] as String? ?? '').trim();
      final mapName = (rawData['mapName'] as String? ?? '').trim();
      if (uniqueId.isEmpty || mapName.isEmpty) continue;
      final filesToZip = await _collectGrenadeFilesToZip(grenade);
      result[uniqueId] = LanSyncManifestItem(
        key: uniqueId,
        mapName: mapName,
        digest: await _buildLocalGrenadeDigest(grenade),
        updatedAtMs: grenade.updatedAt.millisecondsSinceEpoch,
        rawData: rawData,
        filesToZip: filesToZip,
      );
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildTagManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      final tags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
      for (final tag in tags) {
        final tagUuid = tag.tagUuid.trim();
        if (tagUuid.isEmpty) continue;
        final payload = PackageTagData(
          tagUuid: tagUuid,
          mapName: map.name,
          name: tag.name,
          dimension: tag.dimension,
          colorValue: tag.colorValue,
          groupName: tag.groupName,
          isSystem: tag.isSystem,
          updatedAt: tag.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        result[tagUuid] = LanSyncManifestItem(
          key: tagUuid,
          mapName: map.name,
          digest: _digestJsonValue(_normalizePayloadForSyncDigest(payload)),
          updatedAtMs: tag.updatedAt.millisecondsSinceEpoch,
          rawData: payload,
        );
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildAreaManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final tagsById = <int, Tag>{};
    final layerNameById = await _buildLayerNameById(scopedMaps.values);
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      final areas = await isar.mapAreas.filter().mapIdEqualTo(map.id).findAll();
      for (final area in areas) {
        final tag = tagsById[area.tagId] ?? await isar.tags.get(area.tagId);
        if (tag == null) continue;
        tagsById[area.tagId] = tag;
        final tagUuid = tag.tagUuid.trim();
        if (tagUuid.isEmpty) continue;
        final layerName = area.layerId == null
            ? 'Default'
            : (layerNameById[area.layerId!] ?? 'Default');
        final payload = PackageAreaData(
          tagUuid: tagUuid,
          mapName: map.name,
          layerName: layerName,
          name: area.name,
          colorValue: area.colorValue,
          strokes: area.strokes,
          createdAt: area.createdAt.millisecondsSinceEpoch,
          updatedAt: area.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        final key = buildAreaEntityKey(tagUuid: tagUuid, layerName: layerName);
        final current = result[key];
        final updatedAtMs = area.updatedAt.millisecondsSinceEpoch;
        if (current == null || updatedAtMs >= current.updatedAtMs) {
          result[key] = LanSyncManifestItem(
            key: key,
            mapName: map.name,
            digest: _digestJsonValue(_normalizePayloadForSyncDigest(payload)),
            updatedAtMs: updatedAtMs,
            rawData: payload,
          );
        }
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildFavoriteFolderManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final result = <String, LanSyncManifestItem>{};
    for (final map in scopedMaps.values) {
      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
      for (final folder in folders) {
        final nameKey = folder.nameKey.trim().isEmpty
            ? _normalizeFolderNameKey(folder.name)
            : _normalizeFolderNameKey(folder.nameKey);
        if (nameKey.isEmpty) continue;
        final payload = PackageFavoriteFolderData(
          mapName: map.name,
          name: folder.name,
          nameKey: nameKey,
          sortOrder: folder.sortOrder,
          createdAt: folder.createdAt.millisecondsSinceEpoch,
          updatedAt: folder.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        final key =
            buildFavoriteFolderEntityKey(mapName: map.name, nameKey: nameKey);
        result[key] = LanSyncManifestItem(
          key: key,
          mapName: map.name,
          digest: _digestJsonValue(_normalizePayloadForSyncDigest(payload)),
          updatedAtMs: folder.updatedAt.millisecondsSinceEpoch,
          rawData: payload,
        );
      }
    }
    return result;
  }

  Future<Map<String, LanSyncManifestItem>> _buildImpactGroupManifestItems(
    Map<String, GameMap> scopedMaps,
  ) async {
    if (scopedMaps.isEmpty) return const {};
    final layerNameById = await _buildLayerNameById(scopedMaps.values);
    final mapNameByLayerId = <int, String>{};
    for (final map in scopedMaps.values) {
      await map.layers.load();
      for (final layer in map.layers) {
        mapNameByLayerId[layer.id] = map.name;
      }
    }
    final result = <String, LanSyncManifestItem>{};
    for (final entry in mapNameByLayerId.entries) {
      final groups =
          await isar.impactGroups.filter().layerIdEqualTo(entry.key).findAll();
      final mapName = entry.value;
      final layerName = layerNameById[entry.key] ?? 'Default';
      for (final group in groups) {
        final payload = PackageImpactGroupData(
          mapName: mapName,
          layerName: layerName,
          name: group.name,
          type: group.type,
          impactXRatio: group.impactXRatio,
          impactYRatio: group.impactYRatio,
          createdAt: group.createdAt.millisecondsSinceEpoch,
          updatedAt: group.updatedAt.millisecondsSinceEpoch,
        ).toJson();
        final key = buildImpactGroupEntityKey(
          mapName: mapName,
          layerName: layerName,
          type: group.type,
          name: group.name,
          impactXRatio: group.impactXRatio,
          impactYRatio: group.impactYRatio,
        );
        result[key] = LanSyncManifestItem(
          key: key,
          mapName: mapName,
          digest: _digestJsonValue(_normalizePayloadForSyncDigest(payload)),
          updatedAtMs: group.updatedAt.millisecondsSinceEpoch,
          rawData: payload,
        );
      }
    }
    return result;
  }

  Future<LanSyncManifestBundle> buildLanSyncManifest({
    required Set<String> mapKeys,
  }) async {
    final scopedMaps = await _resolveScopeMaps(mapKeys);
    if (scopedMaps.isEmpty) {
      return const LanSyncManifestBundle();
    }
    final grenades = await _loadScopedGrenades(scopedMaps);
    final grenadeItems = await _buildGrenadeManifestItems(grenades);
    final tagItems = await _buildTagManifestItems(scopedMaps);
    final areaItems = await _buildAreaManifestItems(scopedMaps);
    final favoriteFolderItems =
        await _buildFavoriteFolderManifestItems(scopedMaps);
    final impactGroupItems = await _buildImpactGroupManifestItems(scopedMaps);
    return LanSyncManifestBundle(
      grenades: grenadeItems,
      tags: tagItems,
      areas: areaItems,
      favoriteFolders: favoriteFolderItems,
      impactGroups: impactGroupItems,
    );
  }

  Future<List<Grenade>> _resolveExportGrenades({
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
    List<Grenade>? explicitGrenades,
  }) async {
    if (explicitGrenades != null) return explicitGrenades;

    final grenades = <Grenade>[];
    if (scopeType == 0 && singleGrenade != null) {
      grenades.add(singleGrenade);
    } else if (scopeType == 1 && singleMap != null) {
      singleMap.layers.loadSync();
      for (final layer in singleMap.layers) {
        layer.grenades.loadSync();
        grenades.addAll(layer.grenades);
      }
    } else {
      grenades.addAll(isar.grenades.where().findAllSync());
    }
    return grenades;
  }

  Future<_LanSyncExportBundle> _buildLanSyncBundle(
    List<Grenade> grenades, {
    List<PackageGrenadeTombstoneData> grenadeTombstones = const [],
    List<PackageEntityTombstoneData> entityTombstones = const [],
  }) async {
    final base = await _buildExportBundle(grenades);
    final grenadeItems = base.grenades
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    final usedFolderIds = <int>{};
    final usedImpactGroupIds = <int>{};

    for (var i = 0; i < grenades.length; i++) {
      final g = grenades[i];
      final item = grenadeItems[i];

      item['isFavorite'] = g.isFavorite;
      item['favoriteFolderRef'] = null;
      item['impactGroupRef'] = null;

      if (g.isFavorite && g.favoriteFolderId != null) {
        usedFolderIds.add(g.favoriteFolderId!);
      }
      if (g.impactGroupId != null) {
        usedImpactGroupIds.add(g.impactGroupId!);
      }
    }

    final mapById = <int, GameMap>{};
    final folderRefById = <int, Map<String, dynamic>>{};
    final favoriteFoldersData = <Map<String, dynamic>>[];

    for (final folderId in usedFolderIds) {
      final folder = await isar.favoriteFolders.get(folderId);
      if (folder == null) continue;
      final map =
          mapById[folder.mapId] ?? await isar.gameMaps.get(folder.mapId);
      if (map == null) continue;
      mapById[folder.mapId] = map;
      final nameKey = folder.nameKey.trim().isEmpty
          ? _normalizeFolderNameKey(folder.name)
          : _normalizeFolderNameKey(folder.nameKey);

      final payload = PackageFavoriteFolderData(
        mapName: map.name,
        name: folder.name,
        nameKey: nameKey,
        sortOrder: folder.sortOrder,
        createdAt: folder.createdAt.millisecondsSinceEpoch,
        updatedAt: folder.updatedAt.millisecondsSinceEpoch,
      ).toJson();
      favoriteFoldersData.add(payload);
      folderRefById[folder.id] = {
        'mapName': map.name,
        'nameKey': nameKey,
      };
    }

    final impactGroupRefById = <int, Map<String, dynamic>>{};
    final impactGroupsData = <Map<String, dynamic>>[];
    final seenImpactGroupKeys = <String>{};

    for (final groupId in usedImpactGroupIds) {
      final group = await isar.impactGroups.get(groupId);
      if (group == null) continue;
      final layer = await isar.mapLayers.get(group.layerId);
      if (layer == null) continue;
      await layer.map.load();
      final map = layer.map.value;
      if (map == null) continue;

      final payload = PackageImpactGroupData(
        mapName: map.name,
        layerName: layer.name,
        name: group.name,
        type: group.type,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
        createdAt: group.createdAt.millisecondsSinceEpoch,
        updatedAt: group.updatedAt.millisecondsSinceEpoch,
      );
      final semanticKey = _impactGroupSemanticKey(
        mapName: payload.mapName,
        layerName: payload.layerName,
        type: payload.type,
        name: payload.name,
        impactXRatio: payload.impactXRatio,
        impactYRatio: payload.impactYRatio,
      );

      if (!seenImpactGroupKeys.contains(semanticKey)) {
        impactGroupsData.add(payload.toJson());
        seenImpactGroupKeys.add(semanticKey);
      }

      impactGroupRefById[group.id] = {
        'mapName': payload.mapName,
        'layerName': payload.layerName,
        'name': payload.name,
        'type': payload.type,
        'impactXRatio': payload.impactXRatio,
        'impactYRatio': payload.impactYRatio,
      };
    }

    for (var i = 0; i < grenades.length; i++) {
      final g = grenades[i];
      final item = grenadeItems[i];
      if (g.isFavorite && g.favoriteFolderId != null) {
        item['favoriteFolderRef'] = folderRefById[g.favoriteFolderId!];
      }
      if (g.impactGroupId != null) {
        item['impactGroupRef'] = impactGroupRefById[g.impactGroupId!];
      }
    }

    return _LanSyncExportBundle(
      grenades: grenadeItems,
      tags: base.tags,
      areas: base.areas,
      favoriteFolders: favoriteFoldersData,
      impactGroups: impactGroupsData,
      grenadeTombstones:
          grenadeTombstones.map((e) => e.toJson()).toList(growable: false),
      entityTombstones:
          entityTombstones.map((e) => e.toJson()).toList(growable: false),
      filesToZip: base.filesToZip,
    );
  }

  /// 构建局域网同步专用包（schemaVersion=5），包含局域网专用附加数据。
  /// 不影响普通分享/导出逻辑。
  Future<String> buildLanSyncPackageToTemp({
    required int scopeType,
    Grenade? singleGrenade,
    GameMap? singleMap,
    List<Grenade>? explicitGrenades,
    List<Map<String, dynamic>> explicitGrenadePayloads = const [],
    List<Map<String, dynamic>> explicitTagPayloads = const [],
    List<Map<String, dynamic>> explicitAreaPayloads = const [],
    List<Map<String, dynamic>> explicitFavoriteFolderPayloads = const [],
    List<Map<String, dynamic>> explicitImpactGroupPayloads = const [],
    Set<String> explicitFilesToZip = const <String>{},
    List<PackageGrenadeTombstoneData> grenadeTombstones = const [],
    List<PackageEntityTombstoneData> entityTombstones = const [],
  }) async {
    final hasExplicitPayloads = explicitGrenadePayloads.isNotEmpty ||
        explicitTagPayloads.isNotEmpty ||
        explicitAreaPayloads.isNotEmpty ||
        explicitFavoriteFolderPayloads.isNotEmpty ||
        explicitImpactGroupPayloads.isNotEmpty ||
        grenadeTombstones.isNotEmpty ||
        entityTombstones.isNotEmpty;
    final List<Grenade> grenades = hasExplicitPayloads
        ? const []
        : await _resolveExportGrenades(
            scopeType: scopeType,
            singleGrenade: singleGrenade,
            singleMap: singleMap,
            explicitGrenades: explicitGrenades,
          );
    if (!hasExplicitPayloads &&
        grenades.isEmpty &&
        grenadeTombstones.isEmpty &&
        entityTombstones.isEmpty) {
      throw StateError('没有可同步的道具');
    }

    final syncBundle = hasExplicitPayloads
        ? _LanSyncExportBundle(
            grenades: explicitGrenadePayloads,
            tags: explicitTagPayloads,
            areas: explicitAreaPayloads,
            favoriteFolders: explicitFavoriteFolderPayloads,
            impactGroups: explicitImpactGroupPayloads,
            grenadeTombstones: grenadeTombstones
                .map((e) => e.toJson())
                .toList(growable: false),
            entityTombstones:
                entityTombstones.map((e) => e.toJson()).toList(growable: false),
            filesToZip: explicitFilesToZip,
          )
        : await _buildLanSyncBundle(
            grenades,
            grenadeTombstones: grenadeTombstones,
            entityTombstones: entityTombstones,
          );
    if (syncBundle.grenades.isEmpty &&
        syncBundle.tags.isEmpty &&
        syncBundle.areas.isEmpty &&
        syncBundle.favoriteFolders.isEmpty &&
        syncBundle.impactGroups.isEmpty &&
        grenadeTombstones.isEmpty &&
        entityTombstones.isEmpty) {
      throw StateError('当前范围没有可同步的增量变更');
    }
    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, "lan_sync_export_temp");
    final zipPath = p.join(tempDir.path, "lan_sync_data.cs2pkg");

    await compute(
      _packageFilesInIsolate,
      _PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(syncBundle.toJson()),
        filesToCopy: syncBundle.filesToZip.toList(),
      ),
    );

    return zipPath;
  }

  Future<List<Grenade>> loadGrenadesByUniqueIds(
    Iterable<String> uniqueIds,
  ) async {
    final normalized =
        uniqueIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const [];
    final all = await isar.grenades.where().findAll();
    return all
        .where((g) => normalized.contains((g.uniqueId ?? '').trim()))
        .toList(growable: false);
  }

  Future<Map<String, GrenadePreviewItem>>
      loadLocalGrenadePreviewItemsByUniqueIds(
    Iterable<String> uniqueIds,
  ) async {
    final normalized =
        uniqueIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const {};

    final all = await isar.grenades.where().findAll();
    final matched = all
        .where((g) => normalized.contains((g.uniqueId ?? '').trim()))
        .toList(growable: false);
    if (matched.isEmpty) return const {};

    final result = <String, GrenadePreviewItem>{};
    for (final grenade in matched) {
      final uniqueId = (grenade.uniqueId ?? '').trim();
      if (uniqueId.isEmpty) continue;

      await grenade.layer.load();
      final layer = grenade.layer.value;
      await layer?.map.load();
      final map = layer?.map.value;
      await grenade.steps.load();

      final stepsData = <Map<String, dynamic>>[];
      for (final step in grenade.steps) {
        await step.medias.load();
        final mediaData = <Map<String, dynamic>>[];
        for (final media in step.medias) {
          mediaData.add({
            'path': media.localPath,
            'type': media.type,
          });
        }
        stepsData.add({
          'title': step.title,
          'description': step.description,
          'index': step.stepIndex,
          'medias': mediaData,
        });
      }

      final rawData = <String, dynamic>{
        'uniqueId': uniqueId,
        'mapName': map?.name ?? '',
        'layerName': layer?.name ?? '',
        'title': grenade.title,
        'type': grenade.type,
        'team': grenade.team,
        'author': grenade.author,
        'sourceUrl': grenade.sourceUrl,
        'sourceNote': grenade.sourceNote,
        'hasLocalEdits': grenade.hasLocalEdits,
        'x': grenade.xRatio,
        'y': grenade.yRatio,
        'impactX': grenade.impactXRatio,
        'impactY': grenade.impactYRatio,
        'impactAreaStrokes': grenade.impactAreaStrokes,
        'steps': stepsData,
        'createdAt': grenade.createdAt.millisecondsSinceEpoch,
        'updatedAt': grenade.updatedAt.millisecondsSinceEpoch,
      };

      result[uniqueId] = GrenadePreviewItem(
        rawData: rawData,
        uniqueId: uniqueId,
        title: grenade.title,
        type: grenade.type,
        mapName: map?.name ?? '',
        layerName: layer?.name ?? '',
        author: grenade.author,
        status: ImportStatus.skip,
        updatedAt: grenade.updatedAt,
      );
    }

    return result;
  }

  Future<Map<String, Map<String, String>>> buildGrenadeDigestByMap({
    required Set<String> mapKeys,
  }) async {
    final normalized =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (normalized.isEmpty) return const {};

    final result = <String, Map<String, String>>{
      for (final mapKey in normalized) mapKey: <String, String>{},
    };

    final mapByName = <String, GameMap>{};
    final allMaps = await isar.gameMaps.where().findAll();
    for (final map in allMaps) {
      final name = map.name.trim();
      if (name.isNotEmpty && normalized.contains(name)) {
        mapByName[name] = map;
      }
    }

    final scopedGrenades = <Grenade>[];
    for (final mapKey in normalized) {
      final map = mapByName[mapKey];
      if (map == null) continue;
      await map.layers.load();
      for (final layer in map.layers) {
        await layer.grenades.load();
        scopedGrenades.addAll(layer.grenades);
      }
    }
    if (scopedGrenades.isEmpty) return result;

    final exportBundle = await _buildExportBundle(scopedGrenades);
    for (final raw in exportBundle.grenades) {
      final item = Map<String, dynamic>.from(raw);
      final mapName = (item['mapName'] as String? ?? '').trim();
      if (!normalized.contains(mapName)) continue;
      final uniqueId = (item['uniqueId'] as String? ?? '').trim();
      if (uniqueId.isEmpty) continue;
      result.putIfAbsent(mapName, () => <String, String>{});
      result[mapName]![uniqueId] = _digestJsonValue(item);
    }

    return result;
  }

  String _digestJsonValue(Object? value) {
    final canonical = _canonicalizeJson(value);
    final encoded = jsonEncode(canonical);
    return sha256.convert(utf8.encode(encoded)).toString();
  }

  Map<String, dynamic> _normalizePayloadForSyncDigest(
    Map<String, dynamic> value, {
    bool removeHasLocalEdits = false,
  }) {
    final normalized =
        Map<String, dynamic>.from(_canonicalizeJson(value) as Map);
    normalized.remove('createdAt');
    normalized.remove('updatedAt');
    if (removeHasLocalEdits) {
      normalized.remove('hasLocalEdits');
    }
    return normalized;
  }

  Object? _canonicalizeJson(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      final normalized = <String, Object?>{};
      for (final entry in entries) {
        normalized[entry.key.toString()] = _canonicalizeJson(entry.value);
      }
      return normalized;
    }
    if (value is List) {
      return value.map(_canonicalizeJson).toList(growable: false);
    }
    return value;
  }

  String _normalizeStructuredJsonString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    try {
      final decoded = jsonDecode(trimmed);
      return jsonEncode(_canonicalizeJson(decoded));
    } catch (_) {
      return trimmed;
    }
  }

  bool _isSharedAreaEquivalent(MapArea local, PackageAreaData shared) {
    return local.name == shared.name &&
        local.colorValue == shared.colorValue &&
        _normalizeStructuredJsonString(local.strokes) ==
            _normalizeStructuredJsonString(shared.strokes);
  }

  /// 导出列表
  Future<void> exportSelectedGrenades(
      BuildContext context, List<Grenade> grenades) async {
    if (grenades.isEmpty) return;

    final exportBundle = await _buildExportBundle(grenades);

    // 获取临时目录路径
    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, "export_temp");
    final zipPath = p.join(tempDir.path, "share_data.cs2pkg");

    // 异步打包
    await compute(
      _packageFilesInIsolate,
      _PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(exportBundle.toJson()),
        filesToCopy: exportBundle.filesToZip.toList(),
      ),
    );

    if (!context.mounted) return;

    // 根据平台显示不同的分享选项
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    if (isDesktop) {
      // 另存为
      await _saveToFolderWithCustomName(context, zipPath);
    } else {
      // 底部菜单
      await showModalBottomSheet(
        context: context,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          decoration: const BoxDecoration(
            color: Color(0xFF2A2D33),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const Text("选择导出方式",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blueAccent),
                title: const Text("系统分享 (微信/QQ)",
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                      ShareParams(files: [XFile(zipPath)], text: "CS2 道具数据分享"));
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.folder_open, color: Colors.orangeAccent),
                title:
                    const Text("保存到文件夹", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveToFolderWithCustomName(context, zipPath);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> exportData(BuildContext context,
      {required int scopeType,
      Grenade? singleGrenade,
      GameMap? singleMap}) async {
    final grenades = <Grenade>[];

    // 1. 确定要导出的数据范围
    if (scopeType == 0 && singleGrenade != null) {
      grenades.add(singleGrenade);
    } else if (scopeType == 1 && singleMap != null) {
      singleMap.layers.loadSync();
      for (var layer in singleMap.layers) {
        layer.grenades.loadSync();
        grenades.addAll(layer.grenades);
      }
    } else {
      grenades.addAll(isar.grenades.where().findAllSync());
    }

    if (grenades.isEmpty) return;

    final exportBundle = await _buildExportBundle(grenades);

    // 3. 获取临时目录路径
    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, "export_temp");
    final zipPath = p.join(tempDir.path, "share_data.cs2pkg");

    // 4. 异步打包
    await compute(
      _packageFilesInIsolate,
      _PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(exportBundle.toJson()),
        filesToCopy: exportBundle.filesToZip.toList(),
      ),
    );

    if (!context.mounted) return;

    // 根据平台显示不同的分享选项
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    if (isDesktop) {
      // 另存为
      await _saveToFolderWithCustomName(context, zipPath);
    } else {
      // 底部菜单
      await showModalBottomSheet(
        context: context,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          decoration: const BoxDecoration(
            color: Color(0xFF2A2D33),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const Text("选择导出方式",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blueAccent),
                title: const Text("系统分享 (微信/QQ)",
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                      ShareParams(files: [XFile(zipPath)], text: "CS2 道具数据分享"));
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.folder_open, color: Colors.orangeAccent),
                title:
                    const Text("保存到文件夹", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveToFolderWithCustomName(context, zipPath);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  Set<String> _collectSelectedTagUuids(
      PackagePreviewResult preview, Set<String> selectedUniqueIds) {
    final result = <String>{};
    for (final mapItems in preview.grenadesByMap.values) {
      for (final item in mapItems) {
        if (!selectedUniqueIds.contains(item.uniqueId)) continue;
        final raw = item.rawData['tagUuids'];
        if (raw is! List) continue;
        for (final uuid in raw) {
          if (uuid is String && uuid.trim().isNotEmpty) {
            result.add(uuid.trim());
          }
        }
      }
    }
    return result;
  }

  String _semanticTagKey(int mapId, int dimension, String name) {
    return '$mapId|$dimension|${name.trim().toLowerCase()}';
  }

  bool _isTagDifferent(Tag local, PackageTagData shared) {
    return local.name != shared.name ||
        local.colorValue != shared.colorValue ||
        local.dimension != shared.dimension ||
        (local.groupName ?? '') != (shared.groupName ?? '') ||
        local.isSystem != shared.isSystem;
  }

  bool _requiresManualConflictResolution({
    required int sharedUpdatedAtMs,
    required int localUpdatedAtMs,
    required bool contentDifferent,
  }) {
    return sharedUpdatedAtMs == localUpdatedAtMs && contentDifferent;
  }

  bool _shouldApplyIncomingUpdate({
    required int sharedUpdatedAtMs,
    required int localUpdatedAtMs,
    required bool contentDifferent,
  }) {
    if (sharedUpdatedAtMs > localUpdatedAtMs) return true;
    if (sharedUpdatedAtMs < localUpdatedAtMs) return false;
    return contentDifferent;
  }

  String _sha256BytesHex(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> _normalizeGrenadePayloadForSync(
    Map<String, dynamic> value,
  ) {
    return _normalizePayloadForSyncDigest(
      value,
      removeHasLocalEdits: true,
    );
  }

  Future<String> _sha256FileHex(String localPath) async {
    final normalized = localPath.trim();
    if (normalized.isEmpty) return '';
    final file = File(normalized);
    if (!await file.exists()) return '';
    return _sha256BytesHex(await file.readAsBytes());
  }

  Future<String> _buildLocalGrenadeDigest(Grenade grenade) async {
    final bundle = await _buildLanSyncBundle([grenade]);
    if (bundle.grenades.isEmpty) return '';
    final raw = bundle.grenades.first;
    final normalized = _normalizeGrenadePayloadForSync(raw);
    await grenade.steps.load();
    final localSteps = grenade.steps.toList(growable: false);
    final sharedSteps = ((normalized['steps'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    for (var i = 0; i < sharedSteps.length; i++) {
      final medias =
          ((sharedSteps[i]['medias'] as List?) ?? const []).cast<dynamic>();
      if (i >= localSteps.length) continue;
      final localStep = localSteps[i];
      await localStep.medias.load();
      final localMedias = localStep.medias.toList(growable: false);
      final normalizedMedias = <Map<String, dynamic>>[];
      for (var j = 0; j < medias.length; j++) {
        final mediaMap = Map<String, dynamic>.from(medias[j] as Map);
        final mediaHash = j < localMedias.length
            ? await _sha256FileHex(localMedias[j].localPath)
            : '';
        normalizedMedias.add({
          'type': mediaMap['type'],
          'contentHash': mediaHash,
        });
      }
      sharedSteps[i]['medias'] = normalizedMedias;
    }
    normalized['steps'] = sharedSteps;
    return _digestJsonValue(normalized);
  }

  String _buildSharedGrenadeDigest(
    Map<String, dynamic> item,
    Map<String, List<int>> memoryImages,
  ) {
    final normalized = _normalizeGrenadePayloadForSync(item);
    final sharedSteps = ((normalized['steps'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    for (var i = 0; i < sharedSteps.length; i++) {
      final medias =
          ((sharedSteps[i]['medias'] as List?) ?? const []).cast<dynamic>();
      final normalizedMedias = <Map<String, dynamic>>[];
      for (final media in medias) {
        final mediaMap = Map<String, dynamic>.from(media as Map);
        final fileName = (mediaMap['path'] as String? ?? '').trim();
        final mediaHash =
            fileName.isNotEmpty && memoryImages.containsKey(fileName)
                ? _sha256BytesHex(memoryImages[fileName]!)
                : '';
        normalizedMedias.add({
          'type': mediaMap['type'],
          'contentHash': mediaHash,
        });
      }
      sharedSteps[i]['medias'] = normalizedMedias;
    }
    normalized['steps'] = sharedSteps;
    return _digestJsonValue(normalized);
  }

  Future<bool> _shouldImportGrenadeOverLocal(
    Grenade local,
    Map<String, dynamic> shared,
    Map<String, List<int>> memoryImages,
  ) async {
    final sharedUpdatedAtMs = shared['updatedAt'] as int? ?? 0;
    final localUpdatedAtMs = local.updatedAt.millisecondsSinceEpoch;
    if (sharedUpdatedAtMs > localUpdatedAtMs) return true;
    if (sharedUpdatedAtMs < localUpdatedAtMs) return false;
    final localDigest = await _buildLocalGrenadeDigest(local);
    final sharedDigest = _buildSharedGrenadeDigest(shared, memoryImages);
    return localDigest != sharedDigest;
  }

  Set<String> _collectImportTagUuids(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds,
  ) {
    final selected = _collectSelectedTagUuids(preview, selectedUniqueIds);
    final uuids = <String>{
      ...selected,
      ...preview.tagsByUuid.keys
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty),
      ...preview.areas.map((e) => e.tagUuid.trim()).where((e) => e.isNotEmpty),
    };
    return uuids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<_LocalTagContext> _buildLocalTagContext(Set<String> mapNames) async {
    final mapByName = <String, GameMap>{};
    for (final mapName in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map != null) {
        mapByName[mapName] = map;
      }
    }

    final localByUuid = <String, Tag>{};
    final localBySemantic = <String, Tag>{};
    for (final map in mapByName.values) {
      final tags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
      for (final tag in tags) {
        final uuid = tag.tagUuid.trim();
        if (uuid.isNotEmpty) {
          localByUuid[uuid] = tag;
        }
        localBySemantic[_semanticTagKey(map.id, tag.dimension, tag.name)] = tag;
      }
    }

    return _LocalTagContext(
      mapByName: mapByName,
      localByUuid: localByUuid,
      localBySemantic: localBySemantic,
    );
  }

  Future<ImportConflictBundle> collectTagConflicts(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds,
  ) async {
    if (preview.schemaVersion < 2 || preview.tagsByUuid.isEmpty) {
      return const ImportConflictBundle(tagConflicts: [], localTagByUuid: {});
    }

    final usedUuids = _collectImportTagUuids(preview, selectedUniqueIds);
    if (usedUuids.isEmpty) {
      return const ImportConflictBundle(tagConflicts: [], localTagByUuid: {});
    }

    final tagMapNames = <String>{};
    for (final uuid in usedUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared != null && shared.mapName.isNotEmpty) {
        tagMapNames.add(shared.mapName);
      }
    }

    final context = await _buildLocalTagContext(tagMapNames);
    final conflicts = <TagConflictItem>[];

    for (final uuid in usedUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared == null) continue;
      final localByUuid = context.localByUuid[uuid];
      if (localByUuid != null) {
        final contentDifferent = _isTagDifferent(localByUuid, shared);
        if (_requiresManualConflictResolution(
          sharedUpdatedAtMs: shared.updatedAt,
          localUpdatedAtMs: localByUuid.updatedAt.millisecondsSinceEpoch,
          contentDifferent: contentDifferent,
        )) {
          conflicts.add(TagConflictItem(
            type: TagConflictType.uuidMismatch,
            sharedTag: shared,
            localTag: localByUuid,
          ));
        }
        continue;
      }

      final map = context.mapByName[shared.mapName];
      if (map == null) continue;
      final semanticKey =
          _semanticTagKey(map.id, shared.dimension, shared.name);
      final semanticTag = context.localBySemantic[semanticKey];
      if (semanticTag != null) {
        final contentDifferent =
            _isTagDifferent(semanticTag, shared) || semanticTag.tagUuid != uuid;
        if (_requiresManualConflictResolution(
          sharedUpdatedAtMs: shared.updatedAt,
          localUpdatedAtMs: semanticTag.updatedAt.millisecondsSinceEpoch,
          contentDifferent: contentDifferent,
        )) {
          conflicts.add(TagConflictItem(
            type: TagConflictType.semanticMatch,
            sharedTag: shared,
            localTag: semanticTag,
          ));
        }
      }
    }

    return ImportConflictBundle(
      tagConflicts: conflicts,
      localTagByUuid: context.localByUuid,
    );
  }

  Future<List<AreaConflictGroup>> collectAreaConflicts(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    required Map<String, ImportTagConflictResolution> tagResolutions,
  }) async {
    if (preview.schemaVersion < 2 ||
        preview.areas.isEmpty ||
        preview.tagsByUuid.isEmpty) {
      return const [];
    }

    final usedUuids = _collectImportTagUuids(preview, selectedUniqueIds)
      ..removeWhere((uuid) {
        final shared = preview.tagsByUuid[uuid];
        return shared == null || shared.dimension != TagDimension.area;
      });
    if (usedUuids.isEmpty) return const [];

    final tagMapNames = <String>{};
    for (final uuid in usedUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared != null && shared.mapName.isNotEmpty) {
        tagMapNames.add(shared.mapName);
      }
    }
    final context = await _buildLocalTagContext(tagMapNames);

    final groupLayers = <String, Set<String>>{};

    for (final tagUuid in usedUuids) {
      final sharedTag = preview.tagsByUuid[tagUuid];
      if (sharedTag == null) continue;

      Tag? localTag = context.localByUuid[tagUuid];
      final map = context.mapByName[sharedTag.mapName];
      if (map == null) continue;

      if (localTag == null) {
        final semanticKey =
            _semanticTagKey(map.id, sharedTag.dimension, sharedTag.name);
        final semanticTag = context.localBySemantic[semanticKey];
        if (semanticTag != null) {
          final resolution = tagResolutions[tagUuid];
          if (resolution == ImportTagConflictResolution.local ||
              resolution == ImportTagConflictResolution.shared) {
            localTag = semanticTag;
          }
        }
      }
      if (localTag == null) continue;

      await map.layers.load();
      final layerIdByName = <String, int>{
        for (final l in map.layers) l.name: l.id,
      };

      final existingAreas = await isar.mapAreas
          .filter()
          .mapIdEqualTo(map.id)
          .tagIdEqualTo(localTag.id)
          .findAll();

      final tagAreas = preview.areas.where((a) =>
          a.tagUuid == tagUuid &&
          a.mapName == sharedTag.mapName &&
          a.layerName.isNotEmpty);
      for (final area in tagAreas) {
        final layerId = layerIdByName[area.layerName];
        if (layerId == null) continue;
        final sameLayerAreas = existingAreas
            .where((a) => a.layerId == layerId)
            .toList(growable: false);
        if (sameLayerAreas.isEmpty) continue;
        final hasEquivalent = sameLayerAreas.any(
          (localArea) => _isSharedAreaEquivalent(localArea, area),
        );
        if (hasEquivalent) continue;

        sameLayerAreas.sort((a, b) {
          if (a.updatedAt.isAfter(b.updatedAt)) return -1;
          if (a.updatedAt.isBefore(b.updatedAt)) return 1;
          return b.id.compareTo(a.id);
        });
        final target = sameLayerAreas.first;
        final contentDifferent = !_isSharedAreaEquivalent(target, area);
        if (!_requiresManualConflictResolution(
          sharedUpdatedAtMs: area.updatedAt,
          localUpdatedAtMs: target.updatedAt.millisecondsSinceEpoch,
          contentDifferent: contentDifferent,
        )) {
          continue;
        }

        final key = '$tagUuid|${sharedTag.name}|${sharedTag.mapName}';
        groupLayers.putIfAbsent(key, () => <String>{}).add(area.layerName);
      }
    }

    final groups = <AreaConflictGroup>[];
    for (final entry in groupLayers.entries) {
      final parts = entry.key.split('|');
      groups.add(AreaConflictGroup(
        tagUuid: parts[0],
        tagName: parts[1],
        mapName: parts[2],
        layers: (entry.value.toList()..sort()),
      ));
    }
    groups.sort((a, b) => a.tagName.compareTo(b.tagName));
    return groups;
  }

  Future<ImportConflictNotice> collectImportConflictNotice(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds,
  ) async {
    final newerLocalGrenades = <GrenadePreviewItem>[];
    for (final mapItems in preview.grenadesByMap.values) {
      for (final item in mapItems) {
        if (!selectedUniqueIds.contains(item.uniqueId)) continue;
        if (item.status == ImportStatus.skip) {
          newerLocalGrenades.add(item);
        }
      }
    }

    final newerLocalDeleteConflicts = <GrenadePreviewItem>[];
    if (preview.grenadeTombstones.isNotEmpty) {
      final localItems = await loadLocalGrenadePreviewItemsByUniqueIds(
        preview.grenadeTombstones.map((e) => e.uniqueId),
      );
      for (final tombstone in preview.grenadeTombstones) {
        final local = localItems[tombstone.uniqueId];
        if (local == null) continue;
        final deletedAt =
            DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
        if (local.updatedAt.isAfter(deletedAt)) {
          newerLocalDeleteConflicts.add(local);
        }
      }
    }

    final newerLocalFavoriteFolderDeletes = <String>[];
    final favoriteFolderTombstones = preview.entityTombstones
        .where((e) => e.entityType == LanSyncEntityTombstoneType.favoriteFolder)
        .toList(growable: false);
    if (favoriteFolderTombstones.isNotEmpty) {
      final mapNames =
          favoriteFolderTombstones.map((e) => e.mapName).toSet().toList();
      final mapByName = <String, GameMap>{};
      for (final mapName in mapNames) {
        final map =
            await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
        if (map != null) {
          mapByName[mapName] = map;
        }
      }
      for (final tombstone in favoriteFolderTombstones) {
        final map = mapByName[tombstone.mapName];
        final nameKey = _normalizeFolderNameKey(
            tombstone.payload['nameKey'] as String? ?? '');
        if (map == null || nameKey.isEmpty) continue;
        final folders =
            await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
        final local = folders.where((folder) {
          final localKey = folder.nameKey.trim().isEmpty
              ? _normalizeFolderNameKey(folder.name)
              : _normalizeFolderNameKey(folder.nameKey);
          return localKey == nameKey;
        }).firstOrNull;
        if (local == null) continue;
        final deletedAt =
            DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
        if (local.updatedAt.isAfter(deletedAt)) {
          newerLocalFavoriteFolderDeletes
              .add('${tombstone.mapName} / ${local.name}');
        }
      }
    }

    return ImportConflictNotice(
      newerLocalGrenades: newerLocalGrenades,
      newerLocalDeleteConflicts: newerLocalDeleteConflicts,
      newerLocalFavoriteFolderDeletes: newerLocalFavoriteFolderDeletes,
    );
  }

  // --- 导入 ---

  Future<String> importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要导入的 .cs2pkg 文件',
    );
    if (result == null) return "取消导入";

    final filePath = result.files.single.path!;
    return importFromPath(filePath);
  }

  /// 导入路径
  Future<String> importFromPath(String filePath) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return "请选择 .cs2pkg 格式的文件";
    }

    final preview = await previewPackage(filePath);
    if (preview == null) return "文件格式错误或无数据";

    final selected = <String>{};
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final item in mapGrenades) {
        if (item.status != ImportStatus.skip) {
          selected.add(item.uniqueId);
        }
      }
    }

    return importFromPreview(
      preview,
      selected,
      tagResolutions: const {},
      areaResolutions: const {},
    );
  }

  /// 预览导入
  Future<String> importFromPreview(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds, {
    Map<String, ImportTagConflictResolution> tagResolutions = const {},
    Map<String, ImportAreaConflictResolution> areaResolutions = const {},
  }) async {
    final hasGrenadeSelection = selectedUniqueIds.isNotEmpty;
    final hasMetadataChanges = preview.tagsByUuid.isNotEmpty ||
        preview.areas.isNotEmpty ||
        preview.favoriteFolders.isNotEmpty ||
        preview.impactGroups.isNotEmpty;
    final hasTombstones = preview.grenadeTombstones.isNotEmpty ||
        preview.entityTombstones.isNotEmpty;
    if (!hasGrenadeSelection && !hasMetadataChanges && !hasTombstones) {
      return "未选择任何道具";
    }

    final importFileName = p.basename(preview.filePath);
    final dataPath = isar.directory ?? '';
    final memoryImages = preview.memoryImages;

    final tombstoneResult = await _applyGrenadeTombstones(preview);
    final entityTombstoneResult = await _applyEntityTombstones(preview);

    final selectedTagUuids = _collectImportTagUuids(preview, selectedUniqueIds);
    final tagIdByUuid = await _upsertTagsForImport(
      preview,
      selectedTagUuids,
      tagResolutions: tagResolutions,
    );
    await _upsertAreasForImport(
      preview,
      selectedTagUuids,
      tagIdByUuid: tagIdByUuid,
      areaResolutions: areaResolutions,
    );
    final favoriteFolderIdByRef = await _upsertFavoriteFoldersForImport(
      preview,
    );
    final impactGroupIdByRef = await _upsertImpactGroupsForImport(
      preview,
    );

    int newCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    final importedGrenades = <Grenade>[];

    if (hasGrenadeSelection) {
      for (final mapGrenades in preview.grenadesByMap.values) {
        for (final previewItem in mapGrenades) {
          if (!selectedUniqueIds.contains(previewItem.uniqueId)) continue;

          final item = previewItem.rawData;
          final mapName = item['mapName'];
          final layerName = item['layerName'];

          final map =
              await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
          if (map == null) continue;

          await map.layers.load();
          MapLayer? layer;
          for (final l in map.layers) {
            if (l.name == layerName) {
              layer = l;
              break;
            }
          }
          layer ??= map.layers.isNotEmpty ? map.layers.first : null;
          if (layer == null) continue;

          final importedUniqueId = item['uniqueId'] as String?;
          final title = item['title'] as String;
          final xRatio = (item['x'] as num).toDouble();
          final yRatio = (item['y'] as num).toDouble();
          final tagUuids = _readTagUuids(item);

          Grenade? existing;
          if (importedUniqueId != null && importedUniqueId.isNotEmpty) {
            final allGrenades = await isar.grenades.where().findAll();
            existing = allGrenades
                .where((g) => g.uniqueId == importedUniqueId)
                .firstOrNull;
          }
          if (existing == null && importedUniqueId == null) {
            await layer.grenades.load();
            existing = layer.grenades
                .where((g) =>
                    g.title == title &&
                    (g.xRatio - xRatio).abs() < 0.01 &&
                    (g.yRatio - yRatio).abs() < 0.01)
                .firstOrNull;
          }

          if (existing != null) {
            if (await _shouldImportGrenadeOverLocal(
              existing,
              item,
              memoryImages,
            )) {
              await _updateExistingGrenade(
                  existing, item, memoryImages, dataPath);
              await _replaceGrenadeTags(existing.id, tagUuids, tagIdByUuid);
              await _applyLanSyncRefsToGrenade(
                existing,
                item,
                favoriteFolderIdByRef: favoriteFolderIdByRef,
                impactGroupIdByRef: impactGroupIdByRef,
              );
              importedGrenades.add(existing);
              updatedCount++;
            } else {
              skippedCount++;
            }
          } else {
            final newGrenade = await _createNewGrenade(
              item,
              memoryImages,
              dataPath,
              layer,
              importedUniqueId,
            );
            await _replaceGrenadeTags(newGrenade.id, tagUuids, tagIdByUuid);
            await _applyLanSyncRefsToGrenade(
              newGrenade,
              item,
              favoriteFolderIdByRef: favoriteFolderIdByRef,
              impactGroupIdByRef: impactGroupIdByRef,
            );
            importedGrenades.add(newGrenade);
            newCount++;
          }
        }
      }
      if (importedGrenades.isNotEmpty) {
        final importedIds = importedGrenades
            .map((e) => e.id)
            .where((id) => id > 0)
            .toList(growable: false);
        await isar.writeTxn(() async {
          final history = ImportHistory(
            fileName: importFileName,
            importedAt: DateTime.now(),
            newCount: newCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount,
          );
          await isar.importHistorys.put(history);
          final savedGrenades = await isar.grenades.getAll(importedIds);
          history.grenades.addAll(savedGrenades.whereType<Grenade>());
          await history.grenades.save();
        });
      }
    }

    final List<String> messages = [];
    if (newCount > 0) messages.add("新增 $newCount 个");
    if (updatedCount > 0) messages.add("更新 $updatedCount 个");
    if (skippedCount > 0) messages.add("跳过 $skippedCount 个较旧版本");
    if (tombstoneResult.deletedCount > 0) {
      messages.add("删除 ${tombstoneResult.deletedCount} 个");
    }
    if (tombstoneResult.skippedCount > 0) {
      messages.add("忽略 ${tombstoneResult.skippedCount} 条较新的本地版本");
    }
    if (entityTombstoneResult.deletedByType.isNotEmpty) {
      final orderedTypes = <String>[
        LanSyncEntityTombstoneType.tag,
        LanSyncEntityTombstoneType.area,
        LanSyncEntityTombstoneType.favoriteFolder,
        LanSyncEntityTombstoneType.impactGroup,
      ];
      for (final type in orderedTypes) {
        final count = entityTombstoneResult.deletedByType[type] ?? 0;
        if (count <= 0) continue;
        messages.add('${_entityTypeLabel(type)}删除 $count 条');
      }
    }
    if (entityTombstoneResult.skippedByType.isNotEmpty) {
      final orderedTypes = <String>[
        LanSyncEntityTombstoneType.favoriteFolder,
      ];
      for (final type in orderedTypes) {
        final count = entityTombstoneResult.skippedByType[type] ?? 0;
        if (count <= 0) continue;
        messages.add('忽略 $count 条较新的${_entityTypeLabel(type)}删除');
      }
    }
    if (!hasGrenadeSelection) {
      if (selectedTagUuids.isNotEmpty) {
        messages.add('标签同步 ${selectedTagUuids.length} 条');
      }
      if (preview.areas.isNotEmpty) {
        messages.add('区域同步 ${preview.areas.length} 条');
      }
      if (preview.favoriteFolders.isNotEmpty) {
        messages.add('收藏夹同步 ${preview.favoriteFolders.length} 条');
      }
      if (preview.impactGroups.isNotEmpty) {
        messages.add('爆点分组同步 ${preview.impactGroups.length} 条');
      }
    }

    if (messages.isEmpty) {
      return "没有可导入的道具";
    }
    return "成功导入：${messages.join('，')}";
  }

  Future<({int deletedCount, int skippedCount})> _applyGrenadeTombstones(
    PackagePreviewResult preview,
  ) async {
    if (preview.grenadeTombstones.isEmpty) {
      return (deletedCount: 0, skippedCount: 0);
    }

    final allGrenades = await isar.grenades.where().findAll();
    final grenadeByUniqueId = <String, Grenade>{};
    for (final grenade in allGrenades) {
      final uniqueId = (grenade.uniqueId ?? '').trim();
      if (uniqueId.isNotEmpty) {
        grenadeByUniqueId[uniqueId] = grenade;
      }
    }

    final toDelete = <Grenade>[];
    var skippedCount = 0;
    for (final tombstone in preview.grenadeTombstones) {
      final grenade = grenadeByUniqueId[tombstone.uniqueId];
      if (grenade == null) continue;
      final deletedAt =
          DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
      if (grenade.updatedAt.isAfter(deletedAt)) {
        skippedCount++;
        continue;
      }
      toDelete.add(grenade);
    }

    final deletedCount =
        await deleteGrenades(toDelete, recordSyncTombstones: false);
    return (deletedCount: deletedCount, skippedCount: skippedCount);
  }

  String _entityTypeLabel(String type) {
    switch (type) {
      case LanSyncEntityTombstoneType.tag:
        return '标签';
      case LanSyncEntityTombstoneType.area:
        return '区域';
      case LanSyncEntityTombstoneType.favoriteFolder:
        return '收藏夹';
      case LanSyncEntityTombstoneType.impactGroup:
        return '爆点分组';
      default:
        return '对象';
    }
  }

  Future<EntityTombstoneApplyResult> _applyEntityTombstones(
    PackagePreviewResult preview,
  ) async {
    if (preview.entityTombstones.isEmpty) {
      return const EntityTombstoneApplyResult(
        deletedCount: 0,
        skippedCount: 0,
      );
    }

    final deletedByType = <String, int>{};
    final skippedByType = <String, int>{};

    void markDeleted(String type) {
      deletedByType[type] = (deletedByType[type] ?? 0) + 1;
    }

    void markSkipped(String type) {
      skippedByType[type] = (skippedByType[type] ?? 0) + 1;
    }

    final mapByName = <String, GameMap>{};
    Future<GameMap?> resolveMap(String mapName) async {
      final key = mapName.trim();
      if (key.isEmpty) return null;
      final existing = mapByName[key];
      if (existing != null) return existing;
      final map = await isar.gameMaps.filter().nameEqualTo(key).findFirst();
      if (map != null) {
        mapByName[key] = map;
      }
      return map;
    }

    for (final tombstone in preview.entityTombstones) {
      switch (tombstone.entityType) {
        case LanSyncEntityTombstoneType.tag:
          final tagUuid =
              (tombstone.payload['tagUuid'] as String? ?? tombstone.entityKey)
                  .trim();
          if (tagUuid.isEmpty) continue;
          final tag =
              await isar.tags.filter().tagUuidEqualTo(tagUuid).findFirst();
          if (tag == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (tag.updatedAt.isAfter(deletedAt)) {
            markSkipped(tombstone.entityType);
            continue;
          }
          final deleteRelatedAreas =
              tombstone.payload['deleteRelatedAreas'] == true;
          await isar.writeTxn(() async {
            await isar.grenadeTags.filter().tagIdEqualTo(tag.id).deleteAll();
            if (deleteRelatedAreas) {
              await isar.mapAreas.filter().tagIdEqualTo(tag.id).deleteAll();
            }
            await isar.tags.delete(tag.id);
          });
          markDeleted(tombstone.entityType);
          break;
        case LanSyncEntityTombstoneType.area:
          final tagUuid =
              (tombstone.payload['tagUuid'] as String? ?? '').trim();
          final layerName =
              (tombstone.payload['layerName'] as String? ?? '').trim();
          final map = await resolveMap(tombstone.mapName);
          if (tagUuid.isEmpty || layerName.isEmpty || map == null) continue;
          final tag =
              await isar.tags.filter().tagUuidEqualTo(tagUuid).findFirst();
          if (tag == null || tag.mapId != map.id) continue;
          await map.layers.load();
          final layer = map.layers
              .where((item) => item.name.trim() == layerName)
              .firstOrNull;
          if (layer == null) continue;
          final matchedAreas = await isar.mapAreas
              .filter()
              .mapIdEqualTo(map.id)
              .tagIdEqualTo(tag.id)
              .and()
              .layerIdEqualTo(layer.id)
              .findAll();
          if (matchedAreas.isEmpty) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (matchedAreas.any((item) => item.updatedAt.isAfter(deletedAt))) {
            markSkipped(tombstone.entityType);
            continue;
          }
          await isar.writeTxn(() async {
            await isar.mapAreas
                .deleteAll(matchedAreas.map((item) => item.id).toList());
          });
          markDeleted(tombstone.entityType);
          break;
        case LanSyncEntityTombstoneType.favoriteFolder:
          final map = await resolveMap(tombstone.mapName);
          final nameKey = _normalizeFolderNameKey(
              tombstone.payload['nameKey'] as String? ?? '');
          if (map == null || nameKey.isEmpty) continue;
          final folders = await isar.favoriteFolders
              .filter()
              .mapIdEqualTo(map.id)
              .findAll();
          final folder = folders.where((item) {
            final localKey = item.nameKey.trim().isEmpty
                ? _normalizeFolderNameKey(item.name)
                : _normalizeFolderNameKey(item.nameKey);
            return localKey == nameKey;
          }).firstOrNull;
          if (folder == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (folder.updatedAt.isAfter(deletedAt)) {
            markSkipped(tombstone.entityType);
            continue;
          }
          final folderService = FavoriteFolderService(isar);
          await folderService.deleteFolder(
            folder.id,
            FavoriteFolderDeleteStrategy.unfavorite,
            recordSyncTombstone: false,
          );
          markDeleted(tombstone.entityType);
          break;
        case LanSyncEntityTombstoneType.impactGroup:
          final map = await resolveMap(tombstone.mapName);
          final layerName =
              (tombstone.payload['layerName'] as String? ?? '').trim();
          final name = (tombstone.payload['name'] as String? ?? '').trim();
          final type = tombstone.payload['type'] as int?;
          final impactXRatio =
              (tombstone.payload['impactXRatio'] as num?)?.toDouble();
          final impactYRatio =
              (tombstone.payload['impactYRatio'] as num?)?.toDouble();
          if (map == null ||
              layerName.isEmpty ||
              name.isEmpty ||
              type == null ||
              impactXRatio == null ||
              impactYRatio == null) {
            continue;
          }
          await map.layers.load();
          final layer = map.layers
              .where((item) => item.name.trim() == layerName)
              .firstOrNull;
          if (layer == null) continue;
          final groups = await isar.impactGroups
              .filter()
              .layerIdEqualTo(layer.id)
              .findAll();
          final targetKey = buildImpactGroupEntityKey(
            mapName: map.name,
            layerName: layer.name,
            type: type,
            name: name,
            impactXRatio: impactXRatio,
            impactYRatio: impactYRatio,
          );
          final group = groups.where((item) {
            final currentKey = buildImpactGroupEntityKey(
              mapName: map.name,
              layerName: layer.name,
              type: item.type,
              name: item.name,
              impactXRatio: item.impactXRatio,
              impactYRatio: item.impactYRatio,
            );
            return currentKey == targetKey;
          }).firstOrNull;
          if (group == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (group.updatedAt.isAfter(deletedAt)) {
            markSkipped(tombstone.entityType);
            continue;
          }
          await deleteImpactGroup(group, recordSyncTombstone: false);
          markDeleted(tombstone.entityType);
          break;
      }
    }

    final deletedCount =
        deletedByType.values.fold(0, (sum, item) => sum + item);
    final skippedCount =
        skippedByType.values.fold(0, (sum, item) => sum + item);
    return EntityTombstoneApplyResult(
      deletedCount: deletedCount,
      skippedCount: skippedCount,
      deletedByType: deletedByType,
      skippedByType: skippedByType,
    );
  }

  List<String> _readTagUuids(Map<String, dynamic> item) {
    final raw = item['tagUuids'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    return const [];
  }

  _PackageFavoriteFolderRef? _readFavoriteFolderRef(Map<String, dynamic> item) {
    final raw = item['favoriteFolderRef'];
    if (raw is! Map) return null;
    final mapName = (raw['mapName'] as String? ?? '').trim();
    final nameKey = _normalizeFolderNameKey(raw['nameKey'] as String? ?? '');
    if (mapName.isEmpty || nameKey.isEmpty) return null;
    return _PackageFavoriteFolderRef(mapName: mapName, nameKey: nameKey);
  }

  _PackageImpactGroupRef? _readImpactGroupRef(Map<String, dynamic> item) {
    final raw = item['impactGroupRef'];
    if (raw is! Map) return null;
    final mapName = (raw['mapName'] as String? ?? '').trim();
    final layerName = (raw['layerName'] as String? ?? '').trim();
    final name = (raw['name'] as String? ?? '').trim();
    final type = raw['type'] as int?;
    final x = (raw['impactXRatio'] as num?)?.toDouble();
    final y = (raw['impactYRatio'] as num?)?.toDouble();
    if (mapName.isEmpty ||
        layerName.isEmpty ||
        name.isEmpty ||
        type == null ||
        x == null ||
        y == null) {
      return null;
    }
    return _PackageImpactGroupRef(
      mapName: mapName,
      layerName: layerName,
      name: name,
      type: type,
      impactXRatio: x,
      impactYRatio: y,
    );
  }

  Future<Map<String, int>> _upsertFavoriteFoldersForImport(
    PackagePreviewResult preview,
  ) async {
    if (preview.schemaVersion < 3) {
      return const {};
    }

    final referencedKeys = <String>{};
    final referencedRefsByKey = <String, _PackageFavoriteFolderRef>{};
    final referencedMapNames = <String>{};
    for (final folder in preview.favoriteFolders) {
      final nameKey = folder.nameKey.trim().isEmpty
          ? _normalizeFolderNameKey(folder.name)
          : _normalizeFolderNameKey(folder.nameKey);
      if (folder.mapName.trim().isEmpty || nameKey.isEmpty) continue;
      referencedMapNames.add(folder.mapName.trim());
      final key = _favoriteFolderRefKey(
        mapName: folder.mapName,
        nameKey: nameKey,
      );
      referencedKeys.add(key);
      referencedRefsByKey[key] = _PackageFavoriteFolderRef(
        mapName: folder.mapName.trim(),
        nameKey: nameKey,
      );
    }
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final previewItem in mapGrenades) {
        final ref = _readFavoriteFolderRef(previewItem.rawData);
        if (ref == null) continue;
        referencedMapNames.add(ref.mapName);
        final key = _favoriteFolderRefKey(
          mapName: ref.mapName,
          nameKey: ref.nameKey,
        );
        referencedKeys.add(key);
        referencedRefsByKey[key] = ref;
      }
    }
    if (referencedKeys.isEmpty) return const {};

    final sharedByKey = <String, PackageFavoriteFolderData>{};
    for (final folder in preview.favoriteFolders) {
      final nameKey = folder.nameKey.trim().isEmpty
          ? _normalizeFolderNameKey(folder.name)
          : _normalizeFolderNameKey(folder.nameKey);
      final key =
          _favoriteFolderRefKey(mapName: folder.mapName, nameKey: nameKey);
      if (!referencedKeys.contains(key)) continue;
      final existing = sharedByKey[key];
      if (existing == null || folder.updatedAt >= existing.updatedAt) {
        sharedByKey[key] = folder;
      }
    }
    final mapNames = <String>{
      ...sharedByKey.values.map((e) => e.mapName),
      ...referencedMapNames,
    };
    final mapByName = <String, GameMap>{};
    for (final mapName in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map != null) {
        mapByName[mapName] = map;
      }
    }

    final foldersByMapIdAndNameKey = <String, FavoriteFolder>{};
    for (final map in mapByName.values) {
      final folders =
          await isar.favoriteFolders.filter().mapIdEqualTo(map.id).findAll();
      for (final folder in folders) {
        final nameKey = folder.nameKey.trim().isEmpty
            ? _normalizeFolderNameKey(folder.name)
            : _normalizeFolderNameKey(folder.nameKey);
        foldersByMapIdAndNameKey['${map.id}|$nameKey'] = folder;
      }
    }

    final toCreate = <FavoriteFolder>[];
    final toUpdate = <FavoriteFolder>[];
    final result = <String, int>{};

    for (final entry in sharedByKey.entries) {
      final shared = entry.value;
      final map = mapByName[shared.mapName];
      if (map == null) continue;

      final normalizedNameKey = shared.nameKey.trim().isEmpty
          ? _normalizeFolderNameKey(shared.name)
          : _normalizeFolderNameKey(shared.nameKey);
      final localKey = '${map.id}|$normalizedNameKey';
      final local = foldersByMapIdAndNameKey[localKey];

      if (local == null) {
        final created = FavoriteFolder(
          mapId: map.id,
          name: shared.name.isEmpty ? normalizedNameKey : shared.name,
          nameKey: normalizedNameKey,
          sortOrder: shared.sortOrder,
          created: DateTime.fromMillisecondsSinceEpoch(shared.createdAt),
          updated: DateTime.fromMillisecondsSinceEpoch(shared.updatedAt),
        );
        toCreate.add(created);
        foldersByMapIdAndNameKey[localKey] = created;
        continue;
      }

      final sharedUpdated =
          DateTime.fromMillisecondsSinceEpoch(shared.updatedAt);
      if (_shouldApplyIncomingUpdate(
        sharedUpdatedAtMs: shared.updatedAt,
        localUpdatedAtMs: local.updatedAt.millisecondsSinceEpoch,
        contentDifferent:
            local.name != (shared.name.isEmpty ? local.name : shared.name) ||
                local.nameKey != normalizedNameKey ||
                local.sortOrder != shared.sortOrder,
      )) {
        final nextName = shared.name.isEmpty ? local.name : shared.name;
        final changed = local.name != nextName ||
            local.nameKey != normalizedNameKey ||
            local.sortOrder != shared.sortOrder ||
            local.updatedAt != sharedUpdated;
        if (changed) {
          local.name = nextName;
          local.nameKey = normalizedNameKey;
          local.sortOrder = shared.sortOrder;
          local.updatedAt = sharedUpdated;
          toUpdate.add(local);
        }
      }
    }

    if (toCreate.isNotEmpty || toUpdate.isNotEmpty) {
      await isar.writeTxn(() async {
        if (toCreate.isNotEmpty) {
          await isar.favoriteFolders.putAll(toCreate);
        }
        if (toUpdate.isNotEmpty) {
          await isar.favoriteFolders.putAll(toUpdate);
        }
      });
    }

    for (final compositeKey in referencedKeys) {
      final ref = referencedRefsByKey[compositeKey];
      if (ref == null) continue;
      final map = mapByName[ref.mapName];
      if (map == null) continue;
      final local = foldersByMapIdAndNameKey['${map.id}|${ref.nameKey}'];
      if (local != null) {
        result[compositeKey] = local.id;
      }
    }
    for (final entry in sharedByKey.entries) {
      final shared = entry.value;
      final map = mapByName[shared.mapName];
      if (map == null) continue;
      final normalizedNameKey = shared.nameKey.trim().isEmpty
          ? _normalizeFolderNameKey(shared.name)
          : _normalizeFolderNameKey(shared.nameKey);
      final local = foldersByMapIdAndNameKey['${map.id}|$normalizedNameKey'];
      if (local != null) {
        result[entry.key] = local.id;
      }
    }

    return result;
  }

  Future<Map<String, int>> _upsertImpactGroupsForImport(
    PackagePreviewResult preview,
  ) async {
    if (preview.schemaVersion < 3) {
      return const {};
    }

    final referencedKeys = <String>{};
    for (final group in preview.impactGroups) {
      referencedKeys.add(_impactGroupSemanticKey(
        mapName: group.mapName,
        layerName: group.layerName,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      ));
    }
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final previewItem in mapGrenades) {
        final ref = _readImpactGroupRef(previewItem.rawData);
        if (ref == null) continue;
        referencedKeys.add(_impactGroupSemanticKey(
          mapName: ref.mapName,
          layerName: ref.layerName,
          type: ref.type,
          name: ref.name,
          impactXRatio: ref.impactXRatio,
          impactYRatio: ref.impactYRatio,
        ));
      }
    }
    if (referencedKeys.isEmpty) return const {};

    final sharedByKey = <String, PackageImpactGroupData>{};
    for (final group in preview.impactGroups) {
      final key = _impactGroupSemanticKey(
        mapName: group.mapName,
        layerName: group.layerName,
        type: group.type,
        name: group.name,
        impactXRatio: group.impactXRatio,
        impactYRatio: group.impactYRatio,
      );
      if (!referencedKeys.contains(key)) continue;
      final previous = sharedByKey[key];
      if (previous == null || group.updatedAt >= previous.updatedAt) {
        sharedByKey[key] = group;
      }
    }
    final mapNames = <String>{
      ...sharedByKey.values.map((e) => e.mapName),
      ...preview.grenadesByMap.keys,
    };
    final mapByName = <String, GameMap>{};
    final layerByMapAndName = <String, MapLayer>{};
    for (final mapName in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map == null) continue;
      mapByName[mapName] = map;
      await map.layers.load();
      for (final layer in map.layers) {
        layerByMapAndName['${map.name}|${layer.name}'] = layer;
      }
    }

    final localBySemanticKey = <String, ImpactGroup>{};
    final neededLayerIds = <int>{};
    for (final shared in sharedByKey.values) {
      final layer = layerByMapAndName['${shared.mapName}|${shared.layerName}'];
      if (layer != null) neededLayerIds.add(layer.id);
    }
    for (final layerId in neededLayerIds) {
      final groups =
          await isar.impactGroups.filter().layerIdEqualTo(layerId).findAll();
      final layer = await isar.mapLayers.get(layerId);
      if (layer == null) continue;
      await layer.map.load();
      final map = layer.map.value;
      if (map == null) continue;
      for (final group in groups) {
        final key = _impactGroupSemanticKey(
          mapName: map.name,
          layerName: layer.name,
          type: group.type,
          name: group.name,
          impactXRatio: group.impactXRatio,
          impactYRatio: group.impactYRatio,
        );
        localBySemanticKey[key] = group;
      }
    }

    final toCreate = <ImpactGroup>[];
    for (final entry in sharedByKey.entries) {
      if (localBySemanticKey.containsKey(entry.key)) continue;
      final shared = entry.value;
      final layer = layerByMapAndName['${shared.mapName}|${shared.layerName}'];
      if (layer == null) continue;
      final created = ImpactGroup(
        name: shared.name,
        type: shared.type,
        impactXRatio: shared.impactXRatio,
        impactYRatio: shared.impactYRatio,
        layerId: layer.id,
        created: DateTime.fromMillisecondsSinceEpoch(shared.createdAt),
        updated: DateTime.fromMillisecondsSinceEpoch(shared.updatedAt),
      );
      toCreate.add(created);
      localBySemanticKey[entry.key] = created;
    }

    if (toCreate.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.impactGroups.putAll(toCreate);
      });
    }

    final result = <String, int>{};
    for (final key in referencedKeys) {
      final local = localBySemanticKey[key];
      if (local != null) {
        result[key] = local.id;
      }
    }
    return result;
  }

  Future<void> _applyLanSyncRefsToGrenade(
    Grenade grenade,
    Map<String, dynamic> item, {
    required Map<String, int> favoriteFolderIdByRef,
    required Map<String, int> impactGroupIdByRef,
  }) async {
    bool changed = false;

    if (item.containsKey('isFavorite') ||
        item.containsKey('favoriteFolderRef')) {
      final isFavorite = item['isFavorite'] == true;
      int? favoriteFolderId;
      if (isFavorite) {
        final ref = _readFavoriteFolderRef(item);
        if (ref != null) {
          final key = _favoriteFolderRefKey(
            mapName: ref.mapName,
            nameKey: ref.nameKey,
          );
          favoriteFolderId = favoriteFolderIdByRef[key];
        }
      }

      final nextIsFavorite = isFavorite && favoriteFolderId != null;
      if (grenade.isFavorite != nextIsFavorite) {
        grenade.isFavorite = nextIsFavorite;
        changed = true;
      }
      if (grenade.favoriteFolderId != favoriteFolderId) {
        grenade.favoriteFolderId = favoriteFolderId;
        changed = true;
      }
    }

    if (item.containsKey('impactGroupRef')) {
      int? nextImpactGroupId;
      final ref = _readImpactGroupRef(item);
      if (ref != null) {
        final key = _impactGroupSemanticKey(
          mapName: ref.mapName,
          layerName: ref.layerName,
          type: ref.type,
          name: ref.name,
          impactXRatio: ref.impactXRatio,
          impactYRatio: ref.impactYRatio,
        );
        nextImpactGroupId = impactGroupIdByRef[key];
      }
      if (grenade.impactGroupId != nextImpactGroupId) {
        grenade.impactGroupId = nextImpactGroupId;
        changed = true;
      }
    }

    if (changed) {
      await isar.writeTxn(() async {
        await isar.grenades.put(grenade);
      });
    }
  }

  Future<void> _replaceGrenadeTags(
    int grenadeId,
    List<String> tagUuids,
    Map<String, int> tagIdByUuid,
  ) async {
    final targetTagIds = <int>{};
    for (final uuid in tagUuids) {
      final tagId = tagIdByUuid[uuid];
      if (tagId != null) {
        targetTagIds.add(tagId);
      }
    }

    await isar.writeTxn(() async {
      await isar.grenadeTags.filter().grenadeIdEqualTo(grenadeId).deleteAll();
      for (final tagId in targetTagIds) {
        await isar.grenadeTags
            .put(GrenadeTag(grenadeId: grenadeId, tagId: tagId));
      }
    });
  }

  Future<Map<String, int>> _upsertTagsForImport(
    PackagePreviewResult preview,
    Set<String> selectedTagUuids, {
    required Map<String, ImportTagConflictResolution> tagResolutions,
  }) async {
    if (selectedTagUuids.isEmpty) return const {};
    if (preview.tagsByUuid.isEmpty) {
      final localTagIdByUuid = <String, int>{};
      final allTags = await isar.tags.where().findAll();
      for (final tag in allTags) {
        final uuid = tag.tagUuid.trim();
        if (uuid.isEmpty || !selectedTagUuids.contains(uuid)) continue;
        localTagIdByUuid[uuid] = tag.id;
      }
      return localTagIdByUuid;
    }

    final tagMapNames = <String>{};
    for (final uuid in selectedTagUuids) {
      final shared = preview.tagsByUuid[uuid];
      if (shared != null && shared.mapName.isNotEmpty) {
        tagMapNames.add(shared.mapName);
      }
    }
    final context = await _buildLocalTagContext(tagMapNames);

    final toPut = <Tag>[];
    final toCreate = <Tag>[];
    final tagIdByUuid = <String, int>{};

    for (final tagUuid in selectedTagUuids) {
      final shared = preview.tagsByUuid[tagUuid];
      if (shared == null || shared.mapName.isEmpty) continue;
      final sharedUpdatedAt = shared.updatedAt;

      final map = context.mapByName[shared.mapName];
      if (map == null) continue;

      final localByUuid = context.localByUuid[tagUuid];
      if (localByUuid != null) {
        final resolution = tagResolutions[tagUuid];
        final shouldApplyShared =
            resolution == ImportTagConflictResolution.shared ||
                (resolution == null &&
                    sharedUpdatedAt >
                        localByUuid.updatedAt.millisecondsSinceEpoch &&
                    _isTagDifferent(localByUuid, shared));
        if (shouldApplyShared &&
            _shouldApplyIncomingUpdate(
              sharedUpdatedAtMs: sharedUpdatedAt,
              localUpdatedAtMs: localByUuid.updatedAt.millisecondsSinceEpoch,
              contentDifferent: _isTagDifferent(localByUuid, shared),
            )) {
          localByUuid.name = shared.name;
          localByUuid.dimension = shared.dimension;
          localByUuid.colorValue = shared.colorValue;
          localByUuid.groupName = shared.groupName;
          localByUuid.isSystem = shared.isSystem;
          localByUuid.updatedAt =
              DateTime.fromMillisecondsSinceEpoch(sharedUpdatedAt);
          toPut.add(localByUuid);
        }
        tagIdByUuid[tagUuid] = localByUuid.id;
        continue;
      }

      final semanticKey =
          _semanticTagKey(map.id, shared.dimension, shared.name);
      final semanticTag = context.localBySemantic[semanticKey];
      if (semanticTag != null) {
        final resolution = tagResolutions[tagUuid];
        final contentDifferent = _isTagDifferent(semanticTag, shared) ||
            semanticTag.tagUuid != tagUuid;
        final shouldApplyShared =
            resolution == ImportTagConflictResolution.shared ||
                (resolution == null &&
                    sharedUpdatedAt >
                        semanticTag.updatedAt.millisecondsSinceEpoch &&
                    contentDifferent);
        if (shouldApplyShared &&
            _shouldApplyIncomingUpdate(
              sharedUpdatedAtMs: sharedUpdatedAt,
              localUpdatedAtMs: semanticTag.updatedAt.millisecondsSinceEpoch,
              contentDifferent: contentDifferent,
            )) {
          semanticTag.tagUuid = tagUuid;
          semanticTag.name = shared.name;
          semanticTag.dimension = shared.dimension;
          semanticTag.colorValue = shared.colorValue;
          semanticTag.groupName = shared.groupName;
          semanticTag.isSystem = shared.isSystem;
          semanticTag.updatedAt =
              DateTime.fromMillisecondsSinceEpoch(sharedUpdatedAt);
          toPut.add(semanticTag);
          context.localByUuid[tagUuid] = semanticTag;
        }
        tagIdByUuid[tagUuid] = semanticTag.id;
        continue;
      }

      final newTag = Tag(
        tagUuid: tagUuid,
        name: shared.name,
        colorValue: shared.colorValue,
        dimension: shared.dimension,
        groupName: shared.groupName,
        isSystem: shared.isSystem,
        sortOrder: 0,
        mapId: map.id,
        updated: DateTime.fromMillisecondsSinceEpoch(sharedUpdatedAt),
      );
      toCreate.add(newTag);
    }

    if (toPut.isNotEmpty || toCreate.isNotEmpty) {
      await isar.writeTxn(() async {
        if (toPut.isNotEmpty) {
          await isar.tags.putAll(toPut);
        }
        for (final tag in toCreate) {
          await isar.tags.put(tag);
        }
      });
    }

    for (final tag in toCreate) {
      if (tag.tagUuid.trim().isNotEmpty) {
        tagIdByUuid[tag.tagUuid.trim()] = tag.id;
      }
    }

    // 对未命中的 UUID 再兜底查询一次，确保拿到映射
    if (tagIdByUuid.length < selectedTagUuids.length) {
      final allTags = await isar.tags.where().findAll();
      for (final tag in allTags) {
        final uuid = tag.tagUuid.trim();
        if (uuid.isEmpty || !selectedTagUuids.contains(uuid)) continue;
        tagIdByUuid[uuid] = tag.id;
      }
    }

    return tagIdByUuid;
  }

  Future<void> _upsertAreasForImport(
    PackagePreviewResult preview,
    Set<String> selectedTagUuids, {
    required Map<String, int> tagIdByUuid,
    required Map<String, ImportAreaConflictResolution> areaResolutions,
  }) async {
    if (preview.areas.isEmpty || selectedTagUuids.isEmpty) return;

    final mapNames = <String>{};
    for (final area in preview.areas) {
      if (selectedTagUuids.contains(area.tagUuid) && area.mapName.isNotEmpty) {
        mapNames.add(area.mapName);
      }
    }

    final mapByName = <String, GameMap>{};
    for (final name in mapNames) {
      final map = await isar.gameMaps.filter().nameEqualTo(name).findFirst();
      if (map != null) mapByName[name] = map;
    }

    final putAreas = <MapArea>[];
    final deleteAreaIds = <int>{};

    final dedupedShared = <String, PackageAreaData>{};
    for (final area in preview.areas) {
      if (!selectedTagUuids.contains(area.tagUuid)) continue;
      final key = '${area.tagUuid}|${area.mapName}|${area.layerName}';
      final previous = dedupedShared[key];
      if (previous == null || area.updatedAt >= previous.updatedAt) {
        dedupedShared[key] = area;
      }
    }

    for (final shared in dedupedShared.values) {
      final tagId = tagIdByUuid[shared.tagUuid];
      if (tagId == null) continue;
      final map = mapByName[shared.mapName];
      if (map == null) continue;
      await map.layers.load();

      MapLayer? layer;
      for (final l in map.layers) {
        if (l.name == shared.layerName) {
          layer = l;
          break;
        }
      }
      if (layer == null) continue;

      final existing = await isar.mapAreas
          .filter()
          .mapIdEqualTo(map.id)
          .tagIdEqualTo(tagId)
          .findAll();
      final layerId = layer.id;
      final sameLayer =
          existing.where((a) => a.layerId == layerId).toList(growable: false);
      if (sameLayer.isEmpty) {
        putAreas.add(MapArea(
          name: shared.name,
          colorValue: shared.colorValue,
          strokes: shared.strokes,
          mapId: map.id,
          layerId: layerId,
          tagId: tagId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(shared.createdAt),
          updated: DateTime.fromMillisecondsSinceEpoch(shared.updatedAt),
        ));
        continue;
      }

      sameLayer.sort((a, b) {
        if (a.updatedAt.isAfter(b.updatedAt)) return -1;
        if (a.updatedAt.isBefore(b.updatedAt)) return 1;
        return b.id.compareTo(a.id);
      });
      final target = sameLayer.first;
      final resolution = areaResolutions[shared.tagUuid];
      final contentDifferent = !_isSharedAreaEquivalent(target, shared);
      final shouldApplyShared =
          resolution == ImportAreaConflictResolution.overwriteShared ||
              (resolution == null &&
                  shared.updatedAt > target.updatedAt.millisecondsSinceEpoch &&
                  contentDifferent);
      if (!shouldApplyShared) {
        continue;
      }
      if (!_shouldApplyIncomingUpdate(
        sharedUpdatedAtMs: shared.updatedAt,
        localUpdatedAtMs: target.updatedAt.millisecondsSinceEpoch,
        contentDifferent: contentDifferent,
      )) {
        continue;
      }
      target.name = shared.name;
      target.colorValue = shared.colorValue;
      target.strokes = shared.strokes;
      target.updatedAt = DateTime.fromMillisecondsSinceEpoch(shared.updatedAt);
      putAreas.add(target);
      for (final duplicate in sameLayer.skip(1)) {
        deleteAreaIds.add(duplicate.id);
      }
    }

    if (putAreas.isEmpty && deleteAreaIds.isEmpty) return;
    await isar.writeTxn(() async {
      if (putAreas.isNotEmpty) {
        await isar.mapAreas.putAll(putAreas);
      }
      for (final id in deleteAreaIds) {
        await isar.mapAreas.delete(id);
      }
    });
  }

  /// 更新
  Future<void> _updateExistingGrenade(
    Grenade existing,
    Map<String, dynamic> item,
    Map<String, List<int>> memoryImages,
    String dataPath,
  ) async {
    // 更新信息
    existing.title = item['title'];
    existing.type = item['type'];
    existing.team = item['team'];
    existing.author = item['author'] as String?;
    existing.sourceUrl = item['sourceUrl'] as String?;
    existing.sourceNote = item['sourceNote'] as String?;
    existing.hasLocalEdits = false; // 重置
    existing.isImported = true; // 导入标记
    existing.xRatio = (item['x'] as num).toDouble();
    existing.yRatio = (item['y'] as num).toDouble();
    existing.impactXRatio = (item['impactX'] as num?)?.toDouble();
    existing.impactYRatio = (item['impactY'] as num?)?.toDouble();
    existing.impactAreaStrokes = item['impactAreaStrokes'] as String?;
    existing.updatedAt = DateTime.fromMillisecondsSinceEpoch(item['updatedAt']);
    existing.isNewImport = true;
    await isar.writeTxn(() async {
      await isar.grenades.put(existing);
    });

    // 删旧数据
    await existing.steps.load();
    final oldMediaPaths = <String>{};
    await isar.writeTxn(() async {
      for (final step in existing.steps) {
        await step.medias.load();
        for (final media in step.medias) {
          final path = media.localPath.trim();
          if (path.isNotEmpty) {
            oldMediaPaths.add(path);
          }
          await isar.stepMedias.delete(media.id);
        }
        await isar.grenadeSteps.delete(step.id);
      }
    });
    existing.steps.clear();
    await isar.writeTxn(() async {
      await existing.steps.save();
    });
    for (final path in oldMediaPaths) {
      await deleteMediaFileIfUnused(path);
    }

    // 创建新的 Steps 和 Medias
    final stepsList = item['steps'] as List;
    for (var sItem in stepsList) {
      final step = GrenadeStep(
        title: sItem['title'] ?? "",
        description: sItem['description'],
        stepIndex: sItem['index'],
      );
      final mediasList = sItem['medias'] as List;
      final mediasToCreate = <StepMedia>[];
      for (var mItem in mediasList) {
        final fileName = mItem['path'];
        if (memoryImages.containsKey(fileName)) {
          final savePath = p.join(
              dataPath, "${DateTime.now().millisecondsSinceEpoch}_$fileName");
          await File(savePath).writeAsBytes(memoryImages[fileName]!);

          mediasToCreate
              .add(StepMedia(localPath: savePath, type: mItem['type']));
        }
      }
      await isar.writeTxn(() async {
        await isar.grenadeSteps.put(step);
        step.grenade.value = existing;
        await step.grenade.save();
        existing.steps.add(step);
        for (final media in mediasToCreate) {
          await isar.stepMedias.put(media);
          media.step.value = step;
          await media.step.save();
          step.medias.add(media);
        }
        await step.medias.save();
      });
    }
    await isar.writeTxn(() async {
      await existing.steps.save();
    });
  }

  /// 创建新道具
  Future<Grenade> _createNewGrenade(
    Map<String, dynamic> item,
    Map<String, List<int>> memoryImages,
    String dataPath,
    MapLayer layer,
    String? uniqueId,
  ) async {
    final g = Grenade(
      title: item['title'],
      type: item['type'],
      team: item['team'],
      xRatio: (item['x'] as num).toDouble(),
      yRatio: (item['y'] as num).toDouble(),
      isNewImport: true,
      hasLocalEdits: false,
      isImported: true, // 标记为导入的道具
      uniqueId: uniqueId ?? const Uuid().v4(),
      created: item['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['createdAt'])
          : DateTime.now(),
      updated: item['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
          : DateTime.now(),
    );
    g.author = item['author'] as String?;
    g.sourceUrl = item['sourceUrl'] as String?;
    g.sourceNote = item['sourceNote'] as String?;
    g.impactXRatio = (item['impactX'] as num?)?.toDouble();
    g.impactYRatio = (item['impactY'] as num?)?.toDouble();
    g.impactAreaStrokes = item['impactAreaStrokes'] as String?;
    await isar.writeTxn(() async {
      await isar.grenades.put(g);
    });

    // 设置关联
    g.layer.value = layer;
    await isar.writeTxn(() async {
      await g.layer.save();
    });

    // 创建 Steps & Medias
    final stepsList = item['steps'] as List;
    for (var sItem in stepsList) {
      final step = GrenadeStep(
        title: sItem['title'] ?? "",
        description: sItem['description'],
        stepIndex: sItem['index'],
      );
      final mediasList = sItem['medias'] as List;
      final mediasToCreate = <StepMedia>[];
      for (var mItem in mediasList) {
        final fileName = mItem['path'];
        if (memoryImages.containsKey(fileName)) {
          final savePath = p.join(
              dataPath, "${DateTime.now().millisecondsSinceEpoch}_$fileName");
          await File(savePath).writeAsBytes(memoryImages[fileName]!);

          mediasToCreate
              .add(StepMedia(localPath: savePath, type: mItem['type']));
        }
      }
      await isar.writeTxn(() async {
        await isar.grenadeSteps.put(step);
        step.grenade.value = g;
        await step.grenade.save();
        g.steps.add(step);
        for (final media in mediasToCreate) {
          await isar.stepMedias.put(media);
          media.step.value = step;
          await media.step.save();
          step.medias.add(media);
        }
        await step.medias.save();
      });
    }
    await isar.writeTxn(() async {
      await g.steps.save();
    });

    return g; // 返回创建的道具
  }

  /// 另存为对话框，支持自定义文件名
  Future<void> _saveToFolderWithCustomName(
      BuildContext context, String sourcePath) async {
    // 生成默认文件名
    final defaultFileName =
        "cs2_tactics_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}";

    // 显示文件名输入对话框
    final fileNameController = TextEditingController(text: defaultFileName);
    final customFileName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("导出文件"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("请输入文件名："),
            const SizedBox(height: 16),
            TextField(
              controller: fileNameController,
              decoration: const InputDecoration(
                suffixText: ".cs2pkg",
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, fileNameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text("选择位置"),
          ),
        ],
      ),
    );

    if (customFileName == null || customFileName.isEmpty) return;
    if (!context.mounted) return;

    // 选择保存目录
    String? outputDirectory =
        await FilePicker.platform.getDirectoryPath(dialogTitle: "请选择保存位置");

    if (outputDirectory == null) return;

    try {
      final fileName = "$customFileName.cs2pkg";
      final destination = p.join(outputDirectory, fileName);

      final sourceFile = File(sourcePath);
      await sourceFile.copy(destination);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("文件已保存至:\n$destination"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("保存失败: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

class _LocalTagContext {
  final Map<String, GameMap> mapByName;
  final Map<String, Tag> localByUuid;
  final Map<String, Tag> localBySemantic;

  const _LocalTagContext({
    required this.mapByName,
    required this.localByUuid,
    required this.localBySemantic,
  });
}
