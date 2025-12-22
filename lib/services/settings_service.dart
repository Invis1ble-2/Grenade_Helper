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
  hideOverlay, // 隐藏悬浮窗
  togglePlayPause, // 播放/暂停视频
  increaseNavSpeed, // 增加导航速度
  decreaseNavSpeed, // 减少导航速度
  scrollUp, // 向上滚动
  scrollDown, // 向下滚动
}

/// 设置服务 - 管理用户设置和快捷键配置
class SettingsService {
  static const String _keyHotkeys = 'desktop_hotkeys';
  static const String _keyOverlayOpacity = 'overlay_opacity';
  static const String _keyOverlaySize = 'overlay_size';
  static const String _keyCloseToTray = 'close_to_tray';
  static const String _keyOverlayX = 'overlay_x';
  static const String _keyOverlayY = 'overlay_y';
  static const String _keyThemeMode = 'theme_mode'; // 0=system, 1=light, 2=dark
  static const String _keyMarkerMoveMode = 'marker_move_mode'; // 0=长按选定, 1=摇杆
  static const String _keyJoystickOpacity = 'joystick_opacity'; // 0.3-1.0
  static const String _keyJoystickSpeed = 'joystick_speed'; // 1-5档
  static const String _keyOverlayNavSpeed =
      'overlay_nav_speed'; // 1-5档（桌面端悬浮窗导航速度）
  static const String _keyDataPath = 'custom_data_path'; // 自定义数据存储路径

  SharedPreferences? _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 重新加载设置（用于多窗口间同步）
  Future<void> reload() async {
    await _prefs?.reload();
  }

  /// 获取所有快捷键配置
  Map<HotkeyAction, HotkeyConfig> getHotkeys() {
    final defaults = _getDefaultHotkeys();
    final String? stored = _prefs?.getString(_keyHotkeys);
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
    await _prefs?.setString(_keyHotkeys, jsonEncode(json));
  }

