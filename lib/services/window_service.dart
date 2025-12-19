import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:path/path.dart' as path;
import 'settings_service.dart';
import 'hotkey_service.dart';

/// 窗口服务 - 管理主窗口和悬浮窗、系统托盘
class WindowService with TrayListener, WindowListener {
  final SettingsService _settings;
  HotkeyService? _hotkeyService;

  bool _isOverlayVisible = false;
  bool _isMainWindowVisible = true;

  // 回调函数
  void Function()? onShowMainWindow;
  void Function()? onShowOverlay;
  void Function()? onHideOverlay;
  void Function()? onExitApp;

  WindowService(this._settings);

  /// 设置热键服务引用
  void setHotkeyService(HotkeyService service) {
    _hotkeyService = service;
  }

  bool get isOverlayVisible => _isOverlayVisible;
  set isOverlayVisible(bool value) => _isOverlayVisible = value;
  bool get isMainWindowVisible => _isMainWindowVisible;

  /// 初始化窗口管理
  Future<void> init() async {
    if (!SettingsService.isDesktop) return;

    // 初始化窗口管理器
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // 设置阻止关闭，这样我们可以拦截关闭事件
    await windowManager.setPreventClose(true);

    // 添加窗口监听
    windowManager.addListener(this);

    // 初始化系统托盘
    await _initTray();
  }

  /// 初始化系统托盘
  Future<void> _initTray() async {
    trayManager.addListener(this);

    // 设置托盘图标
    String iconPath;
    if (Platform.isWindows) {
      iconPath = path.join(Directory.current.path, 'windows', 'runner',
          'resources', 'app_icon.ico');
      // 如果自定义图标不存在，使用默认路径
      if (!File(iconPath).existsSync()) {
        iconPath = 'assets/icons/app_icon.png';
      }
    } else {
      iconPath = 'assets/icons/app_icon.png';
    }

    try {
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Grenade Helper');
      await _updateTrayMenu();
    } catch (e) {
      print('Failed to initialize tray: $e');
    }
  }

  /// 更新托盘菜单
  Future<void> _updateTrayMenu() async {
    final menu = Menu(
      items: [
        MenuItem(
          key: 'show_main',
          label: '显示主窗口',
        ),
        MenuItem(
          key: 'show_overlay',
          label: _isOverlayVisible ? '隐藏悬浮窗' : '显示悬浮窗',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: '退出程序',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  /// 托盘菜单点击回调
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_main':
        showMainWindow();
        break;
      case 'show_overlay':
        if (_isOverlayVisible) {
          hideOverlay();
        } else {
          showOverlay();
        }
        break;
      case 'exit':
        forceExitApp();
        break;
    }
  }

  /// 托盘图标双击回调
  @override
  void onTrayIconMouseDown() {
    showMainWindow();
  }

  /// 托盘图标右键回调
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  /// 窗口关闭事件 - 拦截关闭按钮
  @override
  void onWindowClose() async {
    if (_settings.getCloseToTray()) {
      // 最小化到托盘而非关闭
      await windowManager.hide();
      _isMainWindowVisible = false;
    } else {
      // 真正退出
      await forceExitApp();
    }
  }

  /// 显示主窗口
  Future<void> showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
    _isMainWindowVisible = true;
    onShowMainWindow?.call();
  }

  /// 隐藏主窗口
  Future<void> hideMainWindow() async {
    await windowManager.hide();
    _isMainWindowVisible = false;
  }

  /// 显示悬浮窗
  Future<void> showOverlay() async {
    _isOverlayVisible = true;
    await _updateTrayMenu();
    // 注册悬浮窗全局热键
    await _hotkeyService?.registerOverlayHotkeys();
    onShowOverlay?.call();
  }

  /// 隐藏悬浮窗
  Future<void> hideOverlay() async {
    _isOverlayVisible = false;
    await _updateTrayMenu();
    // 注销悬浮窗全局热键
    await _hotkeyService?.unregisterOverlayHotkeys();
    onHideOverlay?.call();
  }

  /// 切换悬浮窗显示状态
  Future<void> toggleOverlay() async {
    if (_isOverlayVisible) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }

  /// 强制退出程序
  Future<void> forceExitApp() async {
    onExitApp?.call();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// 清理资源
  Future<void> dispose() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
