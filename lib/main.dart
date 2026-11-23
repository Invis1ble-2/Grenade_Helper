import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'data/builtin_maps.dart';
import 'models.dart';
import 'models/overlay_snapshot.dart';
import 'models/tag.dart';
import 'models/grenade_tag.dart';
import 'models/map_area.dart';
import 'providers.dart';
import 'screens/app_shell.dart';
import 'screens/overlay_window.dart';
import 'services/settings_service.dart';
import 'services/hotkey_service.dart';
import 'services/window_service.dart';
import 'services/overlay_ipc_client.dart';
import 'services/overlay_ipc_server.dart';
import 'services/overlay_state_service.dart';
import 'services/update_service.dart';
import 'services/migration_service.dart';
import 'services/tag_service.dart';
import 'theme/app_design_system.dart';
import 'widgets/grenade_type_icon.dart';
import 'package:url_launcher/url_launcher.dart';

// 全局服务实例
SettingsService? globalSettingsService;
HotkeyService? globalHotkeyService;
WindowService? globalWindowService;
OverlayIpcServer? globalOverlayServer;
Isar? globalIsar;

void sendOverlayCommand(String command, [Map<String, dynamic>? args]) {
  globalOverlayServer?.sendCommand(command, args);
}

void setOverlayActiveMap(GameMap map, MapLayer layer) {
  globalOverlayServer?.setActiveMap(map, layer);
}

