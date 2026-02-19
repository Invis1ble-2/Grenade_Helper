import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'models.dart';
import 'models/tag.dart';
import 'models/grenade_tag.dart';
import 'models/map_area.dart';
import 'providers.dart';
import 'screens/home_screen.dart';
import 'screens/overlay_window.dart';
import 'services/settings_service.dart';
import 'services/hotkey_service.dart';
import 'services/window_service.dart';
import 'services/overlay_state_service.dart';
import 'services/update_service.dart';
import 'services/migration_service.dart';
import 'services/tag_service.dart';
import 'themes/christmas_theme.dart';
import 'package:url_launcher/url_launcher.dart';

// 全局服务实例
SettingsService? globalSettingsService;
HotkeyService? globalHotkeyService;
WindowService? globalWindowService;
OverlayStateService? globalOverlayState;
Isar? globalIsar;

// 悬浮窗控制器
WindowController? overlayWindowController;
// 主窗口控制器（用于接收子窗口消息）
WindowController? mainWindowController;

/// 窗口类型常量
class WindowType {
  static const String main = 'main';
  static const String overlay = 'overlay';
}

/// IPC发送命令
void sendOverlayCommand(String command, [Map<String, dynamic>? args]) {
  // debugPrint('[Main] sendOverlayCommand: $command, args: $args');
  if (overlayWindowController != null) {
    // debugPrint('[Main] overlayWindowController is not null, invoking $command');
    overlayWindowController!.invokeMethod(command, args).catchError((e) {
      // 忽略通信错误（例如窗口已关闭）
      debugPrint('[Main] IPC error for $command: $e');
    });
  } else {
    debugPrint('[Main] overlayWindowController is null, cannot send $command');
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端检查
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

/// 解析方向字符串
NavigationDirection? _parseDirection(String? dirStr) {
  switch (dirStr) {
    case 'up':
      return NavigationDirection.up;
    case 'down':
      return NavigationDirection.down;
    case 'left':
      return NavigationDirection.left;
    case 'right':
      return NavigationDirection.right;
    default:
      return null;
  }
}

/// 运行主窗口
Future<void> _runMainWindow() async {
  // 1. 获取数据存储目录
  String dataPath;
  if (SettingsService.isDesktop) {
    dataPath = await SettingsService.getDataPathBeforeInit();
  } else {
    final dir = await getApplicationDocumentsDirectory();
    dataPath = dir.path;
  }

  // 确保数据目录存在
  final dataDir = Directory(dataPath);
  if (!await dataDir.exists()) {
    await dataDir.create(recursive: true);
  }

  // 2. 清理可能残留的锁文件（应用异常关闭时可能产生）
  try {
    final lockFile = File('$dataPath/default.isar-lck');
    if (await lockFile.exists()) {
      debugPrint('[Main] Found stale lock file, removing...');
      await lockFile.delete();
    }
  } catch (e) {
    debugPrint('[Main] Error cleaning lock file: $e');
  }

  // 3. 初始化数据库
  final isar = await Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema,
      ImportHistorySchema,
      ImpactGroupSchema,
      FavoriteFolderSchema,
      TagSchema,
      GrenadeTagSchema,
      MapAreaSchema,
    ],
    directory: dataPath,
  );
  globalIsar = isar;

  // 2.1 预填充地图
  await _initMapData(isar);

  // 2.2 数据迁移
  final migrationService = MigrationService(isar);
  final migratedCount = await migrationService.migrateGrenadeUuids();
  if (migratedCount > 0) {
    debugPrint('已为 $migratedCount 个旧道具生成 UUID');
  }
  final favoriteMigratedCount = await migrationService.migrateFavoriteFolders();
  if (favoriteMigratedCount > 0) {
    debugPrint('已修复 $favoriteMigratedCount 个收藏夹归档数据');
  }
  final tagMigratedCount = await migrationService.migrateTagUuids();
  if (tagMigratedCount > 0) {
    debugPrint('已为 $tagMigratedCount 个标签补齐 UUID');
  }
  final tagService = TagService(isar);
  final ensuredSystemTagSummary = await tagService.ensureSystemTagsForAllMaps(
    cleanupObsoleteSystemTags: true,
  );
  if (ensuredSystemTagSummary.addedTags > 0 ||
      ensuredSystemTagSummary.updatedTags > 0 ||
      ensuredSystemTagSummary.removedObsoleteTags > 0) {
    debugPrint(
      '已校正系统标签：地图${ensuredSystemTagSummary.processedMaps}张，'
      '新增${ensuredSystemTagSummary.addedTags}个，'
      '更新${ensuredSystemTagSummary.updatedTags}个，'
      '清理${ensuredSystemTagSummary.removedObsoleteTags}个',
    );
  }
  if (ensuredSystemTagSummary.keptObsoleteTagsInUse > 0) {
    debugPrint(
      '检测到${ensuredSystemTagSummary.keptObsoleteTagsInUse}个废弃系统标签仍被引用，已跳过清理',
    );
  }

  // 2.5 初始化设置服务（所有平台）
  globalSettingsService = SettingsService();
  await globalSettingsService!.init();

  // 3. 初始化桌面端服务
  if (SettingsService.isDesktop) {
    globalHotkeyService = HotkeyService(globalSettingsService!);
    globalWindowService = WindowService(globalSettingsService!);
    globalOverlayState = OverlayStateService(isar);

    // 连接热键服务和窗口服务
    globalWindowService!.setHotkeyService(globalHotkeyService!);

    // 设置数据库关闭回调
    globalWindowService!.onCloseDatabase = () async {
      if (globalIsar != null && globalIsar!.isOpen) {
        await globalIsar!.close();
        debugPrint('[Main] Isar database closed.');
      }
    };

    // 注册悬浮窗热键处理器（通过 IPC 发送命令给悬浮窗）
    globalHotkeyService!.registerHandler(HotkeyAction.prevGrenade, () {
      sendOverlayCommand('prev_grenade');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.nextGrenade, () {
      sendOverlayCommand('next_grenade');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.prevStep, () {
      sendOverlayCommand('prev_step');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.nextStep, () {
      sendOverlayCommand('next_step');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.toggleSmoke, () {
      sendOverlayCommand('toggle_smoke');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.toggleFlash, () {
      sendOverlayCommand('toggle_flash');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.toggleMolotov, () {
      sendOverlayCommand('toggle_molotov');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.toggleHE, () {
      sendOverlayCommand('toggle_he');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.toggleWallbang, () {
      sendOverlayCommand('toggle_wallbang');
    });
    // 方向键导航 - 改为平滑移动模式 (start/stop)
    globalHotkeyService!.registerHandler(HotkeyAction.navigateUp, () {
      sendOverlayCommand('start_navigation', {'direction': 'up'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.navigateDown, () {
      sendOverlayCommand('start_navigation', {'direction': 'down'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.navigateLeft, () {
      sendOverlayCommand('start_navigation', {'direction': 'left'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.navigateRight, () {
      sendOverlayCommand('start_navigation', {'direction': 'right'});
    });
    // 视频播放控制
    globalHotkeyService!.registerHandler(HotkeyAction.togglePlayPause, () {
      sendOverlayCommand('toggle_play_pause');
    });
    // 速度调节
    globalHotkeyService!.registerHandler(HotkeyAction.increaseNavSpeed, () {
      sendOverlayCommand('increase_nav_speed');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.decreaseNavSpeed, () {
      sendOverlayCommand('decrease_nav_speed');
    });
    // 滚动控制
    globalHotkeyService!.registerHandler(HotkeyAction.scrollUp, () {
      sendOverlayCommand('scroll_up');
    });
    globalHotkeyService!.registerHandler(HotkeyAction.scrollDown, () {
      sendOverlayCommand('scroll_down');
    });
  }

  // 初始化节日主题系统
  initializeSeasonalThemes();

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
  // 1. 确保窗口管理器已初始化
  await windowManager.ensureInitialized();

  // 2. 初始化设置服务 (需要先初始化以获取窗口尺寸)
  final settingsService = SettingsService();
  await settingsService.init();

  // 2. 获取保存的尺寸
  final size = settingsService.getOverlaySizePixels();

  // 3. 配置无边框窗口
  final windowOptions = WindowOptions(
    size: Size(size.$1, size.$2),
    minimumSize: const Size(300, 400),
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
  });

  // 初始化数据库（使用与主窗口相同的数据库和目录）
  final dataPath = await SettingsService.getDataPathBeforeInit();

  // 确保数据目录存在
  final dataDir = Directory(dataPath);
  if (!await dataDir.exists()) {
    await dataDir.create(recursive: true);
  }

  final isar = await Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema,
      ImportHistorySchema,
      ImpactGroupSchema,
      FavoriteFolderSchema,
      TagSchema,
      GrenadeTagSchema,
    ],
    directory: dataPath,
  );

  // 初始化状态服务
  final overlayState = OverlayStateService(isar);
  // 设置初始透明度
  overlayState.setOpacity(settingsService.getOverlayOpacity());
  // 设置初始导航速度
  overlayState.setNavSpeedLevel(settingsService.getOverlayNavSpeed());

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

  // 创建 OverlayWindowApp 的 key，以便在 IPC 中访问其状态
  final overlayAppKey = GlobalKey<OverlayWindowAppState>();

  // 设置窗口方法处理器（接收主窗口的命令）
  await controller.setWindowMethodHandler((call) async {
    switch (call.method) {
      case 'set_map':
        // 从主窗口接收当前地图信息
        final args = call.arguments as Map?;
        final mapId = args?['map_id'] as int?;
        final layerId = args?['layer_id'] as int?;
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
      // === 悬浮窗操作命令（由全局热键触发）===
      case 'prev_grenade':
        overlayState.prevGrenade();
        return 'ok';
      case 'next_grenade':
        overlayState.nextGrenade();
        return 'ok';
      case 'prev_step':
        overlayState.prevStep();
        return 'ok';
      case 'next_step':
        overlayState.nextStep();
        return 'ok';
      case 'toggle_smoke':
        overlayState.toggleFilter(GrenadeType.smoke);
        return 'ok';
      case 'toggle_flash':
        overlayState.toggleFilter(GrenadeType.flash);
        return 'ok';
      case 'toggle_molotov':
        overlayState.toggleFilter(GrenadeType.molotov);
        return 'ok';
      case 'toggle_he':
        overlayState.toggleFilter(GrenadeType.he);
        return 'ok';
      case 'toggle_wallbang':
        overlayState.toggleFilter(GrenadeType.wallbang);
        return 'ok';
      // 方向键导航 - 兼容旧版步进移动指令
      case 'navigate_up':
        overlayState.navigateDirection(NavigationDirection.up);
        return 'ok';
      case 'navigate_down':
        overlayState.navigateDirection(NavigationDirection.down);
        return 'ok';
      case 'navigate_left':
        overlayState.navigateDirection(NavigationDirection.left);
        return 'ok';
      case 'navigate_right':
        overlayState.navigateDirection(NavigationDirection.right);
        return 'ok';
      // 方向键导航 - 新版平滑移动指令 (start/stop)
      case 'start_navigation':
        final args = call.arguments as Map?;
        final dirStr = args?['direction'] as String?;
        final dir = _parseDirection(dirStr);
        debugPrint('[Overlay] start_navigation: $dirStr -> $dir');
        if (dir != null) overlayState.startNavigation(dir);
        return 'ok';
      case 'stop_navigation':
        final args = call.arguments as Map?;
        final dirStr = args?['direction'] as String?;
        final dir = _parseDirection(dirStr);
        debugPrint('[Overlay] stop_navigation: $dirStr -> $dir');
        if (dir != null) overlayState.stopNavigation(dir);
        return 'ok';
      case 'stop_all_navigation':
        debugPrint('[Overlay] stop_all_navigation');
        overlayState.stopAllNavigation();
        return 'ok';
      // 视频播放控制
      case 'toggle_play_pause':
        overlayState.triggerVideoTogglePlayPause();
        return 'ok';
      // 更新透明度（设置界面调整时，直接通过 IPC 传递值）
      case 'update_opacity':
        final opacity = call.arguments?['opacity'] as double? ?? 0.9;
        overlayState.setOpacity(opacity);
        return 'ok';
      // 更新导航速度（设置界面调整时，直接通过 IPC 传递值）
      case 'update_nav_speed':
        // JSON 序列化可能将 int 变成 num，使用 round() 避免精度问题
        final speedValue = call.arguments?['speed'];
        final speed = (speedValue is num) ? speedValue.round() : 3;
        overlayState.setNavSpeedLevel(speed);
        return 'ok';
      // 更新窗口尺寸
      case 'update_size':
        final sizeIndex = call.arguments?['sizeIndex'] as int? ?? 1;
        debugPrint(
            '[Overlay] Received update_size command with index: $sizeIndex');
        overlayState.setOverlaySize(sizeIndex);
        return 'ok';
      // 增加导航速度
      case 'increase_nav_speed':
        overlayState.increaseNavSpeed();
        // 保存到设置
        await settingsService.setOverlayNavSpeed(overlayState.navSpeedLevel);
        return 'ok';
      // 减少导航速度
      case 'decrease_nav_speed':
        overlayState.decreaseNavSpeed();
        // 保存到设置
        await settingsService.setOverlayNavSpeed(overlayState.navSpeedLevel);
        return 'ok';
      // 滚动控制
      case 'scroll_up':
        overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.scrollContent(-300);
        return 'ok';
      case 'scroll_down':
        overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.scrollContent(300);
        return 'ok';
      // 重新加载数据（主窗口修改数据后通知悬浮窗刷新）
      case 'reload_data':
        overlayState.reloadData();
        return 'ok';
      // 重新加载热键配置
      case 'reload_hotkeys':
        try {
          // 从 IPC 接收热键配置，需要处理类型转换
          final rawHotkeys = call.arguments?['hotkeys'];
          debugPrint(
              '[Overlay] reload_hotkeys - rawHotkeys type: ${rawHotkeys.runtimeType}');

          if (rawHotkeys != null) {
            // 将 Map<Object?, Object?> 转换为 Map<String, dynamic>
            final hotkeysJson = Map<String, dynamic>.from(rawHotkeys as Map);

            // 解析热键配置
            final hotkeys = <HotkeyAction, HotkeyConfig>{};
            for (final action in HotkeyAction.values) {
              final actionKey = action.name;
              if (hotkeysJson.containsKey(actionKey)) {
                // 同样需要转换内部的Map
                final configMap =
                    Map<String, dynamic>.from(hotkeysJson[actionKey] as Map);
                hotkeys[action] = HotkeyConfig.fromJson(configMap);
              }
            }
            // 通知 OverlayWindow 更新热键配置和UI
            overlayAppKey.currentState?.overlayWindowKey.currentState
                ?.reloadHotkeys(hotkeys);
            debugPrint(
                '[Overlay] Hotkeys reloaded and UI updated with ${hotkeys.length} keys');
          } else {
            debugPrint('[Overlay] reload_hotkeys called without hotkeys data');
          }
        } catch (e, stack) {
          debugPrint('[Overlay] Error reloading hotkeys: $e');
          debugPrint('[Overlay] Stack trace: $stack');
        }
        return 'ok';
      // 获取悬浮窗可见状态（供主窗口轮询）
      case 'get_visibility':
        final isVisible = await windowManager.isVisible();
        return isVisible ? 'visible' : 'hidden';
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
          key: overlayAppKey,
          settingsService: settingsService,
          overlayState: overlayState,
          onClose: () async {
            final position = await windowManager.getPosition();
            await settingsService.setOverlayPosition(position.dx, position.dy);
            // 直接隐藏悬浮窗
            // 注意：由于 desktop_multi_window 的限制，子窗口无法向主窗口发送消息
            // 热键将在用户下次按 Alt+G 时自动注销
            debugPrint('[Overlay] Hiding overlay window');
            await windowManager.hide();
          },
          onMinimize: () async {
            final position = await windowManager.getPosition();
            await settingsService.setOverlayPosition(position.dx, position.dy);
            // 直接隐藏悬浮窗
            debugPrint('[Overlay] Minimizing overlay window');
            await windowManager.hide();
          },
        ),
      ),
    ),
  );
}

/// 数据预填充逻辑：支持多楼层
Future<void> _initMapData(Isar isar) async {
  // 数据库为空则写入默认数据
  if (await isar.gameMaps.count() == 0) {
    debugPrint("检测到首次运行，正在写入地图数据...");

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
    debugPrint("地图数据写入完成！");
  }
}

/// 主窗口应用
class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  // 用于轮询悬浮窗可见性的定时器
  Timer? _visibilityPollTimer;
  // 用于获取 MaterialApp 内部 context 的 navigatorKey
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDesktopServices();
    // 检查更新（所有平台）- 延迟确保 MaterialApp 已初始化
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _checkForUpdates();
    });
    // 检查赞助提醒（延迟2秒，避免与更新弹窗冲突）
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _checkDonationReminder();
    });
    // 加载全局设置
    _loadGlobalSettings();
  }

  /// 检查是否需要显示赞助提醒
  Future<void> _checkDonationReminder() async {
    if (globalSettingsService == null) return;

    // 增加启动次数
    final launchCount = await globalSettingsService!.incrementLaunchCount();

    // 如果达到10次且未显示过提醒
    if (launchCount >= 10 && !globalSettingsService!.isDonationDialogShown()) {
      await globalSettingsService!.setDonationDialogShown();
      _showDonationDialog();
    }
  }

  /// 显示赞助提醒对话框
  void _showDonationDialog() {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;

    showDialog(
      context: navContext,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.favorite, color: Colors.pink[400]),
            const SizedBox(width: 8),
            const Text('支持我们'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '感谢你使用 Grenade Helper！',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '如果这个应用对你有帮助，欢迎在爱发电支持我们的开发工作，你的支持是我们持续更新的动力！',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.1),
                    Colors.pink.withValues(alpha: 0.1)
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volunteer_activism,
                      color: Colors.pink[400], size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    '爱发电 · 支持作者',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('下次再说'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _launchUrl('https://afdian.com/a/Invis1ble');
            },
            icon: const Icon(Icons.favorite, size: 18),
            label: const Text('前往支持'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink[400],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGlobalSettings() async {
    if (globalSettingsService != null) {
      final savedTheme = globalSettingsService!.getThemeMode();
      ref.read(themeModeProvider.notifier).state = savedTheme;
      // 加载节日主题开关设置
      final seasonalEnabled = globalSettingsService!.getSeasonalThemeEnabled();
      ref.read(seasonalThemeEnabledProvider.notifier).state = seasonalEnabled;
      // 加载地图连线设置
      ref.read(mapLineColorProvider.notifier).state =
          globalSettingsService!.getMapLineColor();
      ref.read(mapLineOpacityProvider.notifier).state =
          globalSettingsService!.getMapLineOpacity();
    }
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

    // 获取主窗口控制器并监听来自其他窗口的消息
    mainWindowController = await WindowController.fromCurrentEngine();
    await mainWindowController?.setWindowMethodHandler((call) async {
      debugPrint('[Main] Received IPC method: ${call.method}');
      if (call.method == 'overlay_closed' || call.method == 'overlay_hidden') {
        // 悬浮窗已隐藏/关闭，更新状态并注销热键
        debugPrint('[Main] Processing overlay_hidden - calling hideOverlay');
        await globalWindowService?.hideOverlay();
        debugPrint('[Main] hideOverlay completed');
      }
      return null;
    });

    // 1秒后预加载悬浮窗
    Future.delayed(const Duration(seconds: 1), () {
      _preloadOverlay();
    });

    // 启动定时器轮询悬浮窗可见性（每500ms检查一次）
    _visibilityPollTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkOverlayVisibility();
    });
  }

  /// 检查悬浮窗可见性，如果隐藏则通知主窗口注销热键
  Future<void> _checkOverlayVisibility() async {
    // 仅当主窗口认为悬浮窗可见时才检查
    if (overlayWindowController == null ||
        globalWindowService == null ||
        !globalWindowService!.isOverlayVisible) {
      return;
    }

    try {
      final result =
          await overlayWindowController!.invokeMethod('get_visibility');
      if (result == 'hidden') {
        debugPrint(
            '[Main] Detected overlay hidden via polling, unregistering hotkeys');
        await globalWindowService!.hideOverlay();
      }
    } catch (e) {
      // 忽略通信错误（悬浮窗可能还没准备好）
    }
  }

  /// 预加载悬浮窗（不显示）
  Future<void> _preloadOverlay() async {
    if (overlayWindowController != null) return;

    final savedX = globalSettingsService?.getOverlayX() ?? 100.0;
    final savedY = globalSettingsService?.getOverlayY() ?? 100.0;
    final currentMap = globalOverlayState?.currentMap;
    final currentLayer = globalOverlayState?.currentLayer;

    overlayWindowController = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true, // 启动时隐藏
        arguments: jsonEncode({
          'type': WindowType.overlay,
          'x': savedX,
          'y': savedY,
          'map_id': currentMap?.id,
          'layer_id': currentLayer?.id,
        }),
      ),
    );

    // 延迟后同步地图状态
    await Future.delayed(const Duration(milliseconds: 500));
    _syncMapToOverlay();
  }

  Future<void> _toggleOverlay() async {
    await globalWindowService?.toggleOverlay();
  }

  Future<void> _showOverlay() async {
    if (overlayWindowController == null) {
      // 如果还没加载（比如刚启动就按快捷键），则现在加载并显示
      await _preloadOverlay();
    }
    // 优先使用无焦点显示，避免抢占游戏焦点
    // 显示并聚焦
    await overlayWindowController!.show();
    // 设置状态（用于轮询检测）
    if (globalWindowService != null) {
      globalWindowService!.isOverlayVisible = true;
    }
    // 注册热键
    await globalHotkeyService?.registerOverlayHotkeys();
  }

  Future<void> _hideOverlay() async {
    if (overlayWindowController == null) return;
    // 仅隐藏，不关闭
    await overlayWindowController!.hide();
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

  void _onExitApp() async {
    // 真正退出时，清理悬浮窗
    if (overlayWindowController != null) {
      try {
        await overlayWindowController!.invokeMethod('close');
      } catch (_) {}
      overlayWindowController = null;
    }
    globalHotkeyService?.dispose();
  }

  @override
  void dispose() {
    _visibilityPollTimer?.cancel();
    _hideOverlay();
    globalHotkeyService?.dispose();
    globalWindowService?.dispose();
    super.dispose();
  }

  /// 检查应用更新
  Future<void> _checkForUpdates() async {
    final updateService = UpdateService();
    final updateInfo = await updateService.checkForUpdate();
    if (updateInfo != null && mounted) {
      _showUpdateDialog(updateInfo, updateService.currentPlatform);
    }
  }

  /// 显示更新提示对话框
  void _showUpdateDialog(UpdateInfo updateInfo, String platform) {
    // 使用 navigatorKey 获取 MaterialApp 内部的 context
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) return;

    showDialog(
      context: navContext,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => PopScope(
        canPop: !updateInfo.forceUpdate,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('发现新版本'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新版本: ${updateInfo.versionName}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text('更新内容:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  updateInfo.content.isEmpty ? '优化和修复' : updateInfo.content,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              const Text('请选择下载方式:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
          actions: [
            // 稍后提醒（仅在非强制更新时显示）
            if (!updateInfo.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('稍后提醒'),
              ),
            // 网盘下载
            PopupMenuButton<String>(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_download, size: 18),
                    SizedBox(width: 4),
                    Text('网盘下载'),
                    Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
              onSelected: (url) {
                _launchUrl(url);
                // 不关闭对话框，让用户可以继续选择其他下载方式
              },
              itemBuilder: (context) => DownloadLinks.panLinks.entries
                  .map((e) => PopupMenuItem(
                        value: e.value,
                        child: Text(e.key),
                      ))
                  .toList(),
            ),
            const SizedBox(width: 4),
            // 官方下载
            ElevatedButton.icon(
              onPressed: () {
                _launchUrl(DownloadLinks.getOfficialUrl(platform));
                // 不关闭对话框，让用户可以继续选择其他下载方式
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('官方下载'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开 URL
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final seasonalTheme = ref.watch(activeSeasonalThemeProvider);

    // 基础深色主题
    ThemeData baseDarkTheme = ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.orange,
      colorScheme: ColorScheme.dark(
        primary: Colors.orange,
        secondary: Colors.orangeAccent,
      ),
      scaffoldBackgroundColor: const Color(0xFF1B1E23),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF141619),
        elevation: 0,
      ),
    );

    // 基础浅色主题
    ThemeData baseLightTheme = ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.blue,
      colorScheme: ColorScheme.light(
        primary: Colors.blue,
        secondary: Colors.blueAccent,
        surface: const Color.fromARGB(255, 248, 239, 225),
        onSurface: const Color(0xFF1A1A1A),
      ),
      scaffoldBackgroundColor: const Color.fromARGB(255, 248, 240, 227),
      cardColor: const Color.fromARGB(255, 248, 240, 227),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color.fromARGB(255, 255, 239, 213),
        foregroundColor: Color.fromARGB(255, 5, 5, 5),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF333333)),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF1A1A1A)),
        bodyMedium: TextStyle(color: Color(0xFF333333)),
        bodySmall: TextStyle(color: Color(0xFF555555)),
        titleLarge:
            TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Color(0xFF1A1A1A)),
        labelLarge: TextStyle(color: Color(0xFF1A1A1A)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF333333)),
      dividerColor: const Color(0xFFE0DDD8),
    );

    // 如果有激活的节日主题，应用节日配色
    ThemeData darkTheme = baseDarkTheme;
    ThemeData lightTheme = baseLightTheme;

    if (seasonalTheme != null) {
      final darkColorScheme = seasonalTheme.getDarkColorScheme();
      final lightColorScheme = seasonalTheme.getLightColorScheme();

      darkTheme = baseDarkTheme.copyWith(
        colorScheme: darkColorScheme,
        primaryColor: darkColorScheme.primary,
        scaffoldBackgroundColor: darkColorScheme.surface,
        appBarTheme: baseDarkTheme.appBarTheme.copyWith(
          backgroundColor: darkColorScheme.surface,
        ),
      );

      lightTheme = baseLightTheme.copyWith(
        colorScheme: lightColorScheme,
        primaryColor: lightColorScheme.primary,
        scaffoldBackgroundColor: lightColorScheme.surface,
        appBarTheme: baseLightTheme.appBarTheme.copyWith(
          backgroundColor: lightColorScheme.primaryContainer,
          foregroundColor: lightColorScheme.onPrimaryContainer,
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Grenade Helper',
      debugShowCheckedModeBanner: false,
      themeMode: intToThemeMode(themeMode),
      darkTheme: darkTheme,
      theme: lightTheme,
      home: const HomeScreen(),
    );
  }
}

/// 悬浮窗应用（独立窗口入口）
class OverlayWindowApp extends StatefulWidget {
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
  State<OverlayWindowApp> createState() => OverlayWindowAppState();
}

class OverlayWindowAppState extends State<OverlayWindowApp> {
  final GlobalKey<OverlayWindowState> overlayWindowKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OverlayWindow(
        key: overlayWindowKey,
        settingsService: widget.settingsService,
        overlayState: widget.overlayState,
        onClose: widget.onClose,
        onMinimize: widget.onMinimize,
        onStartDrag: () async {
          await windowManager.startDragging();
        },
      ),
    );
  }
}
