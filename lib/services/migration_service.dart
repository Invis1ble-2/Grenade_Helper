import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';
import '../models.dart';

/// 数据迁移服务
class MigrationService {
  final Isar isar;
  const MigrationService(this.isar);

  /// 为所有没有 uniqueId 的道具生成 UUID
  Future<int> migrateGrenadeUuids() async {
    // 查找所有 uniqueId 为空的道具
    final allGrenades = await isar.grenades.where().findAll();
    final grenadesNeedingUuid = allGrenades
        .where((g) => g.uniqueId == null || g.uniqueId!.isEmpty)
        .toList();

    if (grenadesNeedingUuid.isEmpty) return 0;

    const uuid = Uuid();
    await isar.writeTxn(() async {
      for (final g in grenadesNeedingUuid) {
        // 加载链接关系
        await g.layer.load();
        await g.steps.load();

        // 生成 UUID
        g.uniqueId = uuid.v4();

        // 保存道具
        await isar.grenades.put(g);

        // 重新保存链接关系（确保不丢失）
        await g.layer.save();
        await g.steps.save();
      }
    });

    return grenadesNeedingUuid.length;
  }
}
