import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'settings_service.dart';
import 'windows_navigation_polling_service.dart';

/// 快捷键服务
class HotkeyService {
  final SettingsService _settings;
  final Map<HotkeyAction, HotKey> _registeredHotkeys = {};
  final Map<HotkeyAction, void Function()> _handlers = {};
  static const Set<HotkeyAction> _coreActions = {
    HotkeyAction.toggleOverlay,
  };

  // 悬浮窗热键
  final Map<HotkeyAction, HotKey> _overlayHotkeys = {};
  bool _overlayHotkeysRegistered = false;

  HotkeyService(this._settings);

  /// 初始化
  Future<void> init() async {
    if (!SettingsService.isDesktop) return;
    await _registerCoreHotkeys();
  }

  /// 注册Handler
  void registerHandler(HotkeyAction action, void Function() handler) {
    _handlers[action] = handler;
  }

  /// 移除Handler
  void unregisterHandler(HotkeyAction action) {
    _handlers.remove(action);
  }

  /// 注册核心键
  Future<void> _registerCoreHotkeys() async {
    final hotkeys = _settings.getHotkeys();
    for (final action in _coreActions) {
      final config = hotkeys[action];
      if (config != null) {
        await _registerHotkey(
          action,
          config,
          _registeredHotkeys,
          allowNoModifier: _allowNoModifierForCoreAction(action),
        );
      }
    }
  }

  bool _allowNoModifierForCoreAction(HotkeyAction action) {
    // toggleOverlay 允许设置为单键，满足“显示/隐藏悬浮窗”快捷方式自定义需求
    return action == HotkeyAction.toggleOverlay;
  }

  bool _shouldHandleNavigationWithPolling() {
    if (!Platform.isWindows) return false;
    return WindowsNavigationPollingService.supportsNavigationBindings(
      _settings.getHotkeys(),
    );
  }

  bool _isNavigationAction(HotkeyAction action) {
    return action == HotkeyAction.navigateUp ||
        action == HotkeyAction.navigateDown ||
        action == HotkeyAction.navigateLeft ||
        action == HotkeyAction.navigateRight;
  }

