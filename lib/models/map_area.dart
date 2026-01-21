import 'package:isar_community/isar.dart';

part 'map_area.g.dart';

/// 地图自定义区域模型
@collection
class MapArea {
  Id id = Isar.autoIncrement;
  
  @Index()
  String name;
  
  int colorValue;
  
  /// 存储手绘笔画的JSON字符串
  String strokes;
  
  @Index()
  int mapId;
  
  /// 关联的楼层ID（可选，null表示所有楼层）
  int? layerId;
  
  /// 自动创建的标签ID
  int tagId;
  
  DateTime createdAt;

  MapArea({
    required this.name,
    required this.colorValue,
    required this.strokes,
    required this.mapId,
    this.layerId,
    required this.tagId,
    required this.createdAt,
  });
}
