import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:isar_community/isar.dart';
import 'models.dart';
import 'services/seasonal_theme_service.dart';

// 全局 Isar 数据库
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError());

// 主题模式 Provider (0=跟随系统, 1=浅色, 2=深色)
final themeModeProvider = StateProvider<int>((ref) => 2); // 默认深色

// 节日主题开关 Provider (用户是否启用节日主题)
final seasonalThemeEnabledProvider = StateProvider<bool>((ref) => true); // 默认开启

// 当前激活的节日主题 Provider
final activeSeasonalThemeProvider = Provider<SeasonalTheme?>((ref) {
  final enabled = ref.watch(seasonalThemeEnabledProvider);
  if (!enabled) return null;
  return SeasonalThemeManager.getActiveTheme();
});

/// 将 int 转换为 Flutter ThemeMode
ThemeMode intToThemeMode(int value) {
  switch (value) {
    case 1:
      return ThemeMode.light;
    case 2:
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

// --- 筛选状态 ---
final teamFilterProvider =
    StateProvider.autoDispose<int>((ref) => TeamType.all);
final onlyFavoritesProvider = StateProvider.autoDispose<bool>((ref) => false);
final typeFilterProvider = StateProvider.autoDispose<Set<int>>((ref) => <int>{
      GrenadeType.smoke,
      GrenadeType.flash,
      GrenadeType.molotov,
      GrenadeType.he,
      GrenadeType.wallbang
    });

// 出生点显示开关（默认关闭）
final showSpawnPointsProvider = StateProvider.autoDispose<bool>((ref) => false);

// ==================== Isar 数据流 ====================

// 层级 1: 原始数据源 (Raw Data)
// 从 Isar 数据库取当前楼层的所有数据
final _rawLayerGrenadesProvider =
    StreamProvider.autoDispose.family<List<Grenade>, int>((ref, layerId) {
  final isar = ref.watch(isarProvider);
  // 监听该楼层的所有 Grenade 变化
  return isar.grenades
      .filter()
      .layer((q) => q.idEqualTo(layerId))
      .watch(fireImmediately: true);
});

// 层级 2: 逻辑过滤器 (Logic Filter)
final filteredGrenadesProvider =
    Provider.autoDispose.family<AsyncValue<List<Grenade>>, int>((ref, layerId) {
  // 1. 监听原始数据流
  final rawAsync = ref.watch(_rawLayerGrenadesProvider(layerId));

  // 2. 监听筛选器状态
  final teamFilter = ref.watch(teamFilterProvider);
  final onlyFav = ref.watch(onlyFavoritesProvider);
  final selectedTypes = ref.watch(typeFilterProvider);

  // 3. 使用 whenData 进行安全的内存过滤
  return rawAsync.whenData((allGrenades) {
    return allGrenades.where((g) {
      // A. 类型筛选
      if (!selectedTypes.contains(g.type)) return false;

      // B. 阵营筛选
      if (teamFilter == TeamType.onlyAll && g.team != TeamType.all)
        return false;
      if (teamFilter == TeamType.ct && g.team != TeamType.ct) return false;
      if (teamFilter == TeamType.t && g.team != TeamType.t) return false;

      // C. 收藏筛选
      if (onlyFav && !g.isFavorite) return false;

      return true;
    }).toList();
  });
});
