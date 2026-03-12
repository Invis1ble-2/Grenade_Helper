import 'dart:ffi';
import 'dart:io';

import 'package:grenade_helper/data/builtin_area_region_presets.dart';
import 'package:grenade_helper/data/map_area_presets.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/services/tag_uuid_service.dart';
import 'package:isar_community/isar.dart';
import 'package:isar_community/src/native/isar_core.dart';

Future<void> main(List<String> args) async {
  final dataPath = args.isNotEmpty ? args.first : '';
  if (dataPath.trim().isEmpty) {
    stderr.writeln(
        '用法: dart run tool/diagnose_stale_system_tags.dart <data_path>');
    exitCode = 64;
    return;
  }

  final directory = Directory(dataPath);
  if (!directory.existsSync()) {
    stderr.writeln('数据目录不存在: $dataPath');
    exitCode = 66;
    return;
  }

  await initializeCoreBinary(
    libraries: {
      Abi.current(): _resolveIsarCoreLibraryPath(),
    },
  );

  final isar = await Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema,
      ImportHistorySchema,
      ImpactGroupSchema,
      FavoriteFolderSchema,
      TagSchema,
      GrenadeTagSchema,
      MapAreaSchema,
    ],
    directory: dataPath,
    inspector: false,
  );

  try {
    final maps = await isar.gameMaps.where().findAll();
    if (maps.isEmpty) {
      stdout.writeln('当前库没有地图数据。');
      return;
    }

    var foundAny = false;
    for (final map in maps) {
      final staleTags = await _findStaleSystemTagsForMap(isar, map);
      if (staleTags.isEmpty) continue;

      foundAny = true;
      stdout.writeln('地图: ${map.name} (id=${map.id})');
      for (final item in staleTags) {
        stdout.writeln(
          '  标签: ${item.tag.name} | id=${item.tag.id} | uuid=${item.tag.tagUuid} | '
          '维度=${TagDimension.getName(item.tag.dimension)} | '
          '道具引用=${item.grenadeTitles.length} | 区域引用=${item.areaRefs.length}',
        );

        if (item.grenadeTitles.isNotEmpty) {
          stdout.writeln('    道具: ${item.grenadeTitles.join(' / ')}');
        }
        if (item.areaRefs.isNotEmpty) {
          stdout.writeln('    区域: ${item.areaRefs.join(' / ')}');
        }
      }
    }

    if (!foundAny) {
      stdout.writeln('没有发现“废弃但仍被引用”的系统标签。');
    }
  } finally {
    await isar.close();
  }
}

Future<List<_StaleSystemTagUsage>> _findStaleSystemTagsForMap(
  Isar isar,
  GameMap map,
) async {
  final requiredDefs = _buildRequiredSystemTagDefs(map);
  final requiredKeys =
      requiredDefs.map((def) => _systemTagKey(def.dimension, def.name)).toSet();
  final requiredUuids = requiredDefs
      .map(
        (def) => _normalizeTagUuid(
          TagUuidService.buildSystemTagUuid(
            mapName: map.name,
            mapIconPath: map.iconPath,
            dimension: def.dimension,
            tagName: def.name,
          ),
        ),
      )
      .toSet();

  final existingTags = await isar.tags.filter().mapIdEqualTo(map.id).findAll();
  final staleSystemTags = existingTags.where((tag) {
    if (!tag.isSystem) return false;
    final key = _systemTagKey(tag.dimension, tag.name);
    final normalizedUuid = _normalizeTagUuid(tag.tagUuid);
    return !requiredKeys.contains(key) &&
        !requiredUuids.contains(normalizedUuid);
  }).toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  if (staleSystemTags.isEmpty) {
    return const <_StaleSystemTagUsage>[];
  }

  await map.layers.load();
  final layerNameById = <int, String>{
    for (final layer in map.layers) layer.id: layer.name,
  };

  final result = <_StaleSystemTagUsage>[];
  for (final tag in staleSystemTags) {
    final grenadeRelations =
        await isar.grenadeTags.filter().tagIdEqualTo(tag.id).findAll();
    final areas = await isar.mapAreas.filter().tagIdEqualTo(tag.id).findAll();
    if (grenadeRelations.isEmpty && areas.isEmpty) {
      continue;
    }

    final grenadeTitles = <String>[];
    for (final relation in grenadeRelations) {
      final grenade = await isar.grenades.get(relation.grenadeId);
      if (grenade == null) continue;
      grenadeTitles.add('${grenade.title}#${grenade.id}');
    }
    grenadeTitles.sort();

    final areaRefs = areas.map((area) {
      final layerName = area.layerId == null
          ? 'Default'
          : (layerNameById[area.layerId!] ?? '未知楼层');
      return '${area.name}@$layerName#${area.id}';
    }).toList()
      ..sort();

    result.add(
      _StaleSystemTagUsage(
        tag: tag,
        grenadeTitles: grenadeTitles,
        areaRefs: areaRefs,
      ),
    );
  }

  return result;
}

