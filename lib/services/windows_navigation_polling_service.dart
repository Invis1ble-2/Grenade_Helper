import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings_service.dart';

typedef OverlayCommandSender = void Function(
  String command, [
  Map<String, dynamic>? args,
]);

class WindowsNavigationPollingService {
  WindowsNavigationPollingService(this._settings, this._sendOverlayCommand);

  static const MethodChannel _channel =
      MethodChannel('grenade_helper/windows_navigation');
  static const Duration _pollInterval = Duration(milliseconds: 16);
  static const Map<HotkeyAction, String> _directionNames = {
    HotkeyAction.navigateUp: 'up',
    HotkeyAction.navigateDown: 'down',
    HotkeyAction.navigateLeft: 'left',
    HotkeyAction.navigateRight: 'right',
  };

  final SettingsService _settings;
  final OverlayCommandSender _sendOverlayCommand;
  Timer? _pollTimer;
  bool _overlayVisible = false;
  bool _isPolling = false;
  bool _isDisposed = false;
  final Map<String, bool> _lastPressedState = {
    'up': false,
    'down': false,
    'left': false,
    'right': false,
  };

  static bool get isSupportedPlatform => Platform.isWindows;

  static bool supportsNavigationBindings(
    Map<HotkeyAction, HotkeyConfig> hotkeys,
  ) {
    for (final action in _directionNames.keys) {
      final config = hotkeys[action];
      if (config == null || !_isSupportedConfig(config)) {
        return false;
      }
    }
    return true;
  }

  Future<void> start() async {
    if (!isSupportedPlatform || _isDisposed) return;
    _overlayVisible = true;
    final enabled = await _syncBindings();
    if (!enabled) return;
    _startPolling();
    await _pollNavigationState();
  }

  Future<void> stop() async {
    if (!isSupportedPlatform) return;
    _overlayVisible = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
    _resetPressedState();
    try {
      await _channel.invokeMethod<void>('clearNavigationBindings');
    } catch (e) {
      debugPrint(
        '[WindowsNavigationPollingService] Failed to clear navigation bindings: $e',
      );
    }
    _sendOverlayCommand('stop_all_navigation');
  }

