import 'package:isar_community/isar.dart';

part 'tag.g.dart';

// 标签维度枚举值
class TagDimension {
  static const int role = 0; // 角色 (T/CT)
  static const int area = 1; // 区域
  static const int phase = 2; // 战术阶段
  static const int spawn = 3; // 出身位
  static const int purpose = 4; // 战术目的
  static const int custom = 99; // 个人自定义

  // 自定义名称覆盖映射
  static final Map<int, String> _customNames = {};

  // 默认名称
  static String _getDefaultName(int dimension) {
    switch (dimension) {
      case role:
        return '角色';
      case area:
        return '区域';
      case phase:
        return '阶段';
      case spawn:
        return '身位';
      case purpose:
        return '目的';
      case custom:
        return '自定义';
      default:
        return '未知';
    }
  }

  static String getName(int dimension) {
    return _customNames[dimension] ?? _getDefaultName(dimension);
  }

  static void setName(int dimension, String name) {
    if (name.trim().isEmpty) {
      _customNames.remove(dimension);
    } else {
      _customNames[dimension] = name.trim();
    }
  }

  static void loadFromMap(Map<int, String> names) {
    _customNames.clear();
    _customNames.addAll(names);
  }

  static Map<int, String> getCustomNames() => Map.from(_customNames);
}

// 标签数据模型
@collection
class Tag {
  Id id = Isar.autoIncrement;

  @Index()
  String tagUuid;

  @Index()
  String name;

  int colorValue;
  int dimension;

  // 自定义分组名称（可选，用于覆盖默认分组名）
  String? groupName;

  @Index()
  bool isSystem;

  int sortOrder;

  @Index()
  int mapId;

  Tag({
    this.tagUuid = '',
    required this.name,
    required this.colorValue,
    required this.dimension,
    this.groupName,
    this.isSystem = false,
    this.sortOrder = 0,
    required this.mapId,
  });
}
