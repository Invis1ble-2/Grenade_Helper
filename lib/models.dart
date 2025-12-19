import 'package:isar_community/isar.dart';

part 'models.g.dart';

// --- 1. 常量定义 ---

class GrenadeType {
  static const int smoke = 0;
  static const int flash = 1;
  static const int molotov = 2;
  static const int he = 3;
}

class TeamType {
  static const int all = 0; // 显示全部（不过滤）
  static const int ct = 1; // 仅警
  static const int t = 2; // 仅匪
  static const int onlyAll = 3; // 仅通用（双方都可用）
}

class MediaType {
  static const int image = 0;
  static const int video = 1;
}

// --- 2. 数据库实体定义 ---

@collection
class GameMap {
  Id id = Isar.autoIncrement;

  String name;
  String backgroundPath;
  String iconPath;

  // Isar 使用 IsarLinks 来管理一对多关系
  final layers = IsarLinks<MapLayer>();

  GameMap({
    required this.name,
    this.backgroundPath = "",
    this.iconPath = "",
  });
}

@collection
class MapLayer {
  Id id = Isar.autoIncrement;

  String name;
  String assetPath;
  int sortOrder;

  // 反向链接到 GameMap
  @Backlink(to: 'layers')
  final map = IsarLink<GameMap>();

  // 一对多: MapLayer -> Grenades
  final grenades = IsarLinks<Grenade>();

  MapLayer({
    required this.name,
    required this.assetPath,
    required this.sortOrder,
  });
}

@collection
class Grenade {
  Id id = Isar.autoIncrement;

  String title;
  int type; // GrenadeType
  int team; // TeamType
  bool isFavorite;
  bool isNewImport;
  DateTime createdAt;
  DateTime updatedAt;

  double xRatio;
  double yRatio;

  // 反向链接到 MapLayer
  @Backlink(to: 'grenades')
  final layer = IsarLink<MapLayer>();

  // 一对多: Grenade -> Steps
  final steps = IsarLinks<GrenadeStep>();

  Grenade({
    required this.title,
    required this.type,
    this.team = 0,
    this.isFavorite = false,
    this.isNewImport = false,
    required this.xRatio,
    required this.yRatio,
    DateTime? created,
    DateTime? updated,
  })  : createdAt = created ?? DateTime.now(),
        updatedAt = updated ?? DateTime.now();
}

@collection
class GrenadeStep {
  Id id = Isar.autoIncrement;

  String title;
  String description;
  int stepIndex;

  // 反向链接到 Grenade
  @Backlink(to: 'steps')
  final grenade = IsarLink<Grenade>();

  // 一对多: Step -> Medias
  final medias = IsarLinks<StepMedia>();

  GrenadeStep({
    this.title = "",
    required this.description,
    required this.stepIndex,
  });
}

@collection
class StepMedia {
  Id id = Isar.autoIncrement;

  String localPath;
  int type; // MediaType

  // 反向链接到 GrenadeStep
  @Backlink(to: 'medias')
  final step = IsarLink<GrenadeStep>();

  StepMedia({
    required this.localPath,
    required this.type,
  });
}
