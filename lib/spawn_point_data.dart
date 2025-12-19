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
  'mirage': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.2842, 0.7247),
      SpawnPoint(2, 0.2808, 0.6816),
      SpawnPoint(3, 0.2873, 0.7022),
      SpawnPoint(4, 0.2989, 0.6797),
      SpawnPoint(5, 0.2995, 0.725)
    ],
    tSpawns: [
      SpawnPoint(1, 0.8821, 0.4047),
      SpawnPoint(2, 0.8809, 0.3127),
      SpawnPoint(3, 0.8659, 0.3263),
      SpawnPoint(4, 0.8662, 0.3539),
      SpawnPoint(5, 0.8659, 0.3805),
      SpawnPoint(6, 0.8659, 0.4039),
      SpawnPoint(7, 0.8512, 0.3805),
      SpawnPoint(8, 0.8507, 0.3639),
      SpawnPoint(9, 0.8504, 0.3387),
      SpawnPoint(10, 0.8507, 0.3166)
    ],
  ),
  'dust 2': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.5837, 0.1725),
      SpawnPoint(2, 0.5777, 0.1965),
      SpawnPoint(3, 0.6082, 0.167),
      SpawnPoint(4, 0.6318, 0.174),
      SpawnPoint(5, 0.6378, 0.1955)
    ],
    tSpawns: [
      SpawnPoint(1, 0.3686, 0.8928),
      SpawnPoint(2, 0.352, 0.8772),
      SpawnPoint(3, 0.3831, 0.9094),
      SpawnPoint(4, 0.4036, 0.9089),
      SpawnPoint(5, 0.4175, 0.8867),
      SpawnPoint(6, 0.2992, 0.8983),
      SpawnPoint(7, 0.2919, 0.8728),
      SpawnPoint(8, 0.3114, 0.9172),
      SpawnPoint(9, 0.3297, 0.8972),
      SpawnPoint(10, 0.3286, 0.8739),
      SpawnPoint(11, 0.4425, 0.8883),
      SpawnPoint(12, 0.4319, 0.87),
      SpawnPoint(13, 0.4547, 0.9072),
      SpawnPoint(14, 0.4731, 0.8961),
      SpawnPoint(15, 0.4736, 0.8761)
    ],
  ),
  'inferno': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.9139, 0.3579),
      SpawnPoint(2, 0.9054, 0.3336),
      SpawnPoint(3, 0.9018, 0.3793),
      SpawnPoint(4, 0.8761, 0.3829),
      SpawnPoint(5, 0.8739, 0.3564),
      SpawnPoint(6, 0.8904, 0.3479)
    ],
    tSpawns: [
      SpawnPoint(1, 0.097, 0.6823),
      SpawnPoint(2, 0.1166, 0.6814),
      SpawnPoint(3, 0.0807, 0.6823),
      SpawnPoint(4, 0.0784, 0.7005),
      SpawnPoint(5, 0.0807, 0.7155)
    ],
  ),
  'anubis': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.4438, 0.214),
      SpawnPoint(2, 0.4293, 0.2055),
      SpawnPoint(3, 0.4153, 0.214),
      SpawnPoint(4, 0.4042, 0.2255),
      SpawnPoint(5, 0.4512, 0.2275),
    ],
    tSpawns: [
      SpawnPoint(1, 0.4502, 0.9405),
      SpawnPoint(2, 0.4773, 0.897),
      SpawnPoint(3, 0.4938, 0.896),
      SpawnPoint(4, 0.4542, 0.9175),
      SpawnPoint(5, 0.4637, 0.906),
      SpawnPoint(6, 0.4738, 0.9195),
      SpawnPoint(7, 0.4983, 0.9095),
      SpawnPoint(8, 0.5012, 0.9265),
      SpawnPoint(9, 0.4452, 0.9259),
      SpawnPoint(10, 0.4661, 0.93),
      SpawnPoint(11, 0.4866, 0.9336),
    ],
  ),
  'ancient': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.5366, 0.0956),
      SpawnPoint(2, 0.5191, 0.0894),
      SpawnPoint(3, 0.5003, 0.0894),
      SpawnPoint(4, 0.4797, 0.0912),
      SpawnPoint(5, 0.4684, 0.1031),
    ],
    tSpawns: [
      SpawnPoint(1, 0.5091, 0.8788),
      SpawnPoint(2, 0.4816, 0.8781),
      SpawnPoint(3, 0.4553, 0.8775),
      SpawnPoint(4, 0.4972, 0.8575),
      SpawnPoint(5, 0.4716, 0.855),
    ],
  ),
  'nuke': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.8375, 0.4456),
      SpawnPoint(2, 0.8442, 0.4606),
      SpawnPoint(3, 0.8364, 0.4728),
      SpawnPoint(4, 0.8531, 0.4467),
      SpawnPoint(5, 0.8531, 0.4733),
    ],
    tSpawns: [
      SpawnPoint(1, 0.2286, 0.5456),
      SpawnPoint(2, 0.2114, 0.5361),
      SpawnPoint(3, 0.2103, 0.5544),
      SpawnPoint(4, 0.2184, 0.5318),
      SpawnPoint(5, 0.2275, 0.5615),
      SpawnPoint(6, 0.2178, 0.545),
      SpawnPoint(7, 0.2204, 0.5529),
      SpawnPoint(8, 0.2287, 0.5535),
    ],
  ),
  'overpass': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.496, 0.1973),
      SpawnPoint(2, 0.4844, 0.1935),
      SpawnPoint(3, 0.4729, 0.1888),
      SpawnPoint(4, 0.4921, 0.1835),
      SpawnPoint(5, 0.4798, 0.1808)
    ],
    tSpawns: [
      SpawnPoint(1, 0.6548, 0.9373),
      SpawnPoint(2, 0.6325, 0.9173),
      SpawnPoint(3, 0.6679, 0.9485),
      SpawnPoint(4, 0.6217, 0.9277),
      SpawnPoint(5, 0.6206, 0.9135),
      SpawnPoint(6, 0.6575, 0.9535),
      SpawnPoint(7, 0.6406, 0.9427),
      SpawnPoint(8, 0.644, 0.9558),
      SpawnPoint(9, 0.6444, 0.9242),
      SpawnPoint(10, 0.6279, 0.9377),
      SpawnPoint(11, 0.6344, 0.9277)
    ],
  ),
  'vertigo': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.5648, 0.1935),
      SpawnPoint(2, 0.5503, 0.2035),
      SpawnPoint(3, 0.4828, 0.2225),
      SpawnPoint(4, 0.4953, 0.1985),
      SpawnPoint(5, 0.5162, 0.1985)
    ],
    tSpawns: [
      SpawnPoint(1, 0.4308, 0.7035),
      SpawnPoint(2, 0.4078, 0.77),
      SpawnPoint(3, 0.4233, 0.7615),
      SpawnPoint(4, 0.4243, 0.7405),
      SpawnPoint(5, 0.4158, 0.721)
    ],
  ),
  'train': MapSpawnConfig(
    ctSpawns: [
      SpawnPoint(1, 0.8835, 0.792),
      SpawnPoint(2, 0.9265, 0.791),
      SpawnPoint(3, 0.9065, 0.825),
      SpawnPoint(4, 0.9415, 0.824),
      SpawnPoint(5, 0.9585, 0.856),
      SpawnPoint(6, 0.9225, 0.855),
      SpawnPoint(7, 0.8735, 0.851),
      SpawnPoint(8, 0.9045, 0.777),
    ],
    tSpawns: [
      SpawnPoint(1, 0.0635, 0.171),
      SpawnPoint(2, 0.0975, 0.168),
      SpawnPoint(3, 0.0955, 0.144),
      SpawnPoint(4, 0.0655, 0.145),
      SpawnPoint(5, 0.0855, 0.184),
      SpawnPoint(6, 0.1165, 0.195),
    ],
  ),
};
