import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'models.dart';
import 'providers.dart';
import 'screens/home_screen.dart';
import 'screens/overlay_window.dart';
import 'services/settings_service.dart';
import 'services/hotkey_service.dart';
import 'services/window_service.dart';
import 'services/overlay_state_service.dart';

// 全局服务实例（仅桌面端使用）
SettingsService? globalSettingsService;
HotkeyService? globalHotkeyService;
WindowService? globalWindowService;
OverlayStateService? globalOverlayState;
Isar? globalIsar;

// 悬浮窗控制器
WindowController? overlayWindowController;

/// 窗口类型常量
class WindowType {
  static const String main = 'main';
  static const String overlay = 'overlay';
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 检查是否是桌面平台
  if (SettingsService.isDesktop) {
    // 获取当前窗口控制器
    final windowController = await WindowController.fromCurrentEngine();

    // 解析窗口参数
    final arguments = windowController.arguments;
    Map<String, dynamic>? parsedArgs;

    try {
      if (arguments.isNotEmpty) {
        parsedArgs = jsonDecode(arguments);
      }
    } catch (_) {
      parsedArgs = null;
    }

    final windowType = parsedArgs?['type'] ?? WindowType.main;

    // 根据窗口类型启动不同的应用
    if (windowType == WindowType.overlay) {
      // 这是悬浮窗
      await _runOverlayWindow(windowController, parsedArgs);
      return;
    }
  }

  // 主窗口逻辑
  await _runMainWindow();
}

/// 运行主窗口
Future<void> _runMainWindow() async {
  // 1. 初始化 Isar 数据库
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema
    ],
    directory: dir.path,
  );
  globalIsar = isar;

  // 2. 检查并预填充地图数据
  await _initMapData(isar);

  // 3. 初始化桌面端服务
  if (SettingsService.isDesktop) {
    globalSettingsService = SettingsService();
    await globalSettingsService!.init();

    globalHotkeyService = HotkeyService(globalSettingsService!);
    globalWindowService = WindowService(globalSettingsService!);
    globalOverlayState = OverlayStateService();
  }

  runApp(
    // 4. 注入 Riverpod 和 Isar
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const MainApp(),
    ),
  );
}

/// 运行悬浮窗（作为独立窗口）
Future<void> _runOverlayWindow(
    WindowController controller, Map<String, dynamic>? args) async {
  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  // 配置无边框窗口
  const windowOptions = WindowOptions(
    size: Size(600, 750),
    minimumSize: Size(500, 600),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 恢复保存的位置
    final savedX = args?['x'] as double?;
    final savedY = args?['y'] as double?;
    if (savedX != null && savedY != null) {
      await windowManager.setPosition(Offset(savedX, savedY));
    }
    await windowManager.show();
  });

  // 初始化数据库（使用与主窗口相同的数据库）
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema
    ],
    directory: dir.path,
    // 使用默认实例名，与主窗口共享数据库
  );

  // 初始化设置服务
  final settingsService = SettingsService();
  await settingsService.init();

  // 初始化状态服务
  final overlayState = OverlayStateService();

  // 从参数中加载初始地图信息（如果有的话）
  final initialMapId = args?['map_id'] as int?;
  final initialLayerId = args?['layer_id'] as int?;
  if (initialMapId != null && initialLayerId != null) {
    final map = await isar.gameMaps.get(initialMapId);
    final layer = await isar.mapLayers.get(initialLayerId);
    if (map != null && layer != null) {
      overlayState.setCurrentMap(map, layer);
    }
  }

  // 设置窗口方法处理器（接收主窗口的命令）
  await controller.setWindowMethodHandler((call) async {
    switch (call.method) {
      case 'set_map':
        // 从主窗口接收当前地图信息
        final mapId = call.arguments['map_id'] as int?;
        final layerId = call.arguments['layer_id'] as int?;
        if (mapId != null && layerId != null) {
          final map = await isar.gameMaps.get(mapId);
          final layer = await isar.mapLayers.get(layerId);
          if (map != null && layer != null) {
            overlayState.setCurrentMap(map, layer);
          }
        }
        return 'ok';
      case 'clear_map':
        overlayState.clearMap();
        return 'ok';
      case 'close':
        // 保存位置
        final position = await windowManager.getPosition();
        await settingsService.setOverlayPosition(position.dx, position.dy);
        await windowManager.close();
        return 'ok';
      default:
        return null;
    }
  });

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.orange,
          scaffoldBackgroundColor: Colors.transparent,
          useMaterial3: true,
        ),
        home: OverlayWindowApp(
          settingsService: settingsService,
          overlayState: overlayState,
          onClose: () async {
            final position = await windowManager.getPosition();
            await settingsService.setOverlayPosition(position.dx, position.dy);
            await windowManager.close();
          },
          onMinimize: () async {
            await windowManager.hide();
          },
        ),
      ),
    ),
  );
}