  /// 注册悬浮键
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
      HotkeyAction.toggleWallbang,
      // 导航
      HotkeyAction.navigateUp,
      HotkeyAction.navigateDown,
      HotkeyAction.navigateLeft,
      HotkeyAction.navigateRight,
      // 视频
      HotkeyAction.togglePlayPause,
      HotkeyAction.toggleMediaFullscreenPreview,
      // 速度
      HotkeyAction.increaseNavSpeed,
      HotkeyAction.decreaseNavSpeed,
      // 滚动
      HotkeyAction.scrollUp,
      HotkeyAction.scrollDown,
    ];

    final useNavigationPolling = _shouldHandleNavigationWithPolling();
    for (final action in overlayActions) {
      if (useNavigationPolling && _isNavigationAction(action)) {
        continue;
      }
      final config = hotkeys[action];
      if (config != null) {
        await _registerHotkey(action, config, _overlayHotkeys,
            allowNoModifier: true);
      }
    }

    _overlayHotkeysRegistered = true;
    debugPrint('Overlay hotkeys registered: ${_overlayHotkeys.length} keys');
  }

  /// 注销悬浮键
  Future<void> unregisterOverlayHotkeys() async {
    if (!_overlayHotkeysRegistered) return;

    for (final hotKey in _overlayHotkeys.values) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (e) {
        debugPrint('Failed to unregister overlay hotkey: $e');
      }
    }
    _overlayHotkeys.clear();
    _overlayHotkeysRegistered = false;
    debugPrint('Overlay hotkeys unregistered');
  }

  /// 从设置重新加载已注册的全局热键
  Future<void> reloadFromSettings() async {
    for (final hotKey in _registeredHotkeys.values) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (e) {
        debugPrint('[HotkeyService] Failed to unregister core hotkey: $e');
      }
    }
    _registeredHotkeys.clear();
    await _registerCoreHotkeys();

    if (_overlayHotkeysRegistered) {
      await unregisterOverlayHotkeys();
      await registerOverlayHotkeys();
    }

    debugPrint('[HotkeyService] Hotkeys reloaded from settings');
  }

  /// 注册单键
  Future<void> _registerHotkey(
    HotkeyAction action,
    HotkeyConfig config,
    Map<HotkeyAction, HotKey> targetMap, {
    bool allowNoModifier = false,
  }) async {
    // 转修饰符
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

    // 检查修饰符
    if (!allowNoModifier && modifiers.isEmpty) return;

    // 转物理键
    final physicalKey = _logicalToPhysical(config.key);
    if (physicalKey == null) {
      debugPrint('No physical key mapping for: ${config.key.keyLabel}');
      return;
    }

    try {
      final hotKey = HotKey(
        key: physicalKey,
        modifiers: modifiers,
        scope: HotKeyScope.system, // 系统级
      );

      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hotKey) {
          // debugPrint('Global hotkey triggered: $action');
          _handlers[action]?.call();
        },
      );

      targetMap[action] = hotKey;
    } catch (e) {
      debugPrint('Failed to register hotkey for $action: $e');
    }
  }

  /// 键映射
  PhysicalKeyboardKey? _logicalToPhysical(LogicalKeyboardKey logical) {
    final mapping = <int, PhysicalKeyboardKey>{
      // 字母
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
      // 数字
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
      // F键
      LogicalKeyboardKey.escape.keyId: PhysicalKeyboardKey.escape,
      LogicalKeyboardKey.enter.keyId: PhysicalKeyboardKey.enter,
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
      // 导航
      LogicalKeyboardKey.pageUp.keyId: PhysicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown.keyId: PhysicalKeyboardKey.pageDown,
      LogicalKeyboardKey.home.keyId: PhysicalKeyboardKey.home,
      LogicalKeyboardKey.end.keyId: PhysicalKeyboardKey.end,
      // 括号
      LogicalKeyboardKey.bracketLeft.keyId: PhysicalKeyboardKey.bracketLeft,
      LogicalKeyboardKey.bracketRight.keyId: PhysicalKeyboardKey.bracketRight,
      // 方向
      LogicalKeyboardKey.arrowUp.keyId: PhysicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown.keyId: PhysicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft.keyId: PhysicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight.keyId: PhysicalKeyboardKey.arrowRight,
      // 符号
      LogicalKeyboardKey.equal.keyId: PhysicalKeyboardKey.equal,
      LogicalKeyboardKey.minus.keyId: PhysicalKeyboardKey.minus,
    };
    return mapping[logical.keyId];
  }

  /// 更新单键
  Future<void> updateHotkey(HotkeyAction action, HotkeyConfig config) async {
    await _settings.saveHotkey(action, config);

    // 检查是否是核心热键（如 toggleOverlay）
    if (_coreActions.contains(action)) {
      // 注销旧热键
      final oldHotKey = _registeredHotkeys[action];
      if (oldHotKey != null) {
        try {
          await hotKeyManager.unregister(oldHotKey);
        } catch (e) {
          debugPrint('[HotkeyService] Failed to unregister old hotkey: $e');
        }
      }
      _registeredHotkeys.remove(action);

      // 注册新热键
      await _registerHotkey(
        action,
        config,
        _registeredHotkeys,
        allowNoModifier: _allowNoModifierForCoreAction(action),
      );
      debugPrint('[HotkeyService] Core hotkey updated: $action');
    }

    // 检查是否是悬浮窗热键
    if (_overlayHotkeysRegistered &&
        (_overlayHotkeys.containsKey(action) || _isNavigationAction(action))) {
      await unregisterOverlayHotkeys();
      await registerOverlayHotkeys();
    }
  }

  /// 清理
  Future<void> dispose() async {
    for (final hotKey in _registeredHotkeys.values) {
      await hotKeyManager.unregister(hotKey);
    }
    await unregisterOverlayHotkeys();
    _registeredHotkeys.clear();
    _handlers.clear();
  }
}