void clearOverlayActiveMap() {
  globalOverlayServer?.clearActiveMap();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    fvp.registerWith(options: {
      'platforms': ['windows'],
    });
  }

  if (args.contains('--overlay')) {
    await _runOverlayProcess(args);
    return;
  }

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

  // 2. 初始化数据库
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
  final tagMigrationSummary = await migrationService.migrateTagUuids();
  if (tagMigrationSummary.migratedCount > 0) {
    debugPrint('已为 ${tagMigrationSummary.migratedCount} 个标签补齐 UUID');
    for (final detail in tagMigrationSummary.details) {
      debugPrint(
        '  标签UUID补齐：地图=${detail.mapName}(id=${detail.mapId})，'
        '标签=${detail.tagName}(id=${detail.tagId})，'
        '维度=${detail.dimensionName}，'
        '系统标签=${detail.isSystem}，'
        '原因=${detail.reason}',
      );
      debugPrint(
        '  UUID：旧=[${detail.oldUuid.isEmpty ? "空" : detail.oldUuid}] -> '
        '新=[${detail.newUuid}]',
      );
    }
  }
  final tagService = TagService(isar);
  final ensuredSystemTagSummary = await tagService.ensureSystemTagsForAllMaps(
    cleanupObsoleteSystemTags: true,
  );
  String summarizeRefs(List<String> refs, {int maxItems = 5}) {
    if (refs.isEmpty) return '无';
    final visible = refs.take(maxItems).join('，');
    if (refs.length <= maxItems) return visible;
    return '$visible 等${refs.length}项';
  }

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
    for (final detail in ensuredSystemTagSummary.keptObsoleteTagDetails) {
      debugPrint(
        '  来源：地图=${detail.mapName}(id=${detail.mapId})，'
        '标签=${detail.tagName}(id=${detail.tagId})，'
        '维度=${detail.dimensionName}，'
        'UUID=${detail.tagUuid}',
      );
      debugPrint(
        '  引用：道具${detail.grenadeRefs.length}个'
        ' [${summarizeRefs(detail.grenadeRefs)}]；'
        '区域${detail.areaRefs.length}个'
        ' [${summarizeRefs(detail.areaRefs)}]',
      );
    }
  }
  final defaultAreaSummary =
      await tagService.initializeBuiltinAreaMetadataForAllMaps();
  if (defaultAreaSummary.addedTags > 0 ||
      defaultAreaSummary.updatedTags > 0 ||
      defaultAreaSummary.addedAreas > 0 ||
      defaultAreaSummary.updatedAreas > 0 ||
      defaultAreaSummary.removedDuplicateAreas > 0) {
    debugPrint(
      '已初始化默认区域：地图${defaultAreaSummary.processedMaps}张，'
      '区域标签新增${defaultAreaSummary.addedTags}个，'
      '区域标签更新${defaultAreaSummary.updatedTags}个，'
      '区域新增${defaultAreaSummary.addedAreas}个，'
      '区域更新${defaultAreaSummary.updatedAreas}个，'
      '去重${defaultAreaSummary.removedDuplicateAreas}个',
    );
    for (final detail in defaultAreaSummary.addedTagDetails) {
      debugPrint(
        '  区域标签新增：地图=${detail.mapName}(id=${detail.mapId})，'
        '标签=${detail.tagName}，'
        'UUID=${detail.newTagUuid}，'
        '颜色=${detail.newColorValue}',
      );
    }
    for (final detail in defaultAreaSummary.updatedTagDetails) {
      debugPrint(
        '  区域标签更新：地图=${detail.mapName}(id=${detail.mapId})，'
        '标签=${detail.tagName}(id=${detail.tagId ?? -1})，'
        '原因=${detail.reasonSummary}',
      );
      debugPrint(
        '  变化：UUID=[${detail.oldTagUuid.isEmpty ? "空" : detail.oldTagUuid}] -> '
        '[${detail.newTagUuid}]；'
        '颜色=[${detail.oldColorValue}] -> [${detail.newColorValue}]',
      );
    }
  }

  // 2.5 初始化设置服务（所有平台）
  globalSettingsService = SettingsService();
  await globalSettingsService!.init();
  GrenadeTypeIcon.useLegacy = globalSettingsService!.getMapMarkerUseEmoji();

  // 3. 初始化桌面端服务
  if (SettingsService.isDesktop) {
    globalHotkeyService = HotkeyService(globalSettingsService!);
    globalWindowService = WindowService(globalSettingsService!);
    globalOverlayServer = OverlayIpcServer(
      isar: isar,
      settingsService: globalSettingsService!,
      onOverlayHidden: () {
        if (globalWindowService?.isOverlayVisible == true) {
          unawaited(globalWindowService!.hideOverlay());
        }
      },
    );

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
    globalHotkeyService!.registerKeyUpHandler(HotkeyAction.navigateUp, () {
      sendOverlayCommand('stop_navigation', {'direction': 'up'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.navigateDown, () {
      sendOverlayCommand('start_navigation', {'direction': 'down'});
    });
    globalHotkeyService!.registerKeyUpHandler(HotkeyAction.navigateDown, () {
      sendOverlayCommand('stop_navigation', {'direction': 'down'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.navigateLeft, () {
      sendOverlayCommand('start_navigation', {'direction': 'left'});
    });
    globalHotkeyService!.registerKeyUpHandler(HotkeyAction.navigateLeft, () {
      sendOverlayCommand('stop_navigation', {'direction': 'left'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.navigateRight, () {
      sendOverlayCommand('start_navigation', {'direction': 'right'});
    });
    globalHotkeyService!.registerKeyUpHandler(HotkeyAction.navigateRight, () {
      sendOverlayCommand('stop_navigation', {'direction': 'right'});
    });
    globalHotkeyService!.registerHandler(HotkeyAction.hideOverlay, () {
      unawaited(globalWindowService!.hideOverlay());
    });
    // 视频播放控制
    globalHotkeyService!.registerHandler(HotkeyAction.togglePlayPause, () {
      sendOverlayCommand('toggle_play_pause');
    });
    globalHotkeyService!
        .registerHandler(HotkeyAction.toggleMediaFullscreenPreview, () {
      sendOverlayCommand('toggle_media_fullscreen_preview');
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

/// 运行悬浮窗独立子进程
Future<void> _runOverlayProcess(List<String> args) async {
  final ipcArgs = OverlayIpcClient.parseArgs(args);
  if (ipcArgs == null) {
    exit(0);
  }

  final client = OverlayIpcClient(port: ipcArgs.port, token: ipcArgs.token);
  client.onDisconnected = () => exit(0);

  late final OverlayInitConfig initConfig;
  try {
    initConfig = await client.connectAndAwaitInit();
  } catch (_) {
    exit(0);
  }

  GrenadeTypeIcon.useLegacy = initConfig.useLegacyIcons;

  await windowManager.ensureInitialized();
  final size = SettingsService.calculateSizePixels(initConfig.sizeIndex);

  const windowOptions = WindowOptions(
    minimumSize: Size(300, 400),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setSize(Size(size.$1, size.$2));
    await windowManager.setPosition(Offset(initConfig.x, initConfig.y));
  });

  final overlayState = OverlayStateService();
  overlayState.setOpacity(initConfig.opacity);
  overlayState.setNavSpeedLevel(initConfig.navSpeedLevel);
  if (initConfig.mapSnapshot != null) {
    overlayState.applyMapSnapshot(initConfig.mapSnapshot!);
  }

  final overlayAppKey = GlobalKey<OverlayWindowAppState>();
  final isOverlayVisibleNotifier = ValueNotifier<bool>(false);
  const overlayWindowChannel = MethodChannel('grenade_helper/overlay_window');

  Future<void> showNativeOverlay() async {
    if (Platform.isWindows) {
      await overlayWindowChannel.invokeMethod<void>('showNoActivate');
    } else {
      await windowManager.show(inactive: true);
    }
  }

  Future<void> hideNativeOverlay() async {
    if (Platform.isWindows) {
      await overlayWindowChannel.invokeMethod<void>('hide');
    } else {
      await windowManager.hide();
    }
  }

  Future<void> persistOverlayBounds() async {
    final preferredPosition = overlayAppKey
        .currentState?.overlayWindowKey.currentState?.persistedWindowPosition;
    final position = preferredPosition ?? (await windowManager.getBounds()).topLeft;
    client.sendEvent('bounds_changed', {
      'x': position.dx,
      'y': position.dy,
    });
  }

  Future<void> pauseOverlayVideoPlayback() async {
    await overlayAppKey.currentState?.overlayWindowKey.currentState
        ?.pauseActiveVideoPlayback();
  }

  bool blocksDirectionalNavigation() {
    return overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.blocksDirectionalNavigation ==
        true;
  }

  Future<void> hideOverlay({bool notifyMain = false}) async {
    if (!isOverlayVisibleNotifier.value) return;
    await pauseOverlayVideoPlayback();
    await overlayAppKey.currentState?.overlayWindowKey.currentState
        ?.exitFullscreenPreviewIfNeeded();
    await persistOverlayBounds();
    overlayState.stopAllNavigation();
    isOverlayVisibleNotifier.value = false;
    await hideNativeOverlay();
    if (notifyMain) {
      client.sendEvent('hidden');
    }
  }

  Future<void> showOverlay() async {
    isOverlayVisibleNotifier.value = true;
    await showNativeOverlay();
  }

  client.onCommand = (command, cmdArgs) async {
    switch (command) {
      case 'set_map_snapshot':
        if (cmdArgs != null) {
          overlayState.applyMapSnapshot(OverlayMapSnapshot.fromJson(cmdArgs));
        }
        break;
      case 'clear_map':
        overlayState.clearMap();
        break;
      case 'show_overlay':
        await showOverlay();
        break;
      case 'hide_overlay':
        await hideOverlay();
        break;
      case 'close':
        await pauseOverlayVideoPlayback();
        await overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.exitFullscreenPreviewIfNeeded();
        if (isOverlayVisibleNotifier.value) {
          await persistOverlayBounds();
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await client.close();
        exit(0);
      case 'prev_grenade':
        overlayState.prevGrenade();
        break;
      case 'next_grenade':
        overlayState.nextGrenade();
        break;
      case 'prev_step':
        overlayState.prevStep();
        break;
      case 'next_step':
        overlayState.nextStep();
        break;
      case 'toggle_smoke':
        overlayState.toggleFilter(GrenadeType.smoke);
        break;
      case 'toggle_flash':
        overlayState.toggleFilter(GrenadeType.flash);
        break;
      case 'toggle_molotov':
        overlayState.toggleFilter(GrenadeType.molotov);
        break;
      case 'toggle_he':
        overlayState.toggleFilter(GrenadeType.he);
        break;
      case 'toggle_wallbang':
        overlayState.toggleFilter(GrenadeType.wallbang);
        break;
      case 'navigate_up':
        if (!blocksDirectionalNavigation()) {
          overlayState.navigateDirection(NavigationDirection.up);
        }
        break;
      case 'navigate_down':
        if (!blocksDirectionalNavigation()) {
          overlayState.navigateDirection(NavigationDirection.down);
        }
        break;
      case 'navigate_left':
        if (!blocksDirectionalNavigation()) {
          overlayState.navigateDirection(NavigationDirection.left);
        }
        break;
      case 'navigate_right':
        if (!blocksDirectionalNavigation()) {
          overlayState.navigateDirection(NavigationDirection.right);
        }
        break;
      case 'start_navigation':
        final dir = _parseDirection(cmdArgs?['direction'] as String?);
        if (blocksDirectionalNavigation()) {
          overlayState.stopAllNavigation();
        } else if (dir != null) {
          overlayState.startNavigation(dir);
        }
        break;
      case 'stop_navigation':
        final dir = _parseDirection(cmdArgs?['direction'] as String?);
        if (dir != null) overlayState.stopNavigation(dir);
        break;
      case 'stop_all_navigation':
        overlayState.stopAllNavigation();
        break;
      case 'toggle_play_pause':
        overlayState.triggerVideoTogglePlayPause();
        break;
      case 'toggle_media_fullscreen_preview':
        await overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.toggleMediaFullscreenPreview();
        break;
      case 'update_opacity':
        final opacity = (cmdArgs?['opacity'] as num?)?.toDouble() ?? 0.9;
        overlayState.setOpacity(opacity);
        break;
      case 'update_nav_speed':
        final speed = (cmdArgs?['speed'] as num?)?.round() ?? 3;
        overlayState.setNavSpeedLevel(speed);
        break;
      case 'update_size':
        final sizeIndex = (cmdArgs?['sizeIndex'] as num?)?.toInt() ?? 1;
        await overlayState.setOverlaySize(sizeIndex);
        break;
      case 'increase_nav_speed':
        overlayState.increaseNavSpeed();
        client.sendEvent('nav_speed_changed', {
          'speed': overlayState.navSpeedLevel,
        });
        break;
      case 'decrease_nav_speed':
        overlayState.decreaseNavSpeed();
        client.sendEvent('nav_speed_changed', {
          'speed': overlayState.navSpeedLevel,
        });
        break;
      case 'scroll_up':
        overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.scrollContent(-300);
        break;
      case 'scroll_down':
        overlayAppKey.currentState?.overlayWindowKey.currentState
            ?.scrollContent(300);
        break;
      case 'set_legacy_icons':
        GrenadeTypeIcon.useLegacy = cmdArgs?['value'] == true;
        overlayState.refresh();
        break;
      case 'reload_hotkeys':
        final rawHotkeys = cmdArgs?['hotkeys'];
        if (rawHotkeys is Map) {
          final hotkeys = OverlayInitConfig.decodeHotkeys(rawHotkeys);
          overlayAppKey.currentState?.overlayWindowKey.currentState
              ?.reloadHotkeys(hotkeys);
        }
        break;
    }
  };

  runApp(
    ExcludeSemantics(
      excluding: !kIsWeb && Platform.isWindows,
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
          initialHotkeys: initConfig.hotkeys,
          overlayState: overlayState,
          isVisibleListenable: isOverlayVisibleNotifier,
          onClose: () => hideOverlay(notifyMain: true),
          onMinimize: () => hideOverlay(notifyMain: true),
        ),
      ),
    ),
  );

  client.sendEvent('ready');
}

/// 数据预填充逻辑：支持多楼层
Future<void> _initMapData(Isar isar) async {
  final isFirstRun = await isar.gameMaps.count() == 0;
  if (isFirstRun) {
    debugPrint("检测到首次运行，正在写入地图数据...");
  }

  final addedCount = await _ensureBuiltinMaps(isar);

  if (isFirstRun) {
    debugPrint("地图数据写入完成！");
  } else if (addedCount > 0) {
    debugPrint("已补充官方地图：$addedCount 张");
  }
}

Future<int> _ensureBuiltinMaps(Isar isar) async {
  final existingMaps = await isar.gameMaps.where().findAll();
  final existingByKey = <String, List<GameMap>>{};
  for (final map in existingMaps) {
    final config = findBuiltinMapConfig(map);
    if (config != null) existingByKey.putIfAbsent(config.key, () => []).add(map);
  }

  final mapsToMigrate = <GameMap>[];
  final configsToAdd = <BuiltinMapConfig>[];
  for (final config in builtinMapsConfig) {
    final matched = existingByKey[config.key];
    if (matched != null && matched.isNotEmpty) {
      for (final existing in matched) {
        final migratedBg =
            normalizeLegacyBuiltinAssetPath(existing.backgroundPath);
        if (migratedBg != existing.backgroundPath) {
          existing.backgroundPath = migratedBg;
          mapsToMigrate.add(existing);
        }
      }
      continue;
    }
    configsToAdd.add(config);
  }

  if (mapsToMigrate.isEmpty && configsToAdd.isEmpty) {
    return 0;
  }

  var addedCount = 0;
  await isar.writeTxn(() async {
    if (mapsToMigrate.isNotEmpty) {
      await isar.gameMaps.putAll(mapsToMigrate);
    }
    for (final config in configsToAdd) {
      final map = GameMap(
        name: config.name,
        backgroundPath: config.backgroundPath,
        iconPath: config.iconPath,
      );
      await isar.gameMaps.put(map);

      for (int i = 0; i < config.floors.length; i++) {
        final layer = MapLayer(
          name: config.floorNames[i],
          assetPath: 'assets/maps/${config.floors[i]}',
          sortOrder: i,
        );
        await isar.mapLayers.put(layer);
        map.layers.add(layer);
      }
      await map.layers.save();
      addedCount++;
    }
  });

  return addedCount;
}

/// 主窗口应用
class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
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
    // 加载全局设置（延后到首帧后，避免在 build 生命周期内修改 provider）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadGlobalSettings();
      }
    });
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
  }

  Future<void> _toggleOverlay() async {
    await globalWindowService?.toggleOverlay();
  }

  Future<void> _showOverlay() async {
    try {
      await globalOverlayServer?.showOverlay();
    } catch (e) {
      debugPrint('[Main] Failed to show overlay: $e');
      await globalWindowService?.hideOverlay();
      return;
    }
    if (globalWindowService != null) {
      globalWindowService!.isOverlayVisible = true;
    }
    await globalHotkeyService?.registerOverlayHotkeys();
  }

  void _hideOverlay() {
    globalOverlayServer?.hideOverlay();
  }

  Future<void> _onExitApp() async {
    await globalOverlayServer?.dispose();
    globalOverlayServer = null;
    globalHotkeyService?.dispose();
  }

  @override
  void dispose() {
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

    return ExcludeSemantics(
      excluding: !kIsWeb && Platform.isWindows,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Grenade Helper',
        debugShowCheckedModeBanner: false,
        themeMode: intToThemeMode(themeMode),
        darkTheme: AppTheme.dark(),
        theme: AppTheme.light(),
        home: AppShell(
          settingsService: globalSettingsService,
          onHotkeyChanged: (action, config) async {
            await globalHotkeyService?.updateHotkey(action, config);
          },
          onHotkeysReset: () async {
            await globalHotkeyService?.reloadFromSettings();
          },
        ),
      ),
    );
  }
}

/// 悬浮窗应用（独立窗口入口）
class OverlayWindowApp extends StatefulWidget {
  final Map<HotkeyAction, HotkeyConfig> initialHotkeys;
  final OverlayStateService overlayState;
  final ValueListenable<bool> isVisibleListenable;
  final AsyncCallback onClose;
  final AsyncCallback onMinimize;

  const OverlayWindowApp({
    super.key,
    required this.initialHotkeys,
    required this.overlayState,
    required this.isVisibleListenable,
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
      body: ValueListenableBuilder<bool>(
        valueListenable: widget.isVisibleListenable,
        builder: (context, isVisible, _) {
          return OverlayWindow(
            key: overlayWindowKey,
            initialHotkeys: widget.initialHotkeys,
            overlayState: widget.overlayState,
            isVisible: isVisible,
            onClose: widget.onClose,
            onMinimize: widget.onMinimize,
            onStartDrag: () async {
              await windowManager.startDragging();
            },
          );
        },
      ),
    );
  }
}
