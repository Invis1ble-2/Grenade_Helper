import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

/// 快捷键配置模型
class HotkeyConfig {
  final LogicalKeyboardKey key;
  final Set<LogicalKeyboardKey> modifiers;

  HotkeyConfig({required this.key, this.modifiers = const {}});

  /// 转换为可读字符串，如 "Alt + G"
  String toDisplayString() {
    final parts = <String>[];
    if (modifiers.contains(LogicalKeyboardKey.control) ||
        modifiers.contains(LogicalKeyboardKey.controlLeft) ||
        modifiers.contains(LogicalKeyboardKey.controlRight)) {
      parts.add('Ctrl');
    }
    if (modifiers.contains(LogicalKeyboardKey.alt) ||
        modifiers.contains(LogicalKeyboardKey.altLeft) ||
        modifiers.contains(LogicalKeyboardKey.altRight)) {
      parts.add('Alt');
    }
    if (modifiers.contains(LogicalKeyboardKey.shift) ||
        modifiers.contains(LogicalKeyboardKey.shiftLeft) ||
        modifiers.contains(LogicalKeyboardKey.shiftRight)) {
      parts.add('Shift');
    }
    parts.add(_getKeyLabel(key));
    return parts.join(' + ');
  }

  String _getKeyLabel(LogicalKeyboardKey key) {
    // 方向键
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    // 功能键
    if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
    if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.bracketLeft) return '[';
    if (key == LogicalKeyboardKey.bracketRight) return ']';
    // 数字键
    if (key == LogicalKeyboardKey.digit1) return '1';
    if (key == LogicalKeyboardKey.digit2) return '2';
    if (key == LogicalKeyboardKey.digit3) return '3';
    if (key == LogicalKeyboardKey.digit4) return '4';
    // 符号键
    if (key == LogicalKeyboardKey.equal) return '=';
    if (key == LogicalKeyboardKey.minus) return '-';
    // 其他
    return key.keyLabel.isNotEmpty
        ? key.keyLabel.toUpperCase()
        : key.debugName ?? 'Unknown';
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'keyId': key.keyId,
        'modifierIds': modifiers.map((m) => m.keyId).toList(),
      };

  /// 从 JSON 反序列化
  factory HotkeyConfig.fromJson(Map<String, dynamic> json) {
    return HotkeyConfig(
      key: LogicalKeyboardKey.findKeyByKeyId(json['keyId'] as int) ??
          LogicalKeyboardKey.keyG,
      modifiers: (json['modifierIds'] as List<dynamic>)
          .map((id) => LogicalKeyboardKey.findKeyByKeyId(id as int))
          .whereType<LogicalKeyboardKey>()
          .toSet(),
    );
  }
}

/// 快捷键动作类型
enum HotkeyAction {
  toggleOverlay, // 显示/隐藏悬浮窗
  navigateUp, // 向上导航点位
  navigateDown, // 向下导航点位
  navigateLeft, // 向左导航点位
  navigateRight, // 向右导航点位
  prevGrenade, // 上一个道具
  nextGrenade, // 下一个道具
  prevStep, // 上一个步骤
  nextStep, // 下一个步骤
  toggleSmoke, // 切换烟雾弹过滤
  toggleFlash, // 切换闪光弹过滤
  toggleMolotov, // 切换燃烧弹过滤
  toggleHE, // 切换手雷过滤
  toggleWallbang, // 切换穿点过滤
  hideOverlay, // 隐藏悬浮窗
  togglePlayPause, // 播放/暂停视频
  increaseNavSpeed, // 增加导航速度
  decreaseNavSpeed, // 减少导航速度
  scrollUp, // 向上滚动
  scrollDown, // 向下滚动
}

