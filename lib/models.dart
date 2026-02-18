import 'package:isar_community/isar.dart';

part 'models.g.dart';

// --- 1. 常量定义 ---

class GrenadeType {
  static const int smoke = 0;
  static const int flash = 1;
  static const int molotov = 2;
  static const int he = 3;
  static const int wallbang = 4;
}

class TeamType {
  static const int all = 0;
  static const int ct = 1;
  static const int t = 2;
  static const int onlyAll = 3;
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

  // 关联 MapLayer
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
  @Index()
  int? favoriteFolderId;
  bool isNewImport;
  DateTime createdAt;
  DateTime updatedAt;

  double xRatio;
  double yRatio;

  /// 作者名称
  String? author;

  /// 标记是否进行本地编辑
  bool hasLocalEdits;

  /// 标记道具是否为导入
  bool isImported;

  /// 唯一标识符，用于跨设备同步和去重
  @Index()
  String? uniqueId;

  /// 原始出处链接
  String? sourceUrl;

  /// 出处备注
  String? sourceNote;

  /// 爆点名称/位置描述
  String? description;

  double? impactXRatio;
  double? impactYRatio;
  String? impactAreaStrokes;

  /// 爆点分组ID（用于自定义分组筛选）
  int? impactGroupId;

  @Backlink(to: 'grenades')
  final layer = IsarLink<MapLayer>();

  final steps = IsarLinks<GrenadeStep>();

  Grenade({
    required this.title,
    required this.type,
    this.team = 0,
    this.isFavorite = false,
    this.favoriteFolderId,
    this.isNewImport = false,
    this.hasLocalEdits = false,
    this.isImported = false,
    required this.xRatio,
    required this.yRatio,
    this.uniqueId,
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
  int type;
  int sortOrder;

  // 反向链接到 GrenadeStep
  @Backlink(to: 'medias')
  final step = IsarLink<GrenadeStep>();

  StepMedia({
    required this.localPath,
    required this.type,
    this.sortOrder = 0,
  });
}

/// 导入历史记录
@collection
class ImportHistory {
  Id id = Isar.autoIncrement;

  String fileName;
  DateTime importedAt;
  int newCount;
  int updatedCount;
  int skippedCount;

  // 关联导入的道具
  final grenades = IsarLinks<Grenade>();

  ImportHistory({
    required this.fileName,
    required this.importedAt,
    this.newCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
  });
}

/// 爆点分组（用于在同一爆点下对投掷点进行自定义分组）
@collection
class ImpactGroup {
  Id id = Isar.autoIncrement;

  /// 分组名称
  @Index()
  String name;

  /// 道具类型（GrenadeType）
  int type;

  /// 关联的爆点坐标（用于限定分组范围）
  double impactXRatio;
  double impactYRatio;

  /// 关联的图层ID
  @Index()
  int layerId;

  /// 创建时间
  DateTime createdAt;

  ImpactGroup({
    required this.name,
    required this.type,
    required this.impactXRatio,
    required this.impactYRatio,
    required this.layerId,
    DateTime? created,
  }) : createdAt = created ?? DateTime.now();
}

/// 收藏夹
@collection
class FavoriteFolder {
  Id id = Isar.autoIncrement;

  /// 所属地图
  @Index()
  int mapId;

  /// 显示名称
  String name;

  /// 规范化名称（用于 mapId 维度下唯一校验）
  @Index()
  String nameKey;

  /// 排序权重
  int sortOrder;

  DateTime createdAt;
  DateTime updatedAt;

  FavoriteFolder({
    required this.mapId,
    required this.name,
    required this.nameKey,
    this.sortOrder = 0,
    DateTime? created,
    DateTime? updated,
  })  : createdAt = created ?? DateTime.now(),
        updatedAt = updated ?? DateTime.now();
}
