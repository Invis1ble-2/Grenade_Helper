import 'package:flutter/material.dart';

/// 节日主题基类
///
/// 所有节日主题（圣诞节、春节、情人节等）都应继承此类
abstract class SeasonalTheme {
  /// 主题唯一标识符
  String get id;

  /// 显示名称
  String get name;

  /// 表情图标
  String get emoji;

  /// 主题开始日期（月/日）
  int get startMonth;
  int get startDay;

  /// 主题结束日期（月/日）
  int get endMonth;
  int get endDay;

  /// 获取浅色主题配色
  ColorScheme getLightColorScheme();

  /// 获取深色主题配色
  ColorScheme getDarkColorScheme();

  /// 构建装饰组件（如雪花、烟花等）
  /// 返回 null 表示无装饰
  Widget? buildDecoration(BuildContext context);

  /// 构建 AppBar 装饰（如小徽章）
  Widget? buildAppBarDecoration(BuildContext context) => null;

  /// 检查指定日期是否在主题激活期间
  bool isActiveOn(DateTime date) {
    final year = date.year;

    // 处理跨年情况（如圣诞节 12月20日 - 1月2日）
    if (endMonth < startMonth) {
      // 跨年：检查是否在开始月之后（去年底） 或 结束月之前（今年初）
      final startDate = DateTime(year, startMonth, startDay);
      final endDateThisYear = DateTime(year, endMonth, endDay, 23, 59, 59);

      // 如果当前日期在开始日期之后（年底）或在结束日期之前（年初）
      return date.isAfter(startDate.subtract(const Duration(days: 1))) ||
          date.isBefore(endDateThisYear.add(const Duration(days: 1)));
    } else {
      // 同年
      final startDate = DateTime(year, startMonth, startDay);
      final endDate = DateTime(year, endMonth, endDay, 23, 59, 59);

      return date.isAfter(startDate.subtract(const Duration(days: 1))) &&
          date.isBefore(endDate.add(const Duration(days: 1)));
    }
  }
}

/// 节日主题管理器
class SeasonalThemeManager {
  SeasonalThemeManager._();

  /// 所有已注册的节日主题
  static final List<SeasonalTheme> _themes = [];

  /// 注册主题
  static void registerTheme(SeasonalTheme theme) {
    if (!_themes.any((t) => t.id == theme.id)) {
      _themes.add(theme);
    }
  }

  /// 获取所有已注册的主题
  static List<SeasonalTheme> get themes => List.unmodifiable(_themes);

  /// 获取当前激活的主题（如果有）
  static SeasonalTheme? getActiveTheme([DateTime? date]) {
    final now = date ?? DateTime.now();
    for (final theme in _themes) {
      if (theme.isActiveOn(now)) {
        return theme;
      }
    }
    return null;
  }

  /// 根据 ID 获取主题
  static SeasonalTheme? getThemeById(String id) {
    for (final theme in _themes) {
      if (theme.id == id) {
        return theme;
      }
    }
    return null;
  }

  /// 将节日配色应用到基础主题
  static ThemeData applySeasonalColors(
    ThemeData baseTheme,
    SeasonalTheme seasonalTheme,
    bool isDark,
  ) {
    final colorScheme = isDark
        ? seasonalTheme.getDarkColorScheme()
        : seasonalTheme.getLightColorScheme();

    return baseTheme.copyWith(
      colorScheme: colorScheme,
      primaryColor: colorScheme.primary,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor:
            isDark ? colorScheme.surface : colorScheme.primaryContainer,
        foregroundColor:
            isDark ? colorScheme.onSurface : colorScheme.onPrimaryContainer,
      ),
    );
  }
}