/// 设置服务 - 管理用户设置和快捷键配置
/// 桌面端使用 JSON 文件存储，移动端使用 SharedPreferences
class SettingsService {
  // 设置项键名
  static const String _keyHotkeys = 'desktop_hotkeys';
  static const String _keyOverlayOpacity = 'overlay_opacity';
  static const String _keyOverlaySize = 'overlay_size';
  static const String _keyCloseToTray = 'close_to_tray';
  static const String _keyOverlayX = 'overlay_x';
  static const String _keyOverlayY = 'overlay_y';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyMarkerMoveMode = 'marker_move_mode';
  static const String _keyJoystickOpacity = 'joystick_opacity';
  static const String _keyJoystickSpeed = 'joystick_speed';
  static const String _keyOverlayNavSpeed = 'overlay_nav_speed';
  static const String _keyDataPath = 'custom_data_path';
  static const String _keySeasonalThemeEnabled = 'seasonal_theme_enabled';
  static const String _keyLaunchCount = 'app_launch_count';
  static const String _keyDonationDialogShown = 'donation_dialog_shown';

  // 移动端使用 SharedPreferences
  SharedPreferences? _prefs;

  // 桌面端使用内存缓存 + 文件存储
  Map<String, dynamic> _cache = {};
  File? _settingsFile;

  /// 检查是否是桌面平台
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 初始化
  Future<void> init() async {
    if (isDesktop) {
      // 桌面端：使用 JSON 文件存储
      final appSupport = await getApplicationSupportDirectory();
      _settingsFile = File(path.join(appSupport.path, 'settings.json'));
      await _loadFromFile();
      // 尝试从 SharedPreferences 迁移旧设置
      await _migrateFromSharedPreferences();
    } else {
      // 移动端：使用 SharedPreferences
      _prefs = await SharedPreferences.getInstance();
    }
  }

  /// 从文件加载设置（桌面端）
  Future<void> _loadFromFile() async {
    if (_settingsFile == null) return;
    try {
      if (await _settingsFile!.exists()) {
        final content = await _settingsFile!.readAsString();
        if (content.isNotEmpty) {
          _cache = jsonDecode(content) as Map<String, dynamic>;
          print('[Settings] Loaded ${_cache.length} settings from file');
        }
      }
    } catch (e) {
      print('[Settings] Error loading settings from file: $e');
      _cache = {};
    }
  }

