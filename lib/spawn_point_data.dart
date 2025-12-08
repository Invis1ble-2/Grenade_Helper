/// 出生点数据模型和内置数据

/// 单个出生点
class SpawnPoint {
  final int id; // 编号 1-5
  final double x; // X比例坐标 (0-1)
  final double y; // Y比例坐标 (0-1)

  const SpawnPoint(this.id, this.x, this.y);
}

/// 地图出生点配置
class MapSpawnConfig {
  final List<SpawnPoint> ctSpawns; // CT方出生点列表
  final List<SpawnPoint> tSpawns; // T方出生点列表

  const MapSpawnConfig({
    required this.ctSpawns,
    required this.tSpawns,
  });
}

/// 内置出生点数据
///
/// 使用 tools/spawn_picker.html 工具生成数据后粘贴到这里
/// 键名应与地图名称匹配（小写）
const Map<String, MapSpawnConfig> spawnPointData = {
  // 示例数据（请使用坐标拾取工具替换为实际数据）
  // 'mirage': MapSpawnConfig(
  //   ctSpawns: [SpawnPoint(1, 0.52, 0.31), SpawnPoint(2, 0.54, 0.33)],
  //   tSpawns: [SpawnPoint(1, 0.18, 0.72), SpawnPoint(2, 0.20, 0.74)],
  // ),
};