List<_SystemTagDef> _buildRequiredSystemTagDefs(GameMap map) {
  final result = <_SystemTagDef>[];
  final seenKeys = <String>{};

  void addDef({
    required int dimension,
    required String name,
    required int colorValue,
  }) {
    final key = _systemTagKey(dimension, name);
    if (!seenKeys.add(key)) return;
    result.add(
      _SystemTagDef(
        dimension: dimension,
        name: name,
        colorValue: colorValue,
      ),
    );
  }

  for (final entry in commonSystemTags.entries) {
    final color = dimensionColors[entry.key] ?? 0xFF607D8B;
    for (final name in entry.value) {
      addDef(
        dimension: entry.key,
        name: name,
        colorValue: color,
      );
    }
  }

  final areaNames = _resolveAreaPresetNames(map);
  final areaColor = dimensionColors[TagDimension.area] ?? 0xFF4CAF50;
  for (final name in areaNames) {
    addDef(
      dimension: TagDimension.area,
      name: name,
      colorValue: areaColor,
    );
  }

  final builtinAreaData = _resolveBuiltinAreaRegionPresets(map);
  for (final preset in builtinAreaData.values.expand((list) => list)) {
    addDef(
      dimension: TagDimension.area,
      name: preset.name,
      colorValue: areaColor,
    );
  }

  return result;
}

List<String> _resolveAreaPresetNames(GameMap map) {
  final lowerName = map.name.trim().toLowerCase();
  if (mapAreaPresets.containsKey(lowerName)) {
    return mapAreaPresets[lowerName]!;
  }

  final iconMatch = RegExp(
    r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
    caseSensitive: false,
  ).firstMatch(map.iconPath);
  if (iconMatch != null && iconMatch.groupCount >= 1) {
    final key = iconMatch.group(1)?.toLowerCase();
    if (key != null && mapAreaPresets.containsKey(key)) {
      return mapAreaPresets[key]!;
    }
  }

  final normalized = lowerName.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return mapAreaPresets[normalized] ?? const <String>[];
}

Map<String, List<BuiltinAreaPreset>> _resolveBuiltinAreaRegionPresets(
  GameMap map,
) {
  final lowerName = map.name.trim().toLowerCase();
  if (builtinAreaRegionPresets.containsKey(lowerName)) {
    return builtinAreaRegionPresets[lowerName]!;
  }

  final iconMatch = RegExp(
    r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
    caseSensitive: false,
  ).firstMatch(map.iconPath);
  if (iconMatch != null && iconMatch.groupCount >= 1) {
    final key = iconMatch.group(1)?.toLowerCase();
    if (key != null && builtinAreaRegionPresets.containsKey(key)) {
      return builtinAreaRegionPresets[key]!;
    }
  }

  final normalized = lowerName.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return builtinAreaRegionPresets[normalized] ??
      const <String, List<BuiltinAreaPreset>>{};
}

String _systemTagKey(int dimension, String name) {
  return '$dimension|${name.trim().toLowerCase()}';
}

String _normalizeTagUuid(String value) {
  return value.trim().toLowerCase();
}

String _resolveIsarCoreLibraryPath() {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('未找到 LOCALAPPDATA，无法定位 libisar.dll');
    }
    return '$localAppData\\Pub\\Cache\\hosted\\pub.dev\\'
        'isar_community_flutter_libs-3.3.0\\windows\\libisar.dll';
  }
  throw UnsupportedError('当前脚本仅为桌面 Windows 诊断场景准备');
}

class _SystemTagDef {
  final int dimension;
  final String name;
  final int colorValue;

  const _SystemTagDef({
    required this.dimension,
    required this.name,
    required this.colorValue,
  });
}

class _StaleSystemTagUsage {
  final Tag tag;
  final List<String> grenadeTitles;
  final List<String> areaRefs;

  const _StaleSystemTagUsage({
    required this.tag,
    required this.grenadeTitles,
    required this.areaRefs,
  });
}
