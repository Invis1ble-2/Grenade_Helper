import 'package:isar_community/isar.dart';

part 'grenade_tag.g.dart';

/// 道具与标签的关联表
@collection
class GrenadeTag {
  Id id = Isar.autoIncrement;
  
  @Index()
  int grenadeId;
  
  @Index()
  int tagId;

  GrenadeTag({
    required this.grenadeId,
    required this.tagId,
  });
}