  /// 重置所有快捷键为默认值
  Future<void> resetHotkeys() async {
    await _prefs?.remove(_keyHotkeys);
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
        // 不使用修饰键，直接数字键（多窗口环境下修饰键检测不稳定）
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
      HotkeyAction.hideOverlay: HotkeyConfig(key: LogicalKeyboardKey.escape),
      HotkeyAction.togglePlayPause: HotkeyConfig(
        key: LogicalKeyboardKey.keyP,
        modifiers: {LogicalKeyboardKey.alt},
      ),
      HotkeyAction.increaseNavSpeed: HotkeyConfig(
        key: LogicalKeyboardKey.equal, // = 键
      ),
      HotkeyAction.decreaseNavSpeed: HotkeyConfig(
        key: LogicalKeyboardKey.minus, // - 键
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

  /// 悬浮窗透明度 (0.0 - 1.0)
  double getOverlayOpacity() => _prefs?.getDouble(_keyOverlayOpacity) ?? 0.9;
  Future<void> setOverlayOpacity(double value) async =>
      await _prefs?.setDouble(_keyOverlayOpacity, value);

  /// 悬浮窗尺寸 (0=小, 1=中, 2=大)
  int getOverlaySize() => _prefs?.getInt(_keyOverlaySize) ?? 1;
  Future<void> setOverlaySize(int value) async =>
      await _prefs?.setInt(_keyOverlaySize, value);

  /// 关闭按钮行为：true=最小化到托盘，false=退出程序
  bool getCloseToTray() => _prefs?.getBool(_keyCloseToTray) ?? true;
  Future<void> setCloseToTray(bool value) async =>
      await _prefs?.setBool(_keyCloseToTray, value);

  /// 悬浮窗位置
  double? getOverlayX() => _prefs?.getDouble(_keyOverlayX);
  double? getOverlayY() => _prefs?.getDouble(_keyOverlayY);
  Future<void> setOverlayPosition(double x, double y) async {
    await _prefs?.setDouble(_keyOverlayX, x);
    await _prefs?.setDouble(_keyOverlayY, y);
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

  /// 主题模式 (0=跟随系统, 1=浅色, 2=深色)
  int getThemeMode() => _prefs?.getInt(_keyThemeMode) ?? 2; // 默认深色
  Future<void> setThemeMode(int value) async =>
      await _prefs?.setInt(_keyThemeMode, value);

  /// 检查是否是桌面平台
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 标点移动模式 (0=长按选定, 1=摇杆) - 仅移动端
  int getMarkerMoveMode() => _prefs?.getInt(_keyMarkerMoveMode) ?? 0;
  Future<void> setMarkerMoveMode(int value) async =>
      await _prefs?.setInt(_keyMarkerMoveMode, value);

  /// 摇杆透明度 (0.3-1.0)
  double getJoystickOpacity() => _prefs?.getDouble(_keyJoystickOpacity) ?? 0.8;
  Future<void> setJoystickOpacity(double value) async =>
      await _prefs?.setDouble(_keyJoystickOpacity, value);

  /// 摇杆移动速度 (1=慢, 5=快)
  int getJoystickSpeed() => _prefs?.getInt(_keyJoystickSpeed) ?? 3;
  Future<void> setJoystickSpeed(int value) async =>
      await _prefs?.setInt(_keyJoystickSpeed, value);

  /// 悬浮窗导航速度 (1=慢, 5=快)，默认3档
  int getOverlayNavSpeed() => _prefs?.getInt(_keyOverlayNavSpeed) ?? 3;
  Future<void> setOverlayNavSpeed(int value) async =>
      await _prefs?.setInt(_keyOverlayNavSpeed, value);

  // --- 应用启动计数与赞助提醒 ---
  static const String _keyLaunchCount = 'app_launch_count';
  static const String _keyDonationDialogShown = 'donation_dialog_shown';

  /// 获取应用启动次数
  int getLaunchCount() => _prefs?.getInt(_keyLaunchCount) ?? 0;

  /// 增加启动次数并返回新值
  Future<int> incrementLaunchCount() async {
    final count = getLaunchCount() + 1;
    await _prefs?.setInt(_keyLaunchCount, count);
    return count;
  }

  /// 是否已显示过赞助提醒弹窗
  bool isDonationDialogShown() =>
      _prefs?.getBool(_keyDonationDialogShown) ?? false;

  /// 标记已显示赞助提醒弹窗
  Future<void> setDonationDialogShown() async =>
      await _prefs?.setBool(_keyDonationDialogShown, true);

  // --- 数据存储路径 ---

  /// 获取自定义数据路径（null表示使用默认路径）
  String? getCustomDataPath() => _prefs?.getString(_keyDataPath);

  /// 设置自定义数据路径（null表示恢复默认）
  /// 使用文件存储而非 SharedPreferences，因为 SP 在 Windows 上强制退出时可能丢失数据
  Future<void> setCustomDataPath(String? customPath) async {
    print('[Settings] setCustomDataPath called with: $customPath');

    try {
      final configFile = await _getConfigFile();
      if (customPath == null) {
        if (await configFile.exists()) {
          await configFile.delete();
          print('[Settings] Config file deleted');
        }
      } else {
        await configFile.writeAsString(customPath, flush: true);
        print('[Settings] Config file written: $customPath');
      }
    } catch (e) {
      print('[Settings] Error saving custom path: $e');
    }
  }

  /// 获取配置文件路径（实例方法）
  Future<File> _getConfigFile() async {
    final appSupport = await getApplicationSupportDirectory();
    return File(path.join(appSupport.path, 'custom_data_path.txt'));
  }

  /// 获取配置文件路径（静态方法，用于初始化前调用）
  static Future<File> _getConfigFileStatic() async {
    final appSupport = await getApplicationSupportDirectory();
    return File(path.join(appSupport.path, 'custom_data_path.txt'));
  }

  /// 获取默认数据路径（应用根目录/data）
  /// 这是一个静态方法，可以在 SettingsService 初始化前调用
  static Future<String> getDefaultDataPath() async {
    // 移动端/桌面端：使用系统提供的应用支持目录
    // 这避免了在 Windows Program Files 目录下写入数据的权限问题
    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, 'data');
  }

  /// 获取实际使用的数据路径
  /// 如果设置了自定义路径则使用自定义路径，否则使用默认路径
  Future<String> getEffectiveDataPath() async {
    // 从文件读取自定义路径
    try {
      final configFile = await _getConfigFile();
      if (await configFile.exists()) {
        final customPath = (await configFile.readAsString()).trim();
        if (customPath.isNotEmpty) {
          return customPath;
        }
      }
    } catch (e) {
      print('[Settings] Error reading config file in getEffectiveDataPath: $e');
    }
    return await getDefaultDataPath();
  }

  static Future<String> getDataPathBeforeInit() async {
    String? customPath;

    // 从文件读取自定义路径
    try {
      final configFile = await _getConfigFileStatic();
      if (await configFile.exists()) {
        customPath = await configFile.readAsString();
        customPath = customPath.trim();
        if (customPath.isEmpty) customPath = null;
      }
    } catch (e) {
      print('[Settings] Error reading config file: $e');
    }

    print(
        '[Settings] getDataPathBeforeInit - customPath from file: $customPath');
    final String targetDir;

    if (customPath != null && customPath.isNotEmpty) {
      targetDir = customPath;
    } else {
      targetDir = await getDefaultDataPath();

      // --- 关键改进：执行从“旧默认路径”到“新默认路径”的一次性迁移 ---
      // 只有当用户没有设置自定义路径，且新默认目录下没有数据，但旧目录下有数据时才执行
      try {
        final newDir = Directory(targetDir);
        if (!newDir.existsSync() ||
            (newDir.listSync().isEmpty &&
                !File(path.join(targetDir, 'lock')).existsSync())) {
          // 获取旧的默认路径（安装目录下/data）
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
