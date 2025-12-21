import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'settings_service.dart';

/// 快捷键服务 - 管理全局快捷键的注册和响应
class HotkeyService {
  final SettingsService _settings;
  final Map<HotkeyAction, HotKey> _registeredHotkeys = {};
  final Map<HotkeyAction, void Function()> _handlers = {};

  // 悬浮窗专用热键（动态注册）
  final Map<HotkeyAction, HotKey> _overlayHotkeys = {};
  bool _overlayHotkeysRegistered = false;

  HotkeyService(this._settings);

  /// 初始化并注册核心快捷键（Alt+G 等始终生效的）
  Future<void> init() async {
    if (!SettingsService.isDesktop) return;
    await _registerCoreHotkeys();
  }

  /// 注册动作处理器
  void registerHandler(HotkeyAction action, void Function() handler) {
    _handlers[action] = handler;
  }

  /// 移除动作处理器
  void unregisterHandler(HotkeyAction action) {
    _handlers.remove(action);
  }

  /// 注册核心热键（始终生效，如 Alt+G）
  Future<void> _registerCoreHotkeys() async {
    final hotkeys = _settings.getHotkeys();
    // 只注册带修饰键的核心热键
    final coreActions = [
      HotkeyAction.toggleOverlay,
    ];
    for (final action in coreActions) {
      final config = hotkeys[action];
      if (config != null && config.modifiers.isNotEmpty) {
        await _registerHotkey(action, config, _registeredHotkeys);
      }
    }
  }

  /// 注册悬浮窗热键（悬浮窗显示时调用）
  Future<void> registerOverlayHotkeys() async {
    if (_overlayHotkeysRegistered) return;

    final hotkeys = _settings.getHotkeys();
    final overlayActions = [
      HotkeyAction.prevGrenade,
      HotkeyAction.nextGrenade,
      HotkeyAction.prevStep,
      HotkeyAction.nextStep,
      HotkeyAction.toggleSmoke,
      HotkeyAction.toggleFlash,
      HotkeyAction.toggleMolotov,
      HotkeyAction.toggleHE,
      // 方向键导航
      HotkeyAction.navigateUp,
      HotkeyAction.navigateDown,
      HotkeyAction.navigateLeft,
      HotkeyAction.navigateRight,
      // 视频播放控制
      HotkeyAction.togglePlayPause,
      // 速度调节
      HotkeyAction.increaseNavSpeed,
      HotkeyAction.decreaseNavSpeed,
    ];

    for (final action in overlayActions) {
      final config = hotkeys[action];
      if (config != null) {
        await _registerHotkey(action, config, _overlayHotkeys,
            allowNoModifier: true);
      }
    }

    _overlayHotkeysRegistered = true;
    // print('Overlay hotkeys registered: ${_overlayHotkeys.length} keys');
  }

  /// 注销悬浮窗热键（悬浮窗隐藏时调用）
  Future<void> unregisterOverlayHotkeys() async {
    if (!_overlayHotkeysRegistered) return;

    for (final hotKey in _overlayHotkeys.values) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (e) {
        print('Failed to unregister overlay hotkey: $e');
      }
    }
    _overlayHotkeys.clear();
    _overlayHotkeysRegistered = false;
    // print('Overlay hotkeys unregistered');
  }

  /// 注册单个快捷键
  Future<void> _registerHotkey(
    HotkeyAction action,
    HotkeyConfig config,
    Map<HotkeyAction, HotKey> targetMap, {
    bool allowNoModifier = false,
  }) async {
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

    // 如果不允许无修饰键且没有修饰键，则跳过
    if (!allowNoModifier && modifiers.isEmpty) return;

    // 转换 LogicalKeyboardKey 到 PhysicalKeyboardKey
    final physicalKey = _logicalToPhysical(config.key);
    if (physicalKey == null) {
      // print('No physical key mapping for: ${config.key.keyLabel}');
      return;
    }

    try {
      final hotKey = HotKey(
        key: physicalKey,
        modifiers: modifiers,
        scope: HotKeyScope.system, // 系统级全局热键
      );

      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hotKey) {
          // print('Global hotkey triggered: $action');
          _handlers[action]?.call();
        },
      );

      targetMap[action] = hotKey;
    } catch (e) {
      print('Failed to register hotkey for $action: $e');
    }
  }

  /// LogicalKeyboardKey 转 PhysicalKeyboardKey
  PhysicalKeyboardKey? _logicalToPhysical(LogicalKeyboardKey logical) {
    final mapping = <int, PhysicalKeyboardKey>{
      // 字母键
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
      // 数字键
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
      // 功能键
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
      // 导航键
      LogicalKeyboardKey.pageUp.keyId: PhysicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown.keyId: PhysicalKeyboardKey.pageDown,
      LogicalKeyboardKey.home.keyId: PhysicalKeyboardKey.home,
      LogicalKeyboardKey.end.keyId: PhysicalKeyboardKey.end,
      // 括号键
      LogicalKeyboardKey.bracketLeft.keyId: PhysicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.bracketRight.keyId: PhysicalKeyboardKey.bracketRight,
      // 方向键
      LogicalKeyboardKey.arrowUp.keyId: PhysicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown.keyId: PhysicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft.keyId: PhysicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight.keyId: PhysicalKeyboardKey.arrowRight,
      // 等号和减号键
      LogicalKeyboardKey.equal.keyId: PhysicalKeyboardKey.equal,
      LogicalKeyboardKey.minus.keyId: PhysicalKeyboardKey.minus,
    };
    return mapping[logical.keyId];
  }

  /// 更新单个快捷键
  Future<void> updateHotkey(HotkeyAction action, HotkeyConfig config) async {
    await _settings.saveHotkey(action, config);
    // 如果是悬浮窗热键，需要重新注册
    if (_overlayHotkeys.containsKey(action)) {
      await unregisterOverlayHotkeys();
      await registerOverlayHotkeys();
    }
  }

  /// 清理所有快捷键
  Future<void> dispose() async {
    for (final hotKey in _registeredHotkeys.values) {
      await hotKeyManager.unregister(hotKey);
    }
    await unregisterOverlayHotkeys();
    _registeredHotkeys.clear();
    _handlers.clear();
  }
}
