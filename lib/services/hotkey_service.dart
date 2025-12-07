import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'settings_service.dart';

/// 快捷键服务 - 管理全局快捷键的注册和响应
class HotkeyService {
  final SettingsService _settings;
  final Map<HotkeyAction, HotKey> _registeredHotkeys = {};
  final Map<HotkeyAction, void Function()> _handlers = {};

  HotkeyService(this._settings);

  /// 初始化并注册所有快捷键
  Future<void> init() async {
    if (!SettingsService.isDesktop) return;
    await _registerAllHotkeys();
  }

  /// 注册动作处理器
  void registerHandler(HotkeyAction action, void Function() handler) {
    _handlers[action] = handler;
  }

  /// 移除动作处理器
  void unregisterHandler(HotkeyAction action) {
    _handlers.remove(action);
  }

  /// 注册所有快捷键
  Future<void> _registerAllHotkeys() async {
    final hotkeys = _settings.getHotkeys();
    for (final entry in hotkeys.entries) {
      await _registerHotkey(entry.key, entry.value);
    }
  }

  /// 注册单个快捷键
  Future<void> _registerHotkey(HotkeyAction action, HotkeyConfig config) async {
    // 先注销旧的
    if (_registeredHotkeys.containsKey(action)) {
      await hotKeyManager.unregister(_registeredHotkeys[action]!);
      _registeredHotkeys.remove(action);
    }

    // 转换修饰键
    final modifiers = <HotKeyModifier>[];
    for (final mod in config.modifiers) {
      if (mod == LogicalKeyboardKey.alt ||
          mod == LogicalKeyboardKey.altLeft ||
          mod == LogicalKeyboardKey.altRight) {
        modifiers.add(HotKeyModifier.alt);
      } else if (mod == LogicalKeyboardKey.control ||
          mod == LogicalKeyboardKey.controlLeft ||
          mod == LogicalKeyboardKey.controlRight) {
        modifiers.add(HotKeyModifier.control);
      } else if (mod == LogicalKeyboardKey.shift ||
          mod == LogicalKeyboardKey.shiftLeft ||
          mod == LogicalKeyboardKey.shiftRight) {
        modifiers.add(HotKeyModifier.shift);
      } else if (mod == LogicalKeyboardKey.meta ||
          mod == LogicalKeyboardKey.metaLeft ||
          mod == LogicalKeyboardKey.metaRight) {
        modifiers.add(HotKeyModifier.meta);
      }
    }

    // 只有带修饰键的快捷键才注册为全局热键
    // 方向键等无修饰键的快捷键通过悬浮窗内部的 KeyboardListener 处理
    if (modifiers.isEmpty) return;

    // 转换 LogicalKeyboardKey 到 PhysicalKeyboardKey
    final physicalKey = _logicalToPhysical(config.key);
    if (physicalKey == null) return;

    try {
      final hotKey = HotKey(
        key: physicalKey,
        modifiers: modifiers,
        scope: HotKeyScope.system, // 系统级全局热键
      );

      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hotKey) {
          _handlers[action]?.call();
        },
      );

      _registeredHotkeys[action] = hotKey;
    } catch (e) {
      print('Failed to register hotkey for $action: $e');
    }
  }

  /// LogicalKeyboardKey 转 PhysicalKeyboardKey
  PhysicalKeyboardKey? _logicalToPhysical(LogicalKeyboardKey logical) {
    // 常用键映射
    final mapping = <int, PhysicalKeyboardKey>{
      LogicalKeyboardKey.keyA.keyId: PhysicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyB.keyId: PhysicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyC.keyId: PhysicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD.keyId: PhysicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE.keyId: PhysicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyF.keyId: PhysicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG.keyId: PhysicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyH.keyId: PhysicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyI.keyId: PhysicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyJ.keyId: PhysicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK.keyId: PhysicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL.keyId: PhysicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyM.keyId: PhysicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyN.keyId: PhysicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyO.keyId: PhysicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyP.keyId: PhysicalKeyboardKey.keyP,
      LogicalKeyboardKey.keyQ.keyId: PhysicalKeyboardKey.keyQ,
      LogicalKeyboardKey.keyR.keyId: PhysicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyS.keyId: PhysicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyT.keyId: PhysicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyU.keyId: PhysicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyV.keyId: PhysicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyW.keyId: PhysicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyX.keyId: PhysicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyY.keyId: PhysicalKeyboardKey.keyY,
      LogicalKeyboardKey.keyZ.keyId: PhysicalKeyboardKey.keyZ,
      LogicalKeyboardKey.digit0.keyId: PhysicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1.keyId: PhysicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2.keyId: PhysicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3.keyId: PhysicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4.keyId: PhysicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5.keyId: PhysicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6.keyId: PhysicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7.keyId: PhysicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8.keyId: PhysicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9.keyId: PhysicalKeyboardKey.digit9,
      LogicalKeyboardKey.escape.keyId: PhysicalKeyboardKey.escape,
      LogicalKeyboardKey.f1.keyId: PhysicalKeyboardKey.f1,
      LogicalKeyboardKey.f2.keyId: PhysicalKeyboardKey.f2,
      LogicalKeyboardKey.f3.keyId: PhysicalKeyboardKey.f3,
      LogicalKeyboardKey.f4.keyId: PhysicalKeyboardKey.f4,
      LogicalKeyboardKey.f5.keyId: PhysicalKeyboardKey.f5,
      LogicalKeyboardKey.f6.keyId: PhysicalKeyboardKey.f6,
      LogicalKeyboardKey.f7.keyId: PhysicalKeyboardKey.f7,
      LogicalKeyboardKey.f8.keyId: PhysicalKeyboardKey.f8,
      LogicalKeyboardKey.f9.keyId: PhysicalKeyboardKey.f9,
      LogicalKeyboardKey.f10.keyId: PhysicalKeyboardKey.f10,
      LogicalKeyboardKey.f11.keyId: PhysicalKeyboardKey.f11,
      LogicalKeyboardKey.f12.keyId: PhysicalKeyboardKey.f12,
    };
    return mapping[logical.keyId];
  }

  /// 更新单个快捷键
  Future<void> updateHotkey(HotkeyAction action, HotkeyConfig config) async {
    await _settings.saveHotkey(action, config);
    await _registerHotkey(action, config);
  }

  /// 清理所有快捷键
  Future<void> dispose() async {
    for (final hotKey in _registeredHotkeys.values) {
      await hotKeyManager.unregister(hotKey);
    }
    _registeredHotkeys.clear();
    _handlers.clear();
  }
}
