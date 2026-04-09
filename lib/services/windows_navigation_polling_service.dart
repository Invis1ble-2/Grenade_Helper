import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings_service.dart';

typedef HotkeyActionCallback = void Function(HotkeyAction action);

class WindowsHotkeyPollingService {
  WindowsHotkeyPollingService(
    this._settings, {
    required HotkeyActionCallback onKeyDown,
    HotkeyActionCallback? onKeyUp,
  })  : _onKeyDown = onKeyDown,
        _onKeyUp = onKeyUp;

  static const MethodChannel _channel =
      MethodChannel('grenade_helper/windows_navigation');
  static const Duration _pollInterval = Duration(milliseconds: 16);
  static const Set<HotkeyAction> _coreActions = {
    HotkeyAction.toggleOverlay,
  };
  static const Set<HotkeyAction> _overlayActions = {
    HotkeyAction.hideOverlay,
    HotkeyAction.navigateUp,
    HotkeyAction.navigateDown,
    HotkeyAction.navigateLeft,
    HotkeyAction.navigateRight,
    HotkeyAction.prevGrenade,
    HotkeyAction.nextGrenade,
    HotkeyAction.prevStep,
    HotkeyAction.nextStep,
    HotkeyAction.toggleSmoke,
    HotkeyAction.toggleFlash,
    HotkeyAction.toggleMolotov,
    HotkeyAction.toggleHE,
    HotkeyAction.toggleWallbang,
    HotkeyAction.togglePlayPause,
    HotkeyAction.toggleMediaFullscreenPreview,
    HotkeyAction.increaseNavSpeed,
    HotkeyAction.decreaseNavSpeed,
    HotkeyAction.scrollUp,
    HotkeyAction.scrollDown,
  };
  static final Set<HotkeyAction> _trackedActions = {
    ..._coreActions,
    ..._overlayActions,
  };
  static const Set<HotkeyAction> _repeatWhilePressedActions = {
    HotkeyAction.navigateUp,
    HotkeyAction.navigateDown,
    HotkeyAction.navigateLeft,
    HotkeyAction.navigateRight,
  };

  final SettingsService _settings;
  final HotkeyActionCallback _onKeyDown;
  final HotkeyActionCallback? _onKeyUp;

  Timer? _pollTimer;
  bool _overlayHotkeysEnabled = false;
  bool _isDisposed = false;
  bool _isPolling = false;
  final Map<HotkeyAction, bool> _lastPressedState = {
    for (final action in _trackedActions) action: false,
  };

  static bool get isSupportedPlatform => Platform.isWindows;

  Future<void> init() async {
    if (!isSupportedPlatform || _isDisposed) return;
    await _syncBindings();
    _startPolling();
    await _pollHotkeyState();
  }

  Future<void> setOverlayHotkeysEnabled(bool enabled) async {
    if (!isSupportedPlatform || _isDisposed) return;
    if (_overlayHotkeysEnabled == enabled) return;

    _overlayHotkeysEnabled = enabled;
    if (!enabled) {
      _releaseDisabledActions();
    }
    await _pollHotkeyState();
  }

  Future<void> reloadBindings() async {
    if (!isSupportedPlatform || _isDisposed) return;
    await _syncBindings();
    await _pollHotkeyState();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _releaseAllPressedActions();
    try {
      await _channel.invokeMethod<void>('clearHotkeyBindings');
    } catch (e) {
      debugPrint(
        '[WindowsHotkeyPollingService] Failed to clear hotkey bindings: $e',
      );
    }
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollHotkeyState());
    });
  }

  Future<void> _syncBindings() async {
    final hotkeys = _settings.getHotkeys();
    final bindings = <String, dynamic>{};

    for (final action in _trackedActions) {
      final config = hotkeys[action];
      if (config == null) continue;

      final binding = _toBindingPayload(config);
      if (binding == null) {
        debugPrint(
          '[WindowsHotkeyPollingService] Unsupported hotkey config for $action: ${config.toDisplayString()}',
        );
        continue;
      }
      bindings[action.name] = binding;
    }

    try {
      await _channel.invokeMethod<void>('setHotkeyBindings', bindings);
    } catch (e) {
      debugPrint(
        '[WindowsHotkeyPollingService] Failed to set hotkey bindings: $e',
      );
    }
  }

  Future<void> _pollHotkeyState() async {
    if (_isDisposed || _isPolling) return;

    _isPolling = true;
    try {
      final rawState =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('readHotkeyState');

      for (final action in _trackedActions) {
        final isPressed =
            _isActionEnabled(action) && rawState?[action.name] == true;
        final wasPressed = _lastPressedState[action] ?? false;

        if (isPressed &&
            (!wasPressed || _repeatWhilePressedActions.contains(action))) {
          _onKeyDown(action);
        } else if (!isPressed && wasPressed) {
          _onKeyUp?.call(action);
        }

        _lastPressedState[action] = isPressed;
      }
    } catch (e) {
      debugPrint(
        '[WindowsHotkeyPollingService] Failed to poll hotkey state: $e',
      );
    } finally {
      _isPolling = false;
    }
  }

  bool _isActionEnabled(HotkeyAction action) {
    return _coreActions.contains(action) ||
        (_overlayHotkeysEnabled && _overlayActions.contains(action));
  }

  void _releaseDisabledActions() {
    for (final action in _trackedActions) {
      if (_isActionEnabled(action) || _lastPressedState[action] != true) {
        continue;
      }
      _onKeyUp?.call(action);
      _lastPressedState[action] = false;
    }
  }

  void _releaseAllPressedActions() {
    for (final action in _trackedActions) {
      if (_lastPressedState[action] != true) continue;
      _onKeyUp?.call(action);
      _lastPressedState[action] = false;
    }
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
      'requiresMeta': modifiers.any((key) =>
          key == LogicalKeyboardKey.meta ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight),
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