/// 数据预填充逻辑：支持多楼层
Future<void> _initMapData(Isar isar) async {
  // 如果数据库为空，则写入默认数据
  if (await isar.gameMaps.count() == 0) {
    print("检测到首次运行，正在写入地图数据...");

    final mapsConfig = [
      {
        "name": "Mirage",
        "key": "mirage",
        "floors": ["mirage.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Inferno",
        "key": "inferno",
        "floors": ["inferno.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Dust 2",
        "key": "dust2",
        "floors": ["dust2.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Overpass",
        "key": "overpass",
        "floors": ["overpass.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Ancient",
        "key": "ancient",
        "floors": ["ancient.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Anubis",
        "key": "anubis",
        "floors": ["anubis.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Train",
        "key": "train",
        "floors": ["train.png"],
        "floorNames": ["Default"]
      },
      {
        "name": "Nuke",
        "key": "nuke",
        "floors": ["nuke_lower.png", "nuke_upper.png"],
        "floorNames": ["B Site (Lower)", "A Site (Upper)"]
      },
      {
        "name": "Vertigo",
        "key": "vertigo",
        "floors": ["vertigo_lower.png", "vertigo_upper.png"],
        "floorNames": ["Level 50 (Lower)", "Level 51 (Upper)"]
      },
    ];

    await isar.writeTxn(() async {
      for (var config in mapsConfig) {
        final key = config['key'] as String;
        final map = GameMap(
          name: config['name'] as String,
          backgroundPath: 'assets/backgrounds/${key}_bg.png',
          iconPath: 'assets/icons/${key}_icon.svg',
        );
        await isar.gameMaps.put(map);

        final floors = config['floors'] as List<String>;
        final floorNames = config['floorNames'] as List<String>;

        for (int i = 0; i < floors.length; i++) {
          final layer = MapLayer(
            name: floorNames[i],
            assetPath: "assets/maps/${floors[i]}",
            sortOrder: i,
          );
          await isar.mapLayers.put(layer);

          // 建立关联
          map.layers.add(layer);
        }
        await map.layers.save();
      }
    });
    print("地图数据写入完成！");
  }
}

/// 主窗口应用
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  void initState() {
    super.initState();
    _initDesktopServices();
  }

  Future<void> _initDesktopServices() async {
    if (!SettingsService.isDesktop) return;

    // 初始化窗口服务
    await globalWindowService?.init();

    // 设置回调
    globalWindowService?.onShowOverlay = _showOverlay;
    globalWindowService?.onHideOverlay = _hideOverlay;
    globalWindowService?.onExitApp = _onExitApp;

    // 初始化快捷键服务
    await globalHotkeyService?.init();

    // 注册全局快捷键处理
    globalHotkeyService?.registerHandler(
      HotkeyAction.toggleOverlay,
      _toggleOverlay,
    );
  }

  Future<void> _toggleOverlay() async {
    if (overlayWindowController != null) {
      // 已存在，关闭它
      try {
        await overlayWindowController!.invokeMethod('close');
      } catch (_) {}
      overlayWindowController = null;
    } else {
      // 不存在，创建新窗口
      await _showOverlay();
    }
  }

  Future<void> _showOverlay() async {
    if (overlayWindowController != null) return;

    // 获取保存的位置
    final savedX = globalSettingsService?.getOverlayX() ?? 100.0;
    final savedY = globalSettingsService?.getOverlayY() ?? 100.0;

    // 获取当前地图信息（如果有的话）
    final currentMap = globalOverlayState?.currentMap;
    final currentLayer = globalOverlayState?.currentLayer;

    // 创建新窗口，在参数中包含当前地图信息
    overlayWindowController = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': WindowType.overlay,
          'x': savedX,
          'y': savedY,
          'map_id': currentMap?.id,
          'layer_id': currentLayer?.id,
        }),
      ),
    );

    await overlayWindowController!.show();

    // 延迟后同步地图状态，确保窗口已准备好
    await Future.delayed(const Duration(milliseconds: 500));
    _syncMapToOverlay();
  }

  Future<void> _hideOverlay() async {
    if (overlayWindowController == null) return;
    try {
      await overlayWindowController!.invokeMethod('close');
    } catch (_) {}
    overlayWindowController = null;
  }

  /// 同步地图信息到悬浮窗
  void _syncMapToOverlay() async {
    if (overlayWindowController == null || globalOverlayState == null) return;

    final map = globalOverlayState!.currentMap;
    final layer = globalOverlayState!.currentLayer;

    if (map != null && layer != null) {
      try {
        await overlayWindowController!.invokeMethod('set_map', {
          'map_id': map.id,
          'layer_id': layer.id,
        });
      } catch (_) {
        // 窗口可能已关闭，忽略错误
      }
    }
  }

  void _onExitApp() {
    _hideOverlay();
    globalHotkeyService?.dispose();
  }

  @override
  void dispose() {
    _hideOverlay();
    globalHotkeyService?.dispose();
    globalWindowService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grenade Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF1B1E23),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141619),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// 悬浮窗应用（独立窗口入口）
class OverlayWindowApp extends StatelessWidget {
  final SettingsService settingsService;
  final OverlayStateService overlayState;
  final VoidCallback onClose;
  final VoidCallback onMinimize;

  const OverlayWindowApp({
    super.key,
    required this.settingsService,
    required this.overlayState,
    required this.onClose,
    required this.onMinimize,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OverlayWindow(
        settingsService: settingsService,
        overlayState: overlayState,
        onClose: onClose,
        onMinimize: onMinimize,
        onStartDrag: () async {
          await windowManager.startDragging();
        },
      ),
    );
  }
}
