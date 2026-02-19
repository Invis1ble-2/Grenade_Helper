import 'package:uuid/uuid.dart';

/// 标签 UUID 规则：
/// - 系统标签：确定性 UUID（跨设备一致）
/// - 非系统标签：随机 UUID
class TagUuidService {
  static const Uuid _uuid = Uuid();

  // 固定命名空间，保证同一输入生成同一 UUID。
  static const String _systemTagNamespace =
      '4f5b6f2c-2d6d-4cb0-8f4a-8b7a76f5a5b1';

  static String newRandomUuid() => _uuid.v4();

  static String buildSystemTagUuid({
    required String mapName,
    String? mapIconPath,
    required int dimension,
    required String tagName,
  }) {
    final mapKey = _resolveMapKey(mapName: mapName, mapIconPath: mapIconPath);
    final normalizedTagName = _normalize(tagName);
    final seed =
        'grenade_helper.system_tag|$mapKey|$dimension|$normalizedTagName';
    return _uuid.v5(_systemTagNamespace, seed);
  }

  static String _resolveMapKey({
    required String mapName,
    String? mapIconPath,
  }) {
    final iconPath = mapIconPath ?? '';
    final match = RegExp(
      r'assets[\\/]+icons[\\/]+(.+?)_icon\.svg$',
      caseSensitive: false,
    ).firstMatch(iconPath);
    if (match != null && match.groupCount >= 1) {
      final key = _normalize(match.group(1) ?? '');
      if (key.isNotEmpty) return key;
    }
    return _normalize(mapName);
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