  Future<void> reloadBindings() async {
    if (!isSupportedPlatform || _isDisposed) return;
    final enabled = await _syncBindings();
    if (!_overlayVisible) return;
    if (enabled) {
      _startPolling();
      await _pollNavigationState();
    } else {
      await stop();
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await stop();
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollNavigationState());
    });
  }

  Future<bool> _syncBindings() async {
    final hotkeys = _settings.getHotkeys();
    if (!supportsNavigationBindings(hotkeys)) {
      debugPrint(
        '[WindowsNavigationPollingService] Navigation bindings are not fully supported, using hotkey_manager fallback.',
      );
      try {
        await _channel.invokeMethod<void>('clearNavigationBindings');
      } catch (e) {
        debugPrint(
          '[WindowsNavigationPollingService] Failed to clear unsupported navigation bindings: $e',
        );
      }
      return false;
    }

    final bindings = <String, dynamic>{};
    for (final entry in _directionNames.entries) {
      final config = hotkeys[entry.key];
      if (config == null) continue;
      final binding = _toBindingPayload(config);
      if (binding == null) {
        try {
          await _channel.invokeMethod<void>('clearNavigationBindings');
        } catch (e) {
          debugPrint(
            '[WindowsNavigationPollingService] Failed to clear invalid navigation bindings: $e',
          );
        }
        return false;
      }
      bindings[entry.value] = binding;
    }

    try {
      await _channel.invokeMethod<void>('setNavigationBindings', bindings);
      return true;
    } catch (e) {
      debugPrint(
        '[WindowsNavigationPollingService] Failed to set navigation bindings: $e',
      );
      return false;
    }
  }

  Future<void> _pollNavigationState() async {
    if (!_overlayVisible || _isDisposed || _isPolling) return;

    _isPolling = true;
    try {
      final rawState = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('readNavigationState');
      final pressedState = <String, bool>{
        for (final direction in _lastPressedState.keys)
          direction: rawState?[direction] == true,
      };

      for (final entry in pressedState.entries) {
        if (entry.value) {
          _sendOverlayCommand('start_navigation', {'direction': entry.key});
        } else if (_lastPressedState[entry.key] == true) {
          _sendOverlayCommand('stop_navigation', {'direction': entry.key});
        }
      }

      _lastPressedState
        ..clear()
        ..addAll(pressedState);
    } catch (e) {
      debugPrint(
        '[WindowsNavigationPollingService] Failed to poll navigation state: $e',
      );
    } finally {
      _isPolling = false;
    }
  }

  void _resetPressedState() {
    for (final direction in _lastPressedState.keys) {
      _lastPressedState[direction] = false;
    }
  }

  static bool _isSupportedConfig(HotkeyConfig config) {
    if (_toVirtualKey(config.key) == null) {
      return false;
    }
    return config.modifiers.every(_isSupportedModifier);
  }

  static bool _isSupportedModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight;
  }

  static Map<String, dynamic>? _toBindingPayload(HotkeyConfig config) {
    final virtualKey = _toVirtualKey(config.key);
    if (virtualKey == null) return null;

    final modifiers = config.modifiers;
    return {
      'virtualKey': virtualKey,
      'requiresAlt': modifiers.any((key) =>
          key == LogicalKeyboardKey.alt ||
          key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight),
      'requiresCtrl': modifiers.any((key) =>
          key == LogicalKeyboardKey.control ||
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight),
      'requiresShift': modifiers.any((key) =>
          key == LogicalKeyboardKey.shift ||
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight),
    };
  }

  static int? _toVirtualKey(LogicalKeyboardKey logical) {
    final mapping = <int, int>{
      LogicalKeyboardKey.keyA.keyId: 0x41,
      LogicalKeyboardKey.keyB.keyId: 0x42,
      LogicalKeyboardKey.keyC.keyId: 0x43,
      LogicalKeyboardKey.keyD.keyId: 0x44,
      LogicalKeyboardKey.keyE.keyId: 0x45,
      LogicalKeyboardKey.keyF.keyId: 0x46,
      LogicalKeyboardKey.keyG.keyId: 0x47,
      LogicalKeyboardKey.keyH.keyId: 0x48,
      LogicalKeyboardKey.keyI.keyId: 0x49,
      LogicalKeyboardKey.keyJ.keyId: 0x4A,
      LogicalKeyboardKey.keyK.keyId: 0x4B,
      LogicalKeyboardKey.keyL.keyId: 0x4C,
      LogicalKeyboardKey.keyM.keyId: 0x4D,
      LogicalKeyboardKey.keyN.keyId: 0x4E,
      LogicalKeyboardKey.keyO.keyId: 0x4F,
      LogicalKeyboardKey.keyP.keyId: 0x50,
      LogicalKeyboardKey.keyQ.keyId: 0x51,
      LogicalKeyboardKey.keyR.keyId: 0x52,
      LogicalKeyboardKey.keyS.keyId: 0x53,
      LogicalKeyboardKey.keyT.keyId: 0x54,
      LogicalKeyboardKey.keyU.keyId: 0x55,
      LogicalKeyboardKey.keyV.keyId: 0x56,
      LogicalKeyboardKey.keyW.keyId: 0x57,
      LogicalKeyboardKey.keyX.keyId: 0x58,
      LogicalKeyboardKey.keyY.keyId: 0x59,
      LogicalKeyboardKey.keyZ.keyId: 0x5A,
      LogicalKeyboardKey.digit0.keyId: 0x30,
      LogicalKeyboardKey.digit1.keyId: 0x31,
      LogicalKeyboardKey.digit2.keyId: 0x32,
      LogicalKeyboardKey.digit3.keyId: 0x33,
      LogicalKeyboardKey.digit4.keyId: 0x34,
      LogicalKeyboardKey.digit5.keyId: 0x35,
      LogicalKeyboardKey.digit6.keyId: 0x36,
      LogicalKeyboardKey.digit7.keyId: 0x37,
      LogicalKeyboardKey.digit8.keyId: 0x38,
      LogicalKeyboardKey.digit9.keyId: 0x39,
      LogicalKeyboardKey.escape.keyId: 0x1B,
      LogicalKeyboardKey.enter.keyId: 0x0D,
      LogicalKeyboardKey.f1.keyId: 0x70,
      LogicalKeyboardKey.f2.keyId: 0x71,
      LogicalKeyboardKey.f3.keyId: 0x72,
      LogicalKeyboardKey.f4.keyId: 0x73,
      LogicalKeyboardKey.f5.keyId: 0x74,
      LogicalKeyboardKey.f6.keyId: 0x75,
      LogicalKeyboardKey.f7.keyId: 0x76,
      LogicalKeyboardKey.f8.keyId: 0x77,
      LogicalKeyboardKey.f9.keyId: 0x78,
      LogicalKeyboardKey.f10.keyId: 0x79,
      LogicalKeyboardKey.f11.keyId: 0x7A,
      LogicalKeyboardKey.f12.keyId: 0x7B,
      LogicalKeyboardKey.pageUp.keyId: 0x21,
      LogicalKeyboardKey.pageDown.keyId: 0x22,
      LogicalKeyboardKey.home.keyId: 0x24,
      LogicalKeyboardKey.end.keyId: 0x23,
      LogicalKeyboardKey.bracketLeft.keyId: 0xDB,
      LogicalKeyboardKey.bracketRight.keyId: 0xDD,
      LogicalKeyboardKey.arrowUp.keyId: 0x26,
      LogicalKeyboardKey.arrowDown.keyId: 0x28,
      LogicalKeyboardKey.arrowLeft.keyId: 0x25,
      LogicalKeyboardKey.arrowRight.keyId: 0x27,
      LogicalKeyboardKey.equal.keyId: 0xBB,
      LogicalKeyboardKey.minus.keyId: 0xBD,
    };
    return mapping[logical.keyId];
  }
}