  /// 保存设置到文件（桌面端）
  /// 精确更新指定的键值，不会用旧缓存覆盖其他设置
  Future<void> _saveValue(String key, dynamic value) async {
    if (_settingsFile == null) return;
    try {
      // 先读取文件中的最新内容
      Map<String, dynamic> fileData = {};
      if (await _settingsFile!.exists()) {
        final content = await _settingsFile!.readAsString();
        if (content.isNotEmpty) {
          try {
            fileData = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {
            // 文件内容无效，使用空 map
          }
        }
      }

      // 只更新指定的键
      fileData[key] = value;

      // 写入更新后的数据
      final output = const JsonEncoder.withIndent('  ').convert(fileData);
      await _settingsFile!.writeAsString(output, flush: true);

      // 同步更新本地缓存为文件最新内容
      _cache = fileData;
    } catch (e) {
      print('[Settings] Error saving value to file: $e');
    }
  }

  /// 保存多个设置到文件（桌面端）
  /// 用于同时更新多个键值
  Future<void> _saveValues(Map<String, dynamic> values) async {
    if (_settingsFile == null) return;
    try {
      // 先读取文件中的最新内容
      Map<String, dynamic> fileData = {};
      if (await _settingsFile!.exists()) {
        final content = await _settingsFile!.readAsString();
        if (content.isNotEmpty) {
          try {
            fileData = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {}
        }
      }

      // 更新指定的键
      for (final entry in values.entries) {
        fileData[entry.key] = entry.value;
      }

      // 写入更新后的数据
      final output = const JsonEncoder.withIndent('  ').convert(fileData);
      await _settingsFile!.writeAsString(output, flush: true);

      // 同步更新本地缓存
      _cache = fileData;
    } catch (e) {
      print('[Settings] Error saving values to file: $e');
    }
  }

  /// 从 SharedPreferences 迁移旧设置到文件（仅首次迁移）
  Future<void> _migrateFromSharedPreferences() async {
    // 如果已有设置，跳过迁移
    if (_cache.isNotEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      bool migrated = false;

      // 迁移所有设置项
      if (prefs.containsKey(_keyHotkeys)) {
        _cache[_keyHotkeys] = prefs.getString(_keyHotkeys);
        migrated = true;
      }
      if (prefs.containsKey(_keyOverlayOpacity)) {
        _cache[_keyOverlayOpacity] = prefs.getDouble(_keyOverlayOpacity);
        migrated = true;
      }
      if (prefs.containsKey(_keyOverlaySize)) {
        _cache[_keyOverlaySize] = prefs.getInt(_keyOverlaySize);
        migrated = true;
      }
      if (prefs.containsKey(_keyCloseToTray)) {
        _cache[_keyCloseToTray] = prefs.getBool(_keyCloseToTray);
        migrated = true;
      }
      if (prefs.containsKey(_keyOverlayX)) {
        _cache[_keyOverlayX] = prefs.getDouble(_keyOverlayX);
        migrated = true;
      }
      if (prefs.containsKey(_keyOverlayY)) {
        _cache[_keyOverlayY] = prefs.getDouble(_keyOverlayY);
        migrated = true;
      }
      if (prefs.containsKey(_keyThemeMode)) {
        _cache[_keyThemeMode] = prefs.getInt(_keyThemeMode);
        migrated = true;
      }
      if (prefs.containsKey(_keySeasonalThemeEnabled)) {
        _cache[_keySeasonalThemeEnabled] =
            prefs.getBool(_keySeasonalThemeEnabled);
        migrated = true;
      }
      if (prefs.containsKey(_keyOverlayNavSpeed)) {
        _cache[_keyOverlayNavSpeed] = prefs.getInt(_keyOverlayNavSpeed);
        migrated = true;
      }
      if (prefs.containsKey(_keyLaunchCount)) {
        _cache[_keyLaunchCount] = prefs.getInt(_keyLaunchCount);
        migrated = true;
      }
      if (prefs.containsKey(_keyDonationDialogShown)) {
        _cache[_keyDonationDialogShown] =
            prefs.getBool(_keyDonationDialogShown);
        migrated = true;
      }

      if (migrated) {
        await _saveValues(_cache);
        print('[Settings] Migrated settings from SharedPreferences to file');
      }
    } catch (e) {
      print('[Settings] Error migrating from SharedPreferences: $e');
    }
  }

  /// 重新加载设置（用于多窗口间同步）
  Future<void> reload() async {
    if (isDesktop) {
      await _loadFromFile();
    } else {
      await _prefs?.reload();
    }
  }

  // ==================== 快捷键设置 ====================

  /// 获取所有快捷键配置
  Map<HotkeyAction, HotkeyConfig> getHotkeys() {
    final defaults = _getDefaultHotkeys();
    String? stored;

    if (isDesktop) {
      stored = _cache[_keyHotkeys] as String?;
    } else {
      stored = _prefs?.getString(_keyHotkeys);
    }

    if (stored == null) return defaults;

    try {
      final Map<String, dynamic> json = jsonDecode(stored);
      final result = <HotkeyAction, HotkeyConfig>{};
      for (final action in HotkeyAction.values) {
        final actionKey = action.name;
        if (json.containsKey(actionKey)) {
          result[action] = HotkeyConfig.fromJson(json[actionKey]);
        } else {
          result[action] = defaults[action]!;
        }
      }
      return result;
    } catch (e) {
      return defaults;
    }
  }

  /// 保存快捷键配置
  Future<void> saveHotkey(HotkeyAction action, HotkeyConfig config) async {
    final hotkeys = getHotkeys();
    hotkeys[action] = config;

    final json = <String, dynamic>{};
    for (final entry in hotkeys.entries) {
      json[entry.key.name] = entry.value.toJson();
    }
    final encoded = jsonEncode(json);

    if (isDesktop) {
      _cache[_keyHotkeys] = encoded;
      await _saveValue(_keyHotkeys, encoded);
    } else {
      await _prefs?.setString(_keyHotkeys, encoded);
    }
  }

  /// 重置所有快捷键为默认值
  Future<void> resetHotkeys() async {
    if (isDesktop) {
      _cache.remove(_keyHotkeys);
      await _saveValue(_keyHotkeys, null);
    } else {
      await _prefs?.remove(_keyHotkeys);
    }
  }

  /// 默认快捷键配置
  Map<HotkeyAction, HotkeyConfig> _getDefaultHotkeys() {
    return {
      HotkeyAction.toggleOverlay: HotkeyConfig(
        key: LogicalKeyboardKey.keyG,
        modifiers: {LogicalKeyboardKey.alt},
      ),
      HotkeyAction.navigateUp: HotkeyConfig(key: LogicalKeyboardKey.arrowUp),
      HotkeyAction.navigateDown:
          HotkeyConfig(key: LogicalKeyboardKey.arrowDown),
      HotkeyAction.navigateLeft:
          HotkeyConfig(key: LogicalKeyboardKey.arrowLeft),
      HotkeyAction.navigateRight:
          HotkeyConfig(key: LogicalKeyboardKey.arrowRight),
      HotkeyAction.prevGrenade: HotkeyConfig(key: LogicalKeyboardKey.pageUp),
      HotkeyAction.nextGrenade: HotkeyConfig(key: LogicalKeyboardKey.pageDown),
      HotkeyAction.prevStep: HotkeyConfig(key: LogicalKeyboardKey.bracketLeft),
      HotkeyAction.nextStep: HotkeyConfig(key: LogicalKeyboardKey.bracketRight),
      HotkeyAction.toggleSmoke: HotkeyConfig(
        key: LogicalKeyboardKey.digit7,
      ),
      HotkeyAction.toggleFlash: HotkeyConfig(
        key: LogicalKeyboardKey.digit8,
      ),
      HotkeyAction.toggleMolotov: HotkeyConfig(
        key: LogicalKeyboardKey.digit9,
      ),
      HotkeyAction.toggleHE: HotkeyConfig(
        key: LogicalKeyboardKey.digit0,
      ),
      HotkeyAction.toggleWallbang: HotkeyConfig(
        key: LogicalKeyboardKey.digit0,
        modifiers: {LogicalKeyboardKey.alt},
      ),
      HotkeyAction.hideOverlay: HotkeyConfig(key: LogicalKeyboardKey.escape),
      HotkeyAction.togglePlayPause: HotkeyConfig(
        key: LogicalKeyboardKey.keyP,
        modifiers: {LogicalKeyboardKey.alt},
      ),
      HotkeyAction.increaseNavSpeed: HotkeyConfig(
        key: LogicalKeyboardKey.equal,
      ),
      HotkeyAction.decreaseNavSpeed: HotkeyConfig(
        key: LogicalKeyboardKey.minus,
      ),
      HotkeyAction.scrollUp: HotkeyConfig(
        key: LogicalKeyboardKey.pageUp,
        modifiers: {LogicalKeyboardKey.alt},
      ),
      HotkeyAction.scrollDown: HotkeyConfig(
        key: LogicalKeyboardKey.pageDown,
        modifiers: {LogicalKeyboardKey.alt},
      ),
    };
  }

  // ==================== 悬浮窗设置 ====================

  /// 悬浮窗透明度 (0.0 - 1.0)
  double getOverlayOpacity() {
    if (isDesktop) {
      return (_cache[_keyOverlayOpacity] as num?)?.toDouble() ?? 0.9;
    }
    return _prefs?.getDouble(_keyOverlayOpacity) ?? 0.9;
  }

  Future<void> setOverlayOpacity(double value) async {
    if (isDesktop) {
      _cache[_keyOverlayOpacity] = value;
      await _saveValue(_keyOverlayOpacity, value);
    } else {
      await _prefs?.setDouble(_keyOverlayOpacity, value);
    }
  }

  /// 悬浮窗尺寸 (0=小, 1=中, 2=大)
  int getOverlaySize() {
    if (isDesktop) {
      return (_cache[_keyOverlaySize] as num?)?.toInt() ?? 1;
    }
    return _prefs?.getInt(_keyOverlaySize) ?? 1;
  }

  Future<void> setOverlaySize(int value) async {
    if (isDesktop) {
      _cache[_keyOverlaySize] = value;
      await _saveValue(_keyOverlaySize, value);
    } else {
      await _prefs?.setInt(_keyOverlaySize, value);
    }
  }

  /// 关闭按钮行为：true=最小化到托盘，false=退出程序
  bool getCloseToTray() {
    if (isDesktop) {
      return _cache[_keyCloseToTray] as bool? ?? true;
    }
    return _prefs?.getBool(_keyCloseToTray) ?? true;
  }

  Future<void> setCloseToTray(bool value) async {
    if (isDesktop) {
      _cache[_keyCloseToTray] = value;
      await _saveValue(_keyCloseToTray, value);
    } else {
      await _prefs?.setBool(_keyCloseToTray, value);
    }
  }

  /// 悬浮窗位置
  double? getOverlayX() {
    if (isDesktop) {
      return (_cache[_keyOverlayX] as num?)?.toDouble();
    }
    return _prefs?.getDouble(_keyOverlayX);
  }

  double? getOverlayY() {
    if (isDesktop) {
      return (_cache[_keyOverlayY] as num?)?.toDouble();
    }
    return _prefs?.getDouble(_keyOverlayY);
  }

  Future<void> setOverlayPosition(double x, double y) async {
    if (isDesktop) {
      _cache[_keyOverlayX] = x;
      _cache[_keyOverlayY] = y;
      await _saveValues({_keyOverlayX: x, _keyOverlayY: y});
    } else {
      await _prefs?.setDouble(_keyOverlayX, x);
      await _prefs?.setDouble(_keyOverlayY, y);
    }
  }

  /// 获取悬浮窗尺寸像素值
  (double width, double height) getOverlaySizePixels() {
    return calculateSizePixels(getOverlaySize());
  }

  /// 静态方法：根据尺寸索引计算像素值
  static (double width, double height) calculateSizePixels(int sizeIndex) {
    switch (sizeIndex) {
      case 0:
        return (500.0, 800.0); // 小（窄长）
      case 2:
        return (600.0, 950.0); // 大
      default:
        return (550.0, 850.0); // 中（默认，窄长）
    }
  }

  /// 悬浮窗导航速度 (1=慢, 5=快)，默认3档
  int getOverlayNavSpeed() {
    if (isDesktop) {
      return (_cache[_keyOverlayNavSpeed] as num?)?.toInt() ?? 3;
    }
    return _prefs?.getInt(_keyOverlayNavSpeed) ?? 3;
  }

  Future<void> setOverlayNavSpeed(int value) async {
    if (isDesktop) {
      _cache[_keyOverlayNavSpeed] = value;
      await _saveValue(_keyOverlayNavSpeed, value);
    } else {
      await _prefs?.setInt(_keyOverlayNavSpeed, value);
    }
  }

  // ==================== 主题设置 ====================

  /// 主题模式 (0=跟随系统, 1=浅色, 2=深色)
  int getThemeMode() {
    if (isDesktop) {
      return (_cache[_keyThemeMode] as num?)?.toInt() ?? 2;
    }
    return _prefs?.getInt(_keyThemeMode) ?? 2;
  }

  Future<void> setThemeMode(int value) async {
    if (isDesktop) {
      _cache[_keyThemeMode] = value;
      await _saveValue(_keyThemeMode, value);
    } else {
      await _prefs?.setInt(_keyThemeMode, value);
    }
  }

  /// 节日主题是否启用
  bool getSeasonalThemeEnabled() {
    if (isDesktop) {
      return _cache[_keySeasonalThemeEnabled] as bool? ?? true;
    }
    return _prefs?.getBool(_keySeasonalThemeEnabled) ?? true;
  }

  Future<void> setSeasonalThemeEnabled(bool value) async {
    if (isDesktop) {
      _cache[_keySeasonalThemeEnabled] = value;
      await _saveValue(_keySeasonalThemeEnabled, value);
    } else {
      await _prefs?.setBool(_keySeasonalThemeEnabled, value);
    }
  }

  // ==================== 移动端设置 ====================

  /// 标点移动模式 (0=长按选定, 1=摇杆) - 仅移动端
  int getMarkerMoveMode() {
    if (isDesktop) {
      return (_cache[_keyMarkerMoveMode] as num?)?.toInt() ?? 0;
    }
    return _prefs?.getInt(_keyMarkerMoveMode) ?? 0;
  }

  Future<void> setMarkerMoveMode(int value) async {
    if (isDesktop) {
      _cache[_keyMarkerMoveMode] = value;
      await _saveValue(_keyMarkerMoveMode, value);
    } else {
      await _prefs?.setInt(_keyMarkerMoveMode, value);
    }
  }

  /// 摇杆透明度 (0.3-1.0)
  double getJoystickOpacity() {
    if (isDesktop) {
      return (_cache[_keyJoystickOpacity] as num?)?.toDouble() ?? 0.8;
    }
    return _prefs?.getDouble(_keyJoystickOpacity) ?? 0.8;
  }

  Future<void> setJoystickOpacity(double value) async {
    if (isDesktop) {
      _cache[_keyJoystickOpacity] = value;
      await _saveValue(_keyJoystickOpacity, value);
    } else {
      await _prefs?.setDouble(_keyJoystickOpacity, value);
    }
  }

  /// 摇杆移动速度 (1=慢, 5=快)
  int getJoystickSpeed() {
    if (isDesktop) {
      return (_cache[_keyJoystickSpeed] as num?)?.toInt() ?? 3;
    }
    return _prefs?.getInt(_keyJoystickSpeed) ?? 3;
  }

  Future<void> setJoystickSpeed(int value) async {
    if (isDesktop) {
      _cache[_keyJoystickSpeed] = value;
      await _saveValue(_keyJoystickSpeed, value);
    } else {
      await _prefs?.setInt(_keyJoystickSpeed, value);
    }
  }

  // ==================== 应用统计 ====================

  /// 获取应用启动次数
  int getLaunchCount() {
    if (isDesktop) {
      return (_cache[_keyLaunchCount] as num?)?.toInt() ?? 0;
    }
    return _prefs?.getInt(_keyLaunchCount) ?? 0;
  }

  /// 增加启动次数并返回新值
  Future<int> incrementLaunchCount() async {
    final count = getLaunchCount() + 1;
    if (isDesktop) {
      _cache[_keyLaunchCount] = count;
      await _saveValue(_keyLaunchCount, count);
    } else {
      await _prefs?.setInt(_keyLaunchCount, count);
    }
    return count;
  }

  /// 是否已显示过赞助提醒弹窗
  bool isDonationDialogShown() {
    if (isDesktop) {
      return _cache[_keyDonationDialogShown] as bool? ?? false;
    }
    return _prefs?.getBool(_keyDonationDialogShown) ?? false;
  }

  /// 标记已显示赞助提醒弹窗
  Future<void> setDonationDialogShown() async {
    if (isDesktop) {
      _cache[_keyDonationDialogShown] = true;
      await _saveValue(_keyDonationDialogShown, true);
    } else {
      await _prefs?.setBool(_keyDonationDialogShown, true);
    }
  }

  // ==================== 数据存储路径 ====================

  /// 获取自定义数据路径（null表示使用默认路径）
  String? getCustomDataPath() {
    if (isDesktop) {
      return _cache[_keyDataPath] as String?;
    }
    return _prefs?.getString(_keyDataPath);
  }

  /// 设置自定义数据路径（null表示恢复默认）
  Future<void> setCustomDataPath(String? customPath) async {
    print('[Settings] setCustomDataPath called with: $customPath');

    if (isDesktop) {
      if (customPath == null) {
        _cache.remove(_keyDataPath);
      } else {
        _cache[_keyDataPath] = customPath;
      }
      if (customPath == null) {
        await _saveValue(_keyDataPath, null);
      } else {
        await _saveValue(_keyDataPath, customPath);
      }

      // 同时更新旧的 custom_data_path.txt 文件以保持兼容性
      try {
        final appSupport = await getApplicationSupportDirectory();
        final configFile =
            File(path.join(appSupport.path, 'custom_data_path.txt'));
        if (customPath == null) {
          if (await configFile.exists()) {
            await configFile.delete();
          }
        } else {
          await configFile.writeAsString(customPath, flush: true);
        }
      } catch (e) {
        print('[Settings] Error updating legacy config file: $e');
      }
    } else {
      if (customPath == null) {
        await _prefs?.remove(_keyDataPath);
      } else {
        await _prefs?.setString(_keyDataPath, customPath);
      }
    }
  }

  /// 获取默认数据路径（应用根目录/data）
  static Future<String> getDefaultDataPath() async {
    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, 'data');
  }

  /// 获取实际使用的数据路径
  Future<String> getEffectiveDataPath() async {
    // 桌面端优先从内存缓存读取
    if (isDesktop) {
      final customPath = _cache[_keyDataPath] as String?;
      if (customPath != null && customPath.isNotEmpty) {
        return customPath;
      }
    }

    // 兼容旧的文件存储方式
    try {
      final appSupport = await getApplicationSupportDirectory();
      final configFile =
          File(path.join(appSupport.path, 'custom_data_path.txt'));
      if (await configFile.exists()) {
        final customPath = (await configFile.readAsString()).trim();
        if (customPath.isNotEmpty) {
          return customPath;
        }
      }
    } catch (e) {
      print('[Settings] Error reading legacy config file: $e');
    }

    return await getDefaultDataPath();
  }

  /// 静态方法：在 SettingsService 初始化前获取数据路径
  static Future<String> getDataPathBeforeInit() async {
    String? customPath;

    // 优先从 settings.json 读取（桌面端新方式）
    if (isDesktop) {
      try {
        final appSupport = await getApplicationSupportDirectory();
        final settingsFile = File(path.join(appSupport.path, 'settings.json'));
        if (await settingsFile.exists()) {
          final content = await settingsFile.readAsString();
          if (content.isNotEmpty) {
            final cache = jsonDecode(content) as Map<String, dynamic>;
            customPath = cache[_keyDataPath] as String?;
          }
        }
      } catch (e) {
        print('[Settings] Error reading settings.json: $e');
      }
    }

    // 兼容旧的文件存储方式
    if (customPath == null || customPath.isEmpty) {
      try {
        final appSupport = await getApplicationSupportDirectory();
        final configFile =
            File(path.join(appSupport.path, 'custom_data_path.txt'));
        if (await configFile.exists()) {
          customPath = await configFile.readAsString();
          customPath = customPath.trim();
          if (customPath.isEmpty) customPath = null;
        }
      } catch (e) {
        print('[Settings] Error reading legacy config file: $e');
      }
    }

    print('[Settings] getDataPathBeforeInit - customPath: $customPath');
    final String targetDir;

    if (customPath != null && customPath.isNotEmpty) {
      targetDir = customPath;
    } else {
      targetDir = await getDefaultDataPath();

      // 执行从"旧默认路径"到"新默认路径"的一次性迁移
      try {
        final newDir = Directory(targetDir);
        if (!newDir.existsSync() ||
            (newDir.listSync().isEmpty &&
                !File(path.join(targetDir, 'lock')).existsSync())) {
          final exePath = Platform.resolvedExecutable;
          final appRoot = Directory(exePath).parent.path;
          final oldPath = path.join(appRoot, 'data');

          if (Directory(oldPath).existsSync()) {
            print(
                '[Settings] Detecting legacy data at: $oldPath, migrating...');
            await moveData(oldPath, targetDir);
            print('[Settings] Legacy data migration completed.');
          }
        }
      } catch (e) {
        print('[Settings] Error checking legacy migration: $e');
      }
    }

    return targetDir;
  }

  /// 递归复制目录
  static Future<void> copyDirectory(
      Directory source, Directory destination) async {
    if (!destination.existsSync()) {
      await destination.create(recursive: true);
    }

    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
            path.join(destination.absolute.path, path.basename(entity.path)));
        await copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
            path.join(destination.absolute.path, path.basename(entity.path)));
      }
    }
  }

  /// 迁移数据到新路径
  static Future<void> moveData(String fromPath, String toPath) async {
    if (fromPath == toPath) return;

    final sourceDir = Directory(fromPath);
    if (!sourceDir.existsSync()) return;

    final targetDir = Directory(toPath);
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }

    print('[Settings] Copying data from $fromPath to $toPath');
    await copyDirectory(sourceDir, targetDir);
  }
}
