import '../models.dart';

class BuiltinMapConfig {
  final String name;
  final String key;
  final List<String> floors;
  final List<String> floorNames;
  final bool isActiveDuty;

  const BuiltinMapConfig({
    required this.name,
    required this.key,
    required this.floors,
    required this.floorNames,
    required this.isActiveDuty,
  });

  String get backgroundPath => 'assets/backgrounds/${key}_bg.webp';
  String get legacyBackgroundPath => 'assets/backgrounds/${key}_bg.png';
  String get iconPath => 'assets/icons/${key}_icon.svg';
}

const List<BuiltinMapConfig> builtinMapsConfig = [
  BuiltinMapConfig(
    name: 'Mirage',
    key: 'mirage',
    floors: ['mirage.png'],
    floorNames: ['Default'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Inferno',
    key: 'inferno',
    floors: ['inferno.png'],
    floorNames: ['Default'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Dust 2',
    key: 'dust2',
    floors: ['dust2.png'],
    floorNames: ['Default'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Cache',
    key: 'cache',
    floors: ['cache.png'],
    floorNames: ['Default'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Ancient',
    key: 'ancient',
    floors: ['ancient.png'],
    floorNames: ['Default'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Anubis',
    key: 'anubis',
    floors: ['anubis.png'],
    floorNames: ['Default'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Nuke',
    key: 'nuke',
    floors: ['nuke_lower.png', 'nuke_upper.png'],
    floorNames: ['B Site (Lower)', 'A Site (Upper)'],
    isActiveDuty: true,
  ),
  BuiltinMapConfig(
    name: 'Overpass',
    key: 'overpass',
    floors: ['overpass.png'],
    floorNames: ['Default'],
    isActiveDuty: false,
  ),
  BuiltinMapConfig(
    name: 'Train',
    key: 'train',
    floors: ['train.png'],
    floorNames: ['Default'],
    isActiveDuty: false,
  ),
  BuiltinMapConfig(
    name: 'Vertigo',
    key: 'vertigo',
    floors: ['vertigo_lower.png', 'vertigo_upper.png'],
    floorNames: ['Level 50 (Lower)', 'Level 51 (Upper)'],
    isActiveDuty: false,
  ),
  BuiltinMapConfig(
    name: 'Cobblestone',
    key: 'cbble',
    floors: ['cbble.png'],
    floorNames: ['Default'],
    isActiveDuty: false,
  ),
  BuiltinMapConfig(
    name: 'Office',
    key: 'office',
    floors: ['office.png'],
    floorNames: ['Default'],
    isActiveDuty: false,
  ),
  BuiltinMapConfig(
    name: 'Italy',
    key: 'italy',
    floors: ['italy.png'],
    floorNames: ['Default'],
    isActiveDuty: false,
  ),
];

final Map<String, String> _legacyBuiltinAssetPathMap = {
  for (final config in builtinMapsConfig)
    config.legacyBackgroundPath: config.backgroundPath,
};

final Map<String, int> _builtinMapOrderByKey = {
  for (var i = 0; i < builtinMapsConfig.length; i++) builtinMapsConfig[i].key: i,
};

BuiltinMapConfig? findBuiltinMapConfig(GameMap map) {
  final normalizedIconPath = map.iconPath.replaceAll('\\', '/').toLowerCase();
  final normalizedBackgroundPath =
      map.backgroundPath.replaceAll('\\', '/').toLowerCase();

  for (final config in builtinMapsConfig) {
    if (normalizedIconPath == config.iconPath) return config;
    if (normalizedBackgroundPath == config.backgroundPath ||
        normalizedBackgroundPath == config.legacyBackgroundPath) {
      return config;
    }
  }
  return null;
}

int builtinMapSortOrder(GameMap map) {
  final config = findBuiltinMapConfig(map);
  if (config == null) return builtinMapsConfig.length;
  return _builtinMapOrderByKey[config.key] ?? builtinMapsConfig.length;
}

String normalizeLegacyBuiltinAssetPath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return trimmed;
  final normalized = trimmed.replaceAll('\\', '/').toLowerCase();
  return _legacyBuiltinAssetPathMap[normalized] ?? trimmed;
}
