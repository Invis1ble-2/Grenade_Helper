import 'package:flutter/material.dart';
import '../services/seasonal_theme_service.dart';
import '../widgets/snowfall_effect.dart';

/// 圣诞节主题
///
/// 激活期间：12月20日 - 1月2日
/// 配色：红色、绿色、金色
class ChristmasTheme extends SeasonalTheme {
  @override
  String get id => 'christmas';

  @override
  String get name => '圣诞节';

  @override
  String get emoji => '🎄';

  @override
  int get startMonth => 12;

  @override
  int get startDay => 20;

  @override
  int get endMonth => 1;

  @override
  int get endDay => 2;

  // 圣诞配色常量
  static const christmasRed = Color(0xFFC41E3A);
  static const christmasGreen = Color(0xFF228B22);
  static const christmasGold = Color(0xFFFFD700);
  static const christmasDarkGreen = Color(0xFF0D1F0D);
  static const christmasLightBg = Color(0xFFFFF8F0);

  @override
  ColorScheme getLightColorScheme() {
    return ColorScheme.light(
      primary: christmasRed,
      secondary: christmasGreen,
      tertiary: christmasGold,
      surface: christmasLightBg,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      primaryContainer: const Color(0xFFFFE4E1), // 浅红色
      onPrimaryContainer: christmasRed,
      secondaryContainer: const Color(0xFFE8F5E9), // 浅绿色
      onSecondaryContainer: christmasGreen,
    );
  }

  @override
  ColorScheme getDarkColorScheme() {
    return ColorScheme.dark(
      primary: christmasRed,
      secondary: christmasGreen,
      tertiary: christmasGold,
      surface: christmasDarkGreen,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      primaryContainer: const Color(0xFF5C1018), // 深红色
      onPrimaryContainer: const Color(0xFFFFDAD6),
      secondaryContainer: const Color(0xFF1B3D1B), // 深绿色
      onSecondaryContainer: const Color(0xFFB8E6B8),
    );
  }

  @override
  Widget? buildDecoration(BuildContext context) {
    return const SnowfallEffect(
      snowflakeCount: 25,
      child: SizedBox.shrink(),
    );
  }

  @override
  Widget? buildAppBarDecoration(BuildContext context) {
    return const ChristmasBadge(size: 28);
  }
}

/// 初始化并注册所有节日主题
void initializeSeasonalThemes() {
  SeasonalThemeManager.registerTheme(ChristmasTheme());
  // 未来可以在这里注册更多主题：
  // SeasonalThemeManager.registerTheme(SpringFestivalTheme());
  // SeasonalThemeManager.registerTheme(ValentineTheme());
}
