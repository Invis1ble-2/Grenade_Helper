import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:photo_view/photo_view.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models.dart';
import '../providers.dart';
import '../main.dart';
import '../config/feature_flags.dart';
import '../spawn_point_data.dart';
import '../widgets/joystick_widget.dart';
import '../services/data_service.dart';
import '../services/favorite_folder_service.dart';
import '../services/tag_service.dart';
import '../models/tag.dart';
import '../models/grenade_tag.dart';
import '../models/map_area.dart';
import 'grenade_detail_screen.dart';
import 'impact_point_picker_screen.dart';
import 'tag_manager_screen.dart';
import 'area_manager_screen.dart';

// 状态管理

final isEditModeProvider = StateProvider.autoDispose<bool>((ref) => false);
final selectedLayerIndexProvider = StateProvider.autoDispose<int>((ref) => 0);
final selectedTagIdsProvider = StateProvider.autoDispose<Set<int>>((ref) => {});

final _grenadeTagRevisionProvider =
    StreamProvider.autoDispose<int>((ref) async* {
  final isar = ref.watch(isarProvider);
  int revision = 0;
  yield revision;
  await for (final _ in isar.grenadeTags.watchLazy()) {
    revision++;
    yield revision;
  }
});

final _filteredGrenadesProvider =
    StreamProvider.autoDispose.family<List<Grenade>, int>((ref, layerId) {
  final isar = ref.watch(isarProvider);
  final teamFilter = ref.watch(teamFilterProvider);
  final onlyFav = ref.watch(onlyFavoritesProvider);
  final selectedTypes = ref.watch(typeFilterProvider);
  final selectedTagIds = ref.watch(selectedTagIdsProvider);
  ref.watch(_grenadeTagRevisionProvider);

  return isar.grenades
      .filter()
      .layer((q) => q.idEqualTo(layerId))
      .watch(fireImmediately: true)
      .asyncMap((allGrenades) async {
    var filtered = allGrenades.where((g) {
      if (!selectedTypes.contains(g.type)) return false;
      if (teamFilter == TeamType.onlyAll && g.team != TeamType.all) {
        return false;
      }
      if (teamFilter == TeamType.ct && g.team != TeamType.ct) return false;
      if (teamFilter == TeamType.t && g.team != TeamType.t) return false;
      if (onlyFav && !g.isFavorite) return false;
      return true;
    }).toList();

    if (kEnableGrenadeTags && selectedTagIds.isNotEmpty) {
      final matchedGrenadeIds = <int>{};
      for (final tagId in selectedTagIds) {
        final links =
            await isar.grenadeTags.filter().tagIdEqualTo(tagId).findAll();
        for (final link in links) {
          matchedGrenadeIds.add(link.grenadeId);
        }
      }
      filtered =
          filtered.where((g) => matchedGrenadeIds.contains(g.id)).toList();
    }

    return filtered;
  });
});

// 聚合模型
class GrenadeCluster {
  final double xRatio;
  final double yRatio;
  final List<Grenade> grenades;

  GrenadeCluster(
      {required this.xRatio, required this.yRatio, required this.grenades});

  int get primaryType => grenades.first.type;
  int get primaryTeam {
    final hasct = grenades.any((g) => g.team == TeamType.ct);
    final hast = grenades.any((g) => g.team == TeamType.t);
    if (hasct && hast) return TeamType.all;
    if (hasct) return TeamType.ct;
    if (hast) return TeamType.t;
    return TeamType.all;
  }

  bool get hasNewImport => grenades.any((g) => g.isNewImport);
  bool get hasFavorite => grenades.any((g) => g.isFavorite);

  // 检查多类型
  bool get hasMultipleTypes {
    if (grenades.length <= 1) return false;
    final firstType = grenades.first.type;
    return grenades.any((g) => g.type != firstType);
  }
}

List<GrenadeCluster> clusterGrenades(List<Grenade> grenades,
    {double threshold = 0.0}) {
  // 禁用合并
  if (grenades.isEmpty) return [];
  final List<GrenadeCluster> clusters = [];
  final List<Grenade> remaining = List.from(grenades);

  while (remaining.isNotEmpty) {
    final first = remaining.removeAt(0);
    final nearby = <Grenade>[first];
    remaining.removeWhere((g) {
      final dx = (g.xRatio - first.xRatio).abs();
      final dy = (g.yRatio - first.yRatio).abs();
      if ((dx * dx + dy * dy) < threshold * threshold) {
        nearby.add(g);
        return true;
      }
      return false;
    });
    final avgX =
        nearby.map((g) => g.xRatio).reduce((a, b) => a + b) / nearby.length;
    final avgY =
        nearby.map((g) => g.yRatio).reduce((a, b) => a + b) / nearby.length;
    clusters.add(GrenadeCluster(xRatio: avgX, yRatio: avgY, grenades: nearby));
  }
  return clusters;
}

List<GrenadeCluster> clusterGrenadesByImpact(List<Grenade> grenades,
    {double threshold = 0.0}) {
  if (grenades.isEmpty) return [];
  final List<GrenadeCluster> clusters = [];
  final List<Grenade> remaining = grenades
      .where((g) => g.impactXRatio != null && g.impactYRatio != null)
      .toList();

  while (remaining.isNotEmpty) {
    final first = remaining.removeAt(0);
    final nearby = <Grenade>[first];
    remaining.removeWhere((g) {
      final dx = (g.impactXRatio! - first.impactXRatio!).abs();
      final dy = (g.impactYRatio! - first.impactYRatio!).abs();
      if ((dx * dx + dy * dy) < threshold * threshold) {
        nearby.add(g);
        return true;
      }
      return false;
    });
    final avgX = nearby.map((g) => g.impactXRatio!).reduce((a, b) => a + b) /
        nearby.length;
    final avgY = nearby.map((g) => g.impactYRatio!).reduce((a, b) => a + b) /
        nearby.length;
    clusters.add(GrenadeCluster(xRatio: avgX, yRatio: avgY, grenades: nearby));
  }
  return clusters;
}

class MapScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  const MapScreen({super.key, required this.gameMap});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const int _grenadeCreateModeTap = 0;
  static const int _grenadeCreateModeLongPress = 1;
  static const double _allMapListPanelCollapsedHeight = 60;
  static const double _allMapListPanelDefaultHeight = 260;
  static const double _allMapListPanelMinExpandedHeight = 180;

  Offset? _tempTapPosition;
  GrenadeCluster? _draggingCluster;
  Offset? _dragOffset;
  Offset? _dragAnchorOffset; // 锚点偏移
  bool _isMovingCluster = false;
  Grenade? _movingSingleGrenade; // 单个移动
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey(); // GlobalKey
  bool _isSpawnSidebarExpanded = true; // 侧边栏状态
  bool _isImpactMode = false; // 爆点模式

  // 摇杆状态
  GrenadeCluster? _joystickCluster; // 选中标点
  Offset? _joystickOriginalOffset; // 原始位置

  // 爆点摇杆
  GrenadeCluster? _joystickImpactCluster; // 选中爆点
  Offset? _joystickImpactOriginalOffset; // 原始爆点
  Offset? _impactJoystickDragOffset; // 实时爆点

  // 爆点显示
  GrenadeCluster? _selectedClusterForImpact; // 选中点位

  // 爆点拖动
  GrenadeCluster? _draggingImpactCluster; // 拖动Cluster
  Offset? _impactDragOffset; // 拖动位置
  Offset? _impactDragAnchorOffset; // 拖动锚点
  Grenade? _movingSingleImpactGrenade; // 单个爆点移动
  int? _selectedImpactTypeFilter; // 爆点模式下选中的道具类型过滤
  final ValueNotifier<double> _allMapListPanelHeightNotifier =
      ValueNotifier(_allMapListPanelDefaultHeight);
  final TextEditingController _allMapListSearchController =
      TextEditingController();
  String _allMapListSearchQuery = '';
  late final FavoriteFolderService _favoriteFolderService;
  late final Stream<List<FolderWithGrenades>> _mapFavoritesStream;
  StreamSubscription<void>? _grenadeWatchSubscription;
  List<Grenade> _cachedAllMapGrenades = [];
  List<({Grenade grenade, MapLayer layer})> _cachedAllMapGrenadeEntries = [];
  List<Grenade>? _throwClusterCacheSource;
  double? _throwClusterCacheThreshold;
  List<GrenadeCluster> _throwClusterCache = const [];
  List<Grenade>? _impactClusterCacheSource;
  double? _impactClusterCacheThreshold;
  List<GrenadeCluster> _impactClusterCache = const [];

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    final isar = ref.read(isarProvider);
    _favoriteFolderService = FavoriteFolderService(isar);
    _mapFavoritesStream =
        _favoriteFolderService.watchMapFavorites(widget.gameMap.id);
    _refreshAllMapGrenadeCache(notify: false);
    _grenadeWatchSubscription = isar.grenades.watchLazy().listen((_) {
      if (!mounted) return;
      _refreshAllMapGrenadeCache();
    });
    widget.gameMap.layers.loadSync();
    final defaultIndex = widget.gameMap.layers.length > 1 ? 1 : 0;
    Future.microtask(() {
      ref.read(selectedLayerIndexProvider.notifier).state = defaultIndex;
      // 通知悬浮窗
      _updateOverlayState(defaultIndex);
    });
  }

  @override
  void dispose() {
    _grenadeWatchSubscription?.cancel();
    _allMapListPanelHeightNotifier.dispose();
    _allMapListSearchController.dispose();
    _photoViewController.dispose();
    // 清除悬浮窗
    globalOverlayState?.clearMap();
    // 通知清除
    _notifyOverlayWindowClearMap();
    super.dispose();
  }

  /// 比较Cluster
  bool _isSameCluster(GrenadeCluster? c1, GrenadeCluster? c2) {
    if (c1 == null || c2 == null) return false;
    if (c1 == c2) return true;
    if (c1.grenades.isEmpty || c2.grenades.isEmpty) return false;
    return c1.grenades.first.id == c2.grenades.first.id;
  }

  double _getAdaptiveClusterThreshold({
    required double scale,
    required int grenadeCount,
  }) {
    final baseThreshold = scale >= 2.0 ? 0.008 : 0.02;
    if (grenadeCount >= 3200) return baseThreshold * 3.8;
    if (grenadeCount >= 2000) return baseThreshold * 3.0;
    if (grenadeCount >= 1200) return baseThreshold * 2.3;
    if (grenadeCount >= 700) return baseThreshold * 2.0;
    if (grenadeCount >= 350) return baseThreshold * 1.8;
    if (grenadeCount >= 200) return baseThreshold * 1.5;
    if (grenadeCount >= 100) return baseThreshold * 1.3;
    return baseThreshold;
  }

  bool _shouldUseDenseMarkerStyle({
    required int grenadeCount,
    required int clusterCount,
  }) {
    return grenadeCount >= 100 || clusterCount >= 100;
  }

  void _refreshAllMapGrenadeCache({bool notify = true}) {
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final isar = ref.read(isarProvider);

    final grenades = <Grenade>[];
    final entries = <({Grenade grenade, MapLayer layer})>[];

    for (final layer in layers) {
      final layerGrenades = isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(layer.id))
          .findAllSync();
      grenades.addAll(layerGrenades);
      for (final grenade in layerGrenades) {
        entries.add((grenade: grenade, layer: layer));
      }
    }

    void applyCache() {
      _invalidateClusterCaches();
      _cachedAllMapGrenades = grenades;
      _cachedAllMapGrenadeEntries = entries;
    }

    if (notify && mounted) {
      setState(applyCache);
    } else {
      applyCache();
    }
  }

  void _invalidateClusterCaches() {
    _throwClusterCacheSource = null;
    _throwClusterCacheThreshold = null;
    _throwClusterCache = const [];
    _impactClusterCacheSource = null;
    _impactClusterCacheThreshold = null;
    _impactClusterCache = const [];
  }

  List<GrenadeCluster> _getThrowClusters(
    List<Grenade> grenades, {
    required double threshold,
  }) {
    if (!identical(_throwClusterCacheSource, grenades) ||
        _throwClusterCacheThreshold != threshold) {
      _throwClusterCacheSource = grenades;
      _throwClusterCacheThreshold = threshold;
      _throwClusterCache = clusterGrenades(grenades, threshold: threshold);
    }
    return _throwClusterCache;
  }

  List<GrenadeCluster> _getImpactClusters(
    List<Grenade> grenades, {
    required double threshold,
  }) {
    if (!identical(_impactClusterCacheSource, grenades) ||
        _impactClusterCacheThreshold != threshold) {
      _impactClusterCacheSource = grenades;
      _impactClusterCacheThreshold = threshold;
      _impactClusterCache = clusterGrenadesByImpact(
        grenades,
        threshold: threshold,
      );
    }
    return _impactClusterCache;
  }

  /// 计算图片区域
  /// 返回 (imageWidth, imageHeight, offsetX, offsetY)
  ({double width, double height, double offsetX, double offsetY})
      _getImageBounds(double containerWidth, double containerHeight) {
    const double imageAspectRatio = 1.0; // 正方形图片
    final double containerAspectRatio = containerWidth / containerHeight;

    if (containerAspectRatio > imageAspectRatio) {
      // 宽容器
      final imageHeight = containerHeight;
      final imageWidth = containerHeight * imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: (containerWidth - imageWidth) / 2,
        offsetY: 0.0,
      );
    } else {
      // 高容器
      final imageWidth = containerWidth;
      final imageHeight = containerWidth / imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: 0.0,
        offsetY: (containerHeight - imageHeight) / 2,
      );
    }
  }

  ({
    double left,
    double top,
    double right,
    double bottom,
  }) _getVisibleImageRatioRect({
    required BoxConstraints constraints,
    required double scale,
    required Offset position,
    required ({
      double width,
      double height,
      double offsetX,
      double offsetY
    }) imageBounds,
  }) {
    final safeScale = scale <= 0 ? 1.0 : scale;
    final viewportCenter =
        Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);

    double screenToChildX(double x) =>
        ((x - viewportCenter.dx - position.dx) / safeScale) + viewportCenter.dx;
    double screenToChildY(double y) =>
        ((y - viewportCenter.dy - position.dy) / safeScale) + viewportCenter.dy;

    final childLeft = screenToChildX(0);
    final childRight = screenToChildX(constraints.maxWidth);
    final childTop = screenToChildY(0);
    final childBottom = screenToChildY(constraints.maxHeight);

    final ratioLeftA = (childLeft - imageBounds.offsetX) / imageBounds.width;
    final ratioRightA = (childRight - imageBounds.offsetX) / imageBounds.width;
    final ratioTopA = (childTop - imageBounds.offsetY) / imageBounds.height;
    final ratioBottomA =
        (childBottom - imageBounds.offsetY) / imageBounds.height;

    final left = ratioLeftA < ratioRightA ? ratioLeftA : ratioRightA;
    final right = ratioLeftA > ratioRightA ? ratioLeftA : ratioRightA;
    final top = ratioTopA < ratioBottomA ? ratioTopA : ratioBottomA;
    final bottom = ratioTopA > ratioBottomA ? ratioTopA : ratioBottomA;

    return (left: left, top: top, right: right, bottom: bottom);
  }

  bool _isRatioPointVisible(
    double x,
    double y, {
    required ({
      double left,
      double top,
      double right,
      double bottom,
    }) visibleRect,
    double marginX = 0,
    double marginY = 0,
  }) {
    return x >= visibleRect.left - marginX &&
        x <= visibleRect.right + marginX &&
        y >= visibleRect.top - marginY &&
        y <= visibleRect.bottom + marginY;
  }

  bool _isRatioSegmentVisible(
    double x1,
    double y1,
    double x2,
    double y2, {
    required ({
      double left,
      double top,
      double right,
      double bottom,
    }) visibleRect,
    double marginX = 0,
    double marginY = 0,
  }) {
    final minX = x1 < x2 ? x1 : x2;
    final maxX = x1 > x2 ? x1 : x2;
    final minY = y1 < y2 ? y1 : y2;
    final maxY = y1 > y2 ? y1 : y2;

    return !(maxX < visibleRect.left - marginX ||
        minX > visibleRect.right + marginX ||
        maxY < visibleRect.top - marginY ||
        minY > visibleRect.bottom + marginY);
  }

  /// 坐标转比例
  /// 返回 null 如果坐标无效
  Offset? _getLocalPosition(Offset globalPosition) {
    // 获取RenderBox
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    // 转局部坐标
    final localPosition = box.globalToLocal(globalPosition);

    // 获取尺寸
    final size = box.size;

    // 计算区域
    final bounds = _getImageBounds(size.width, size.height);

    // 计算偏移
    final tapX = localPosition.dx - bounds.offsetX;
    final tapY = localPosition.dy - bounds.offsetY;

    // 转比例
    return Offset(tapX / bounds.width, tapY / bounds.height);
  }

  void _updateOverlayState(int layerIndex) {
    if (!_supportsOverlayWindow) return;
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    if (layerIndex < layers.length) {
      final layer = layers[layerIndex];
      globalOverlayState?.setCurrentMap(widget.gameMap, layer);
      // 通知独立悬浮窗
      _notifyOverlayWindowSetMap(widget.gameMap.id, layer.id);
    }
  }

  void _notifyOverlayWindowSetMap(int mapId, int layerId,
      {int retryCount = 0}) {
    if (!_supportsOverlayWindow) return;
    if (overlayWindowController != null) {
      try {
        overlayWindowController!.invokeMethod('set_map', {
          'map_id': mapId,
          'layer_id': layerId,
        }).catchError((e) {
          if (retryCount < 3) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _notifyOverlayWindowSetMap(mapId, layerId,
                  retryCount: retryCount + 1);
            });
          }
        });
      } catch (e) {
        // ignore
      }
    } else {
      if (retryCount < 5) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _notifyOverlayWindowSetMap(mapId, layerId,
              retryCount: retryCount + 1);
        });
      }
    }
  }

  void _notifyOverlayWindowClearMap() {
    if (!_supportsOverlayWindow) return;
    if (overlayWindowController != null) {
      try {
        overlayWindowController!.invokeMethod('clear_map').catchError((_) {});
      } catch (_) {}
    }
  }

  bool get _supportsOverlayWindow =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  int _getGrenadeCreateMode() {
    return globalSettingsService?.getGrenadeCreateMode() ??
        _grenadeCreateModeTap;
  }

  void _showGrenadeCreateModeHint() {
    if (!mounted) return;
    final mode = _getGrenadeCreateMode();
    final detailText = mode == _grenadeCreateModeLongPress
        ? '当前新增方式：长按地图新增道具'
        : '当前新增方式：单点地图新增道具';
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('💡 $detailText'),
        backgroundColor: Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleAllMapListPanelCollapsed() {
    final current = _allMapListPanelHeightNotifier.value;
    final shouldExpand = current < _allMapListPanelMinExpandedHeight;
    _allMapListPanelHeightNotifier.value = shouldExpand
        ? _allMapListPanelDefaultHeight
        : _allMapListPanelCollapsedHeight;
  }

  void _resizeAllMapListPanel(double deltaDy, double maxHeight) {
    final next = (_allMapListPanelHeightNotifier.value - deltaDy)
        .clamp(_allMapListPanelCollapsedHeight, maxHeight);
    _allMapListPanelHeightNotifier.value = (next as num).toDouble();
  }

  void _snapAllMapListPanelHeight(double maxHeight) {
    final current = _allMapListPanelHeightNotifier.value;
    if (current <
        (_allMapListPanelCollapsedHeight + _allMapListPanelMinExpandedHeight) /
            2) {
      _allMapListPanelHeightNotifier.value = _allMapListPanelCollapsedHeight;
      return;
    }
    if (current < _allMapListPanelMinExpandedHeight) {
      _allMapListPanelHeightNotifier.value = _allMapListPanelMinExpandedHeight;
      return;
    }
    if (current > maxHeight) {
      _allMapListPanelHeightNotifier.value = maxHeight;
    }
  }

  void _tryCreateGrenadeAtGlobalPosition(Offset globalPosition, int layerId) {
    if (_isMovingCluster ||
        _movingSingleGrenade != null ||
        _movingSingleImpactGrenade != null ||
        _draggingImpactCluster != null) {
      return;
    }

    final isEditMode = ref.read(isEditModeProvider);
    if (!isEditMode) return;

    // 面板打开禁创建
    if (_selectedClusterForImpact != null) return;

    final localRatio = _getLocalPosition(globalPosition);
    if (localRatio == null) return;

    final xRatio = localRatio.dx;
    final yRatio = localRatio.dy;
    if (xRatio < 0 || xRatio > 1 || yRatio < 0 || yRatio > 1) {
      return;
    }

    setState(() {
      _tempTapPosition = Offset(xRatio, yRatio);
    });
    _createGrenade(layerId);
  }

  void _handleTap(
      TapUpDetails details, double width, double height, int layerId) async {
    if (_isMovingCluster ||
        _movingSingleGrenade != null ||
        _movingSingleImpactGrenade != null ||
        _draggingImpactCluster != null) {
      final localRatio = _getLocalPosition(details.globalPosition);
      if (localRatio == null) return;

      final targetX = localRatio.dx;
      final targetY = localRatio.dy;

      // 边界检查
      if (targetX < 0 || targetX > 1 || targetY < 0 || targetY > 1) {
        return;
      }

      // 移动单个
      if (_movingSingleGrenade != null) {
        final isar = ref.read(isarProvider);
        final targetId = _movingSingleGrenade!.id;

        await isar.writeTxn(() async {
          final g = await isar.grenades.get(targetId);
          if (g != null) {
            g.xRatio = targetX;
            g.yRatio = targetY;
            g.updatedAt = DateTime.now();
            await isar.grenades.put(g);
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✓ 道具位置已更新"),
            backgroundColor: Colors.cyan,
            duration: Duration(seconds: 1)));

        // 恢复选中
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted) return;
          // 获取列表
          final grenades =
              ref.read(_filteredGrenadesProvider(layerId)).asData?.value;
          if (grenades != null) {
            final clusterThreshold = _getAdaptiveClusterThreshold(
              scale: _photoViewController.scale ?? 1.0,
              grenadeCount: grenades.length,
            );

            List<GrenadeCluster> clusters;
            if (_isImpactMode) {
              clusters =
                  _getImpactClusters(grenades, threshold: clusterThreshold);
            } else {
              clusters =
                  _getThrowClusters(grenades, threshold: clusterThreshold);
            }

            // 找Cluster
            try {
              final cluster = clusters
                  .firstWhere((c) => c.grenades.any((g) => g.id == targetId));
              setState(() {
                _selectedClusterForImpact = cluster;
              });
            } catch (_) {
              // 找不到忽略
            }
          }
        });

        setState(() {
          _movingSingleGrenade = null;
        });
        return;
      }

      // 移动爆点
      if (_movingSingleImpactGrenade != null) {
        final isar = ref.read(isarProvider);
        await isar.writeTxn(() async {
          final g = await isar.grenades.get(_movingSingleImpactGrenade!.id);
          if (g != null) {
            g.impactXRatio = targetX;
            g.impactYRatio = targetY;
            g.updatedAt = DateTime.now();
            await isar.grenades.put(g);
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✓ 爆点位置已更新"),
            backgroundColor: Colors.purpleAccent,
            duration: Duration(seconds: 1)));

        // 恢复选中
        final impactTargetId = _movingSingleImpactGrenade!.id;
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted) return;
          final grenades =
              ref.read(_filteredGrenadesProvider(layerId)).asData?.value;
          if (grenades != null) {
            final clusterThreshold = _getAdaptiveClusterThreshold(
              scale: _photoViewController.scale ?? 1.0,
              grenadeCount: grenades.length,
            );

            List<GrenadeCluster> clusters;
            if (_isImpactMode) {
              clusters =
                  _getImpactClusters(grenades, threshold: clusterThreshold);
            } else {
              clusters =
                  _getThrowClusters(grenades, threshold: clusterThreshold);
            }

            try {
              final cluster = clusters.firstWhere(
                  (c) => c.grenades.any((g) => g.id == impactTargetId));
              setState(() {
                _selectedClusterForImpact = cluster;
              });
            } catch (_) {}
          }
        });

        setState(() {
          _movingSingleImpactGrenade = null;
        });
        return;
      }

      // 移动Cluster爆点
      if (_draggingImpactCluster != null) {
        final isar = ref.read(isarProvider);
        await isar.writeTxn(() async {
          for (final g in _draggingImpactCluster!.grenades) {
            final freshG = await isar.grenades.get(g.id);
            if (freshG != null) {
              freshG.impactXRatio = targetX;
              freshG.impactYRatio = targetY;
              freshG.updatedAt = DateTime.now();
              await isar.grenades.put(freshG);
            }
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✓ 爆点已移动"),
            backgroundColor: Colors.purpleAccent,
            duration: Duration(seconds: 1)));

        setState(() {
          _draggingImpactCluster = null;
          _impactDragOffset = null;
          _impactDragAnchorOffset = null;
        });
        return;
      }

      if (_isMovingCluster && _draggingCluster != null) {
        final isar = ref.read(isarProvider);
        isar.writeTxnSync(() {
          for (final g in _draggingCluster!.grenades) {
            final freshG = isar.grenades.getSync(g.id);
            if (freshG != null) {
              freshG.xRatio = targetX;
              freshG.yRatio = targetY;
              freshG.updatedAt = DateTime.now();
              isar.grenades.putSync(freshG);
            }
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✓ 点位已移动"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1)));

        setState(() {
          _isMovingCluster = false;
          _draggingCluster = null;
          _dragOffset = null;
        });
        return;
      }
      return;
    }
    final isEditMode = ref.read(isEditModeProvider);
    if (!isEditMode) return;
    if (_getGrenadeCreateMode() != _grenadeCreateModeTap) return;
    _tryCreateGrenadeAtGlobalPosition(details.globalPosition, layerId);
  }

  void _createGrenade(int layerId) async {
    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(layerId);
    if (layer == null) return;
    final grenade = Grenade(
      title: "新道具",
      type: GrenadeType.smoke,
      team: TeamType.all,
      xRatio: _tempTapPosition!.dx,
      yRatio: _tempTapPosition!.dy,
      isNewImport: false,
      uniqueId: const Uuid().v4(),
    );
    int id = 0;
    await isar.writeTxn(() async {
      id = await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
    });
    setState(() {
      _tempTapPosition = null;
    });
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GrenadeDetailScreen(grenadeId: id, isEditing: true)));
  }

  void _switchToLayerById(int? targetLayerId, {String? layerName}) {
    if (targetLayerId == null) return;
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final targetIndex = layers.indexWhere((l) => l.id == targetLayerId);
    if (targetIndex != -1 &&
        targetIndex != ref.read(selectedLayerIndexProvider)) {
      ref.read(selectedLayerIndexProvider.notifier).state = targetIndex;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("已跳转至 ${layerName ?? layers[targetIndex].name}"),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _onSearchResultSelected(Grenade g) {
    g.layer.loadSync();
    _switchToLayerById(g.layer.value?.id, layerName: g.layer.value?.name);
    _handleGrenadeTap(g, isEditing: false);
  }

  void _handleGrenadeTap(Grenade g, {required bool isEditing}) async {
    final isar = ref.read(isarProvider);
    if (g.isNewImport) {
      g.isNewImport = false;
      await isar.writeTxn(() async {
        await isar.grenades.put(g);
      });
    }
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GrenadeDetailScreen(grenadeId: g.id, isEditing: isEditing)));
  }

  void _handleClusterTap(GrenadeCluster cluster, int layerId) async {
    // 合并逻辑
    if (_movingSingleGrenade != null) {
      if (cluster.grenades.any((g) => g.id == _movingSingleGrenade!.id)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("不能合并到自己所在的点位"),
            // 避免遮挡
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1)));
        return;
      }

      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        final g = await isar.grenades.get(_movingSingleGrenade!.id);
        if (g != null) {
          // 合并坐标
          // 物理合并
          final targetX = cluster.grenades.first.xRatio;
          final targetY = cluster.grenades.first.yRatio;

          g.xRatio = targetX;
          g.yRatio = targetY;
          g.updatedAt = DateTime.now();
          await isar.grenades.put(g);
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✓ 已合并到既有点位"),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1)));

      setState(() {
        _movingSingleGrenade = null;
      });
      setState(() {
        _movingSingleGrenade = null;
      });
      return;
    }

    // 处理单个爆点移动
    if (_movingSingleImpactGrenade != null) {
      final isar = ref.read(isarProvider);

      // 吸附效果
      final targetX = cluster.xRatio;
      final targetY = cluster.yRatio;

      await isar.writeTxn(() async {
        final g = await isar.grenades.get(_movingSingleImpactGrenade!.id);
        if (g != null) {
          g.impactXRatio = targetX;
          g.impactYRatio = targetY;
          g.updatedAt = DateTime.now();
          await isar.grenades.put(g);
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✓ 爆点位置已更新"),
          backgroundColor: Colors.purpleAccent,
          duration: Duration(seconds: 1)));

      setState(() {
        _movingSingleImpactGrenade = null;
      });
      return;
    }

    // 组合并
    if (_isMovingCluster && _draggingCluster != null) {
      // 自包含检查
      final draggingIds = _draggingCluster!.grenades.map((g) => g.id).toSet();
      final targetIds = cluster.grenades.map((g) => g.id).toSet();

      if (draggingIds.intersection(targetIds).isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("不能合并到自己所在的点位"),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1)));
        return;
      }

      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        // 合并基准
        final targetX = cluster.grenades.first.xRatio;
        final targetY = cluster.grenades.first.yRatio;

        for (final g in _draggingCluster!.grenades) {
          final freshG = await isar.grenades.get(g.id);
          if (freshG != null) {
            freshG.xRatio = targetX;
            freshG.yRatio = targetY;
            freshG.updatedAt = DateTime.now();
            await isar.grenades.put(freshG);
          }
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✓ 点位已合并"),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1)));

      setState(() {
        _isMovingCluster = false;
        _draggingCluster = null;
        _dragOffset = null;
      });
      return;
    }

    _showClusterBottomSheet(cluster, layerId);
  }

  Future<void> _deleteGrenadeFromMapList(Grenade g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text("删除道具",
            style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: Text("确定要删除 \"${g.title}\" 吗？",
            style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _deleteGrenadesInBatch([g]);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✓ 道具已删除"),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _buildAllMapGrenadesPanel(
      List<({Grenade grenade, MapLayer layer})> entries,
      bool isEditMode,
      int currentLayerId) {
    final maxPanelHeight =
        ((MediaQuery.of(context).size.height * 0.65).clamp(240.0, 560.0) as num)
            .toDouble();
    final query = _allMapListSearchQuery.trim().toLowerCase();
    final sortedEntries = [...entries]..sort((a, b) {
        final layerCompare = a.layer.name.compareTo(b.layer.name);
        if (layerCompare != 0) return layerCompare;
        return a.grenade.title.compareTo(b.grenade.title);
      });
    final filteredEntries = query.isEmpty
        ? sortedEntries
        : sortedEntries.where((entry) {
            final g = entry.grenade;
            return g.title.toLowerCase().contains(query);
          }).toList();

    return ValueListenableBuilder<double>(
      valueListenable: _allMapListPanelHeightNotifier,
      builder: (context, rawPanelHeight, _) {
        final panelHeight = (rawPanelHeight as num)
            .clamp(_allMapListPanelCollapsedHeight, maxPanelHeight)
            .toDouble();
        final showExpandedContent =
            panelHeight >= _allMapListPanelMinExpandedHeight;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: panelHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) =>
                    _resizeAllMapListPanel(details.delta.dy, maxPanelHeight),
                onVerticalDragEnd: (_) =>
                    _snapAllMapListPanelHeight(maxPanelHeight),
                child: Column(
                  children: [
                    SizedBox(height: showExpandedContent ? 6 : 4),
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: showExpandedContent ? 8 : 4,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.list_alt,
                              color: Colors.blueAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              showExpandedContent
                                  ? '地图道具列表（${filteredEntries.length}/${sortedEntries.length}）'
                                  : '地图道具列表（${sortedEntries.length}）',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (showExpandedContent)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                isEditMode ? '点击编辑，右侧可删' : '点击查看',
                                style: TextStyle(
                                  color: Theme.of(context).hintColor,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: showExpandedContent ? '折叠列表' : '展开列表',
                            onPressed: _toggleAllMapListPanelCollapsed,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(
                              showExpandedContent
                                  ? Icons.expand_more
                                  : Icons.expand_less,
                              color: Colors.blueAccent,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showExpandedContent)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: TextField(
                    controller: _allMapListSearchController,
                    onChanged: (value) =>
                        setState(() => _allMapListSearchQuery = value),
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索道具名称',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      suffixIcon: _allMapListSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空搜索',
                              icon: const Icon(Icons.close, size: 14),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () {
                                _allMapListSearchController.clear();
                                setState(() => _allMapListSearchQuery = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              if (showExpandedContent)
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              if (showExpandedContent)
                Expanded(
                  child: sortedEntries.isEmpty
                      ? const Center(
                          child: Text(
                            '当前地图暂无道具',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : filteredEntries.isEmpty
                          ? const Center(
                              child: Text(
                                '没有匹配的道具',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filteredEntries.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color:
                                    Theme.of(context).dividerColor.withValues(
                                          alpha: 0.12,
                                        ),
                              ),
                              itemBuilder: (context, index) {
                                final entry = filteredEntries[index];
                                final g = entry.grenade;
                                final layer = entry.layer;
                                final isCurrentLayer =
                                    layer.id == currentLayerId;
                                final typeColor = _getTypeColor(g.type);

                                return ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  tileColor: isCurrentLayer
                                      ? Colors.blueAccent
                                          .withValues(alpha: 0.08)
                                      : null,
                                  leading: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: typeColor, width: 1.8),
                                    ),
                                    child: Icon(
                                      _getTypeIcon(g.type),
                                      size: 14,
                                      color: typeColor,
                                    ),
                                  ),
                                  title: Text(
                                    g.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  subtitle: Text(
                                    '${layer.name} • ${_getTypeName(g.type)} • ${_getTeamName(g.team)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (g.isFavorite)
                                        const Icon(Icons.star,
                                            color: Colors.amber, size: 14),
                                      if (isEditMode)
                                        IconButton(
                                          onPressed: () =>
                                              _deleteGrenadeFromMapList(g),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          color: Colors.redAccent,
                                          tooltip: '删除道具',
                                          iconSize: 18,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        )
                                      else
                                        const Icon(Icons.chevron_right,
                                            color: Colors.grey, size: 16),
                                    ],
                                  ),
                                  onTap: () {
                                    _switchToLayerById(layer.id,
                                        layerName: layer.name);
                                    _handleGrenadeTap(g, isEditing: isEditMode);
                                  },
                                );
                              },
                            ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showClusterBottomSheet(GrenadeCluster cluster, int layerId) async {
    // 选中状态
    setState(() {
      _selectedClusterForImpact = cluster;
    });

    // 清除新标记
    final newImportGrenades =
        cluster.grenades.where((g) => g.isNewImport).toList();
    if (newImportGrenades.isNotEmpty) {
      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        for (final g in newImportGrenades) {
          g.isNewImport = false;
          await isar.grenades.put(g);
        }
      });
    }
  }

  // 关闭面板
  void _closeClusterPanel() {
    setState(() {
      _selectedClusterForImpact = null;
      _selectedImpactTypeFilter = null;
      _selectedImpactGroupId = null;
    });
  }

  void _createGrenadeAtCluster(GrenadeCluster cluster, int layerId) async {
    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(layerId);
    if (layer == null) return;
    final grenade = Grenade(
        title: "新道具",
        type: GrenadeType.smoke,
        team: TeamType.all,
        xRatio: cluster.xRatio,
        yRatio: cluster.yRatio,
        isNewImport: false,
        uniqueId: const Uuid().v4());
    int id = 0;
    await isar.writeTxn(() async {
      id = await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
    });
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GrenadeDetailScreen(grenadeId: id, isEditing: true)));
  }

  /// 批量删除
  Future<void> _deleteGrenadesInBatch(List<Grenade> grenades) async {
    if (grenades.isEmpty) return;
    final isar = ref.read(isarProvider);

    // 加载数据
    for (final g in grenades) {
      g.steps.loadSync();
      for (final step in g.steps) {
        step.medias.loadSync();
      }
    }

    // 删文件
    for (final g in grenades) {
      for (final step in g.steps) {
        for (final media in step.medias) {
          await DataService.deleteMediaFile(media.localPath);
        }
      }
    }

    // 在单个事务中执行所有删除操作
    await isar.writeTxn(() async {
      for (final g in grenades) {
        // 删除所有媒体记录
        for (final step in g.steps) {
          await isar.stepMedias
              .deleteAll(step.medias.map((m) => m.id).toList());
        }
        // 删除所有步骤
        await isar.grenadeSteps.deleteAll(g.steps.map((s) => s.id).toList());
        // 删除道具
        await isar.grenades.delete(g.id);
      }
    });
  }

  void _startMoveCluster(GrenadeCluster cluster) {
    setState(() {
      _isMovingCluster = true;
      _draggingCluster = cluster;
      _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("点击地图新位置以移动点位，或点击取消"),
      backgroundColor: Colors.cyan,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
          label: "取消", textColor: Colors.white, onPressed: _cancelMoveCluster),
    ));
  }

  void _cancelMoveCluster() {
    setState(() {
      _isMovingCluster = false;
      _draggingCluster = null;
      _dragOffset = null;
      _dragAnchorOffset = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// 开始移动爆点位置
  void _startMoveImpactCluster(GrenadeCluster cluster) {
    setState(() {
      _draggingImpactCluster = cluster;
      _impactDragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("点击地图新位置以移动爆点，或点击取消"),
      backgroundColor: Colors.purpleAccent,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
          label: "取消",
          textColor: Colors.white,
          onPressed: _cancelMoveImpactCluster),
    ));
  }

  void _cancelMoveImpactCluster() {
    setState(() {
      _draggingImpactCluster = null;
      _impactDragOffset = null;
      _impactDragAnchorOffset = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// 开始移动单个道具
  void _startMoveSingleGrenade(Grenade grenade) {
    setState(() {
      _movingSingleGrenade = grenade;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('点击地图移动道具「${grenade.title}」'),
      backgroundColor: Colors.cyan,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
          label: "取消",
          textColor: Colors.white,
          onPressed: _cancelMoveSingleGrenade),
    ));
  }

  /// 开始移动单个道具的爆点
  void _startMoveSingleGrenadeImpact(Grenade grenade) {
    setState(() {
      _movingSingleImpactGrenade = grenade;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('点击地图移动爆点「${grenade.title}」'),
      backgroundColor: Colors.purpleAccent,
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
          label: "取消",
          textColor: Colors.white,
          onPressed: _cancelMoveSingleGrenadeImpact),
    ));
  }

  void _cancelMoveSingleGrenadeImpact() {
    setState(() {
      _movingSingleImpactGrenade = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// 打开绘制爆点区域界面
  Future<void> _openImpactAreaDrawing(Grenade grenade, int layerId) async {
    // 需要先设置爆点位置
    if (grenade.impactXRatio == null || grenade.impactYRatio == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先设置爆点位置'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ));
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ImpactPointPickerScreen(
          grenadeId: grenade.id,
          initialX: grenade.impactXRatio,
          initialY: grenade.impactYRatio,
          throwX: grenade.xRatio,
          throwY: grenade.yRatio,
          layerId: layerId,
          isDrawingMode: true,
          existingStrokes: grenade.impactAreaStrokes,
          grenadeType: grenade.type,
        ),
      ),
    );

    if (result != null && result['strokes'] != null) {
      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        final g = await isar.grenades.get(grenade.id);
        if (g != null) {
          g.impactAreaStrokes = result['strokes'] as String;
          g.updatedAt = DateTime.now();
          await isar.grenades.put(g);
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ 爆点区域已保存'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ));
    }
  }

  /// 打开自定义分组批量绘制爆点区域界面
  Future<void> _openGroupImpactAreaDrawing(
      ImpactGroup group,
      List<Grenade> grenades,
      int layerId,
      void Function(void Function())? setPanelState) async {
    if (grenades.isEmpty) return;

    // 使用第一个道具作为参照
    final referenceGrenade = grenades.first;

    // 尝试找到一个已有绘制数据的道具作为初始状态
    String? existingStrokes;
    for (final g in grenades) {
      if (g.impactAreaStrokes != null && g.impactAreaStrokes!.isNotEmpty) {
        existingStrokes = g.impactAreaStrokes;
        break;
      }
    }

    if (referenceGrenade.impactXRatio == null ||
        referenceGrenade.impactYRatio == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('分组内道具未设置爆点位置'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ));
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ImpactPointPickerScreen(
          grenadeId: referenceGrenade.id,
          initialX: referenceGrenade.impactXRatio,
          initialY: referenceGrenade.impactYRatio,
          throwX: referenceGrenade.xRatio,
          throwY: referenceGrenade.yRatio,
          layerId: layerId,
          isDrawingMode: true,
          existingStrokes: existingStrokes,
          grenadeType: group.type == GrenadeType.molotov
              ? GrenadeType.molotov
              : GrenadeType.smoke, // 强制使用分组类型对应的绘制颜色
        ),
      ),
    );

    if (result != null && result['strokes'] != null) {
      final isar = ref.read(isarProvider);
      final newStrokes = result['strokes'] as String;

      await isar.writeTxn(() async {
        for (final g in grenades) {
          // 重新从数据库获取最新对象以防并发修改
          final freshGrenade = await isar.grenades.get(g.id);
          if (freshGrenade != null) {
            freshGrenade.impactAreaStrokes = newStrokes;
            freshGrenade.updatedAt = DateTime.now();
            await isar.grenades.put(freshGrenade);
            // 更新内存中的对象，以便 UI 立即反映
            g.impactAreaStrokes = newStrokes;
          }
        }
      });

      // 强制刷新 UI
      setState(() {});
      setPanelState?.call(() {});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✓ 已同步更新分组内 ${grenades.length} 个道具的爆点区域'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  void _cancelMoveSingleGrenade() {
    setState(() {
      _movingSingleGrenade = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _onClusterDragEnd(double width, double height) {
    if (_draggingCluster == null || _dragOffset == null) {
      setState(() {
        _draggingCluster = null;
        _dragOffset = null;
      });
      return;
    }
    final isar = ref.read(isarProvider);
    isar.writeTxnSync(() {
      for (final g in _draggingCluster!.grenades) {
        g.xRatio = _dragOffset!.dx;
        g.yRatio = _dragOffset!.dy;
        g.updatedAt = DateTime.now();
        isar.grenades.putSync(g);
      }
    });
    setState(() {
      _draggingCluster = null;
      _dragOffset = null;
      _dragAnchorOffset = null;
    });
  }

  /// 爆点拖动结束，保存爆点位置
  void _onImpactClusterDragEnd(double width, double height) {
    if (_draggingImpactCluster == null || _impactDragOffset == null) {
      setState(() {
        _draggingImpactCluster = null;
        _impactDragOffset = null;
        _impactDragAnchorOffset = null;
      });
      return;
    }
    final isar = ref.read(isarProvider);
    isar.writeTxnSync(() {
      for (final g in _draggingImpactCluster!.grenades) {
        g.impactXRatio = _impactDragOffset!.dx;
        g.impactYRatio = _impactDragOffset!.dy;
        g.updatedAt = DateTime.now();
        isar.grenades.putSync(g);
      }
    });
    setState(() {
      _draggingImpactCluster = null;
      _impactDragOffset = null;
      _impactDragAnchorOffset = null;
    });
  }

  /// 显示摇杆底部弹窗
  Future<void> _showJoystickSheet(GrenadeCluster cluster) async {
    // 从 SharedPreferences 读取摇杆设置
    final prefs = await SharedPreferences.getInstance();
    final opacity = prefs.getDouble('joystick_opacity') ?? 0.8;
    final speed = prefs.getInt('joystick_speed') ?? 3;

    setState(() {
      _joystickCluster = cluster;
      _joystickOriginalOffset = Offset(cluster.xRatio, cluster.yRatio);
      _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });

    if (!mounted) return;

    await showJoystickBottomSheet(
      context: context,
      barrierColor: Colors.transparent, // 移除背景变暗
      opacity: opacity,
      speedLevel: speed,
      clusterName:
          cluster.grenades.isNotEmpty ? cluster.grenades.first.title : null,
      onMove: (direction) => _handleJoystickMove(direction, speed),
      onConfirm: _confirmJoystickMove,
      onCancel: _cancelJoystickMove,
    );
  }

  /// 处理摇杆移动
  void _handleJoystickMove(Offset direction, int speedLevel) {
    if (_joystickCluster == null || _dragOffset == null) return;

    // 根据速度档位计算移动步长 (1档=0.0005, 5档=0.0025)
    final step = 0.0005 + (speedLevel - 1) * 0.0005;

    final newX = (_dragOffset!.dx + direction.dx * step).clamp(0.0, 1.0);
    final newY = (_dragOffset!.dy + direction.dy * step).clamp(0.0, 1.0);

    setState(() {
      _dragOffset = Offset(newX, newY);
    });

    // 平移地图使点位居中
    _centerMapOnPoint(newX, newY);
  }

  /// 将地图平移使指定比例坐标的点位居中显示
  void _centerMapOnPoint(double xRatio, double yRatio) {
    final RenderBox? renderBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final scale = _photoViewController.scale ?? 1.0;

    // 计算图片边界
    final bounds = _getImageBounds(size.width, size.height);

    // 计算点位在原始坐标系中的位置
    final pointX = bounds.offsetX + xRatio * bounds.width;
    final pointY = bounds.offsetY + yRatio * bounds.height;

    // 视口中心
    final viewportCenterX = size.width / 2;
    final viewportCenterY = size.height / 2;

    // 计算需要的偏移量（使点位位于中心）
    // position 是内容相对于视口中心的偏移，在缩放后的坐标系中
    final targetPositionX = (viewportCenterX - pointX) * scale;
    final targetPositionY = (viewportCenterY - pointY) * scale;

    _photoViewController.position = Offset(targetPositionX, targetPositionY);
  }

  /// 确认摇杆移动
  void _confirmJoystickMove() {
    if (_joystickCluster == null || _dragOffset == null) {
      _cancelJoystickMove();
      return;
    }

    final isar = ref.read(isarProvider);
    isar.writeTxnSync(() {
      for (final g in _joystickCluster!.grenades) {
        g.xRatio = _dragOffset!.dx;
        g.yRatio = _dragOffset!.dy;
        g.updatedAt = DateTime.now();
        isar.grenades.putSync(g);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("✓ 点位已移动"),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 1),
    ));

    setState(() {
      _joystickCluster = null;
      _joystickOriginalOffset = null;
      _dragOffset = null;
    });
  }

  /// 取消摇杆移动
  void _cancelJoystickMove() {
    setState(() {
      _dragOffset = _joystickOriginalOffset;
      _joystickCluster = null;
      _joystickOriginalOffset = null;
      _dragOffset = null;
    });
  }

  /// 显示爆点摇杆底部弹窗
  Future<void> _showJoystickSheetForImpact(GrenadeCluster cluster) async {
    // 从 SharedPreferences 读取摇杆设置
    final prefs = await SharedPreferences.getInstance();
    final opacity = prefs.getDouble('joystick_opacity') ?? 0.8;
    final speed = prefs.getInt('joystick_speed') ?? 3;

    setState(() {
      _joystickImpactCluster = cluster;
      _joystickImpactOriginalOffset = Offset(cluster.xRatio, cluster.yRatio);
      _impactJoystickDragOffset = Offset(cluster.xRatio, cluster.yRatio);
    });

    if (!mounted) return;

    await showJoystickBottomSheet(
      context: context,
      barrierColor: Colors.transparent,
      opacity: opacity,
      speedLevel: speed,
      clusterName: cluster.grenades.isNotEmpty
          ? '爆点: ${cluster.grenades.first.title}'
          : '爆点',
      onMove: (direction) => _handleJoystickMoveForImpact(direction, speed),
      onConfirm: _confirmJoystickMoveForImpact,
      onCancel: _cancelJoystickMoveForImpact,
    );
  }

  /// 处理爆点摇杆移动
  void _handleJoystickMoveForImpact(Offset direction, int speedLevel) {
    if (_joystickImpactCluster == null || _impactJoystickDragOffset == null) {
      return;
    }

    // 根据速度档位计算移动步长 (1档=0.0005, 5档=0.0025)
    final step = 0.0005 + (speedLevel - 1) * 0.0005;

    final newX =
        (_impactJoystickDragOffset!.dx + direction.dx * step).clamp(0.0, 1.0);
    final newY =
        (_impactJoystickDragOffset!.dy + direction.dy * step).clamp(0.0, 1.0);

    setState(() {
      _impactJoystickDragOffset = Offset(newX, newY);
    });

    // 平移地图使爆点居中
    _centerMapOnPoint(newX, newY);
  }

  /// 确认爆点摇杆移动
  void _confirmJoystickMoveForImpact() {
    if (_joystickImpactCluster == null || _impactJoystickDragOffset == null) {
      _cancelJoystickMoveForImpact();
      return;
    }

    final isar = ref.read(isarProvider);
    isar.writeTxnSync(() {
      for (final g in _joystickImpactCluster!.grenades) {
        g.impactXRatio = _impactJoystickDragOffset!.dx;
        g.impactYRatio = _impactJoystickDragOffset!.dy;
        g.updatedAt = DateTime.now();
        isar.grenades.putSync(g);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("✓ 爆点已移动"),
      backgroundColor: Colors.purpleAccent,
      duration: Duration(seconds: 1),
    ));

    setState(() {
      _joystickImpactCluster = null;
      _joystickImpactOriginalOffset = null;
      _impactJoystickDragOffset = null;
    });
  }

  /// 取消爆点摇杆移动
  void _cancelJoystickMoveForImpact() {
    setState(() {
      _impactJoystickDragOffset = _joystickImpactOriginalOffset;
      _joystickImpactCluster = null;
      _joystickImpactOriginalOffset = null;
      _impactJoystickDragOffset = null;
    });
  }

  /// 处理鼠标滚轮缩放（以鼠标指针为中心）
  void _handleMouseWheelZoom(
      PointerScrollEvent event, BoxConstraints constraints) {
    // 确保有有效的RenderBox和当前的缩放值
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    // 计算缩放因子
    final double zoomFactor = scrollDelta > 0 ? 0.9 : 1.1;

    // 获取当前状态
    final double currentScale = _photoViewController.scale ?? 1.0;
    final Offset currentPosition = _photoViewController.position;

    // 计算目标缩放
    final minScale = 0.8;
    final maxScale = 5.0;
    final double newScale =
        (currentScale * zoomFactor).clamp(minScale, maxScale);

    if ((newScale - currentScale).abs() < 0.0001) return;

    // 获取视口中心和鼠标位置（相对于视口中心）
    final Size size = renderBox.size;
    final Offset viewportCenter = size.center(Offset.zero);
    final Offset cursorPosition = event.localPosition - viewportCenter;

    // 核心变焦公式：
    final double scaleRatio = newScale / currentScale;
    final Offset newPosition =
        cursorPosition * (1 - scaleRatio) + currentPosition * scaleRatio;

    _photoViewController.scale = newScale;
    _photoViewController.position = newPosition;
  }

  Color _getTeamColor(int team) {
    switch (team) {
      case TeamType.ct:
        return Colors.blueAccent;
      case TeamType.t:
        return Colors.amber;
      default:
        return Colors.white;
    }
  }

  IconData _getTypeIcon(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return Icons.cloud;
      case GrenadeType.flash:
        return Icons.flash_on;
      case GrenadeType.molotov:
        return Icons.local_fire_department;
      case GrenadeType.he:
        return Icons.trip_origin;
      case GrenadeType.wallbang:
        return Icons.apps; // 穿点使用网格图标表示墙体
      default:
        return Icons.circle;
    }
  }

  Color _getTypeColor(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return Colors.white;
      case GrenadeType.flash:
        return Colors.yellow;
      case GrenadeType.molotov:
        return Colors.red;
      case GrenadeType.he:
        return Colors.green;
      case GrenadeType.wallbang:
        return Colors.cyan;
      default:
        return Colors.white;
    }
  }

  String _getTeamName(int team) {
    switch (team) {
      case TeamType.ct:
        return "CT";
      case TeamType.t:
        return "T";
      default:
        return "通用";
    }
  }

  String _getTypeName(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return "烟雾";
      case GrenadeType.flash:
        return "闪光";
      case GrenadeType.molotov:
        return "燃烧";
      case GrenadeType.he:
        return "手雷";
      case GrenadeType.wallbang:
        return "穿点";
      default:
        return "";
    }
  }

  /// 解析笔画 JSON
  List<Map<String, dynamic>> _parseStrokes(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final parsed = jsonDecode(json) as List;
      return parsed.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 构建爆点区域显示层（选中标点时显示）
  Widget _buildImpactAreaOverlay(
    Grenade grenade,
    BoxConstraints constraints,
  ) {
    final strokes = _parseStrokes(grenade.impactAreaStrokes);
    if (strokes.isEmpty) return const SizedBox.shrink();

    final imageBounds =
        _getImageBounds(constraints.maxWidth, constraints.maxHeight);
    final color = _getTypeColor(grenade.type);
    final opacity = ref.watch(impactAreaOpacityProvider);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ImpactAreaPainter(
            strokes: strokes,
            currentStroke: [],
            currentStrokeWidth: 15,
            isCurrentEraser: false,
            color: color,
            imageBounds: imageBounds,
            opacity: opacity,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeFilterBtn(Set<int> selectedTypes, int type, String label,
      IconData icon, Color activeColor) {
    final isSelected = selectedTypes.contains(type);
    final unselectedColor = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () {
        final newSet = Set<int>.from(selectedTypes);
        if (isSelected) {
          newSet.remove(type);
        } else {
          newSet.add(type);
        }
        ref.read(typeFilterProvider.notifier).state = newSet;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.2)
                : Colors.transparent,
            border: Border.all(
                color: isSelected
                    ? activeColor
                    : unselectedColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon,
              size: 16, color: isSelected ? activeColor : unselectedColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: isSelected ? activeColor : unselectedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold))
        ]),
      ),
    );
  }

  Widget _buildFilterChip(
      String label, int value, int groupValue, Color color) {
    final isSelected = value == groupValue;
    final unselectedColor = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: () => ref.read(teamFilterProvider.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color:
                isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
            border: Border.all(
                color: isSelected
                    ? color
                    : unselectedColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? color : unselectedColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12)),
      ),
    );
  }

  Widget _buildImpactClusterMarker(
    GrenadeCluster cluster,
    BoxConstraints constraints,
    bool isEditMode,
    int layerId,
    double markerScale,
    ({
      double width,
      double height,
      double offsetX,
      double offsetY
    }) imageBounds, {
    bool denseStyle = false,
  }) {
    if (cluster.grenades.isEmpty) return const SizedBox.shrink();

    const double size = 20.0;
    const double baseHalfSize = size / 2;

    // 计算实时位置（考虑拖动状态和摇杆状态）
    double effectiveX = cluster.xRatio;
    double effectiveY = cluster.yRatio;

    // 拖动模式下使用 _impactDragOffset
    if (_isSameCluster(_draggingImpactCluster, cluster) &&
        _impactDragOffset != null) {
      effectiveX = _impactDragOffset!.dx;
      effectiveY = _impactDragOffset!.dy;
    }
    // 摇杆模式下使用 _impactJoystickDragOffset
    if (_isSameCluster(_joystickImpactCluster, cluster) &&
        _impactJoystickDragOffset != null) {
      effectiveX = _impactJoystickDragOffset!.dx;
      effectiveY = _impactJoystickDragOffset!.dy;
    }

    final left =
        imageBounds.offsetX + effectiveX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + effectiveY * imageBounds.height - baseHalfSize;

    final isSelected = _selectedClusterForImpact == cluster;
    final isDragging = _isSameCluster(_draggingImpactCluster, cluster);
    final isJoystickMoving = _isSameCluster(_joystickImpactCluster, cluster);
    final useGlowEffects =
        !denseStyle || isDragging || isJoystickMoving || isSelected;

    // 获取道具类型对应的颜色，多投掷点聚合时使用紫色
    final impactColor = cluster.grenades.length > 1
        ? Colors.purpleAccent
        : _getTypeColor(cluster.primaryType);

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {
            _handleClusterTap(cluster, layerId);
          },
          // 长按开始拖动或摇杆移动（仅编辑模式）
          onLongPressStart: isEditMode
              ? (details) async {
                  // 移动端检查是否使用摇杆模式
                  if (Platform.isAndroid || Platform.isIOS) {
                    final prefs = await SharedPreferences.getInstance();
                    final markerMoveMode =
                        prefs.getInt('marker_move_mode') ?? 0;
                    if (markerMoveMode == 1) {
                      // 摇杆模式：弹出摇杆底部弹窗
                      _showJoystickSheetForImpact(cluster);
                      return;
                    }
                  }
                  // 长按拖动模式（桌面端或移动端选择此模式）
                  final touchRatio = _getLocalPosition(details.globalPosition);
                  if (touchRatio == null) return;

                  setState(() {
                    _draggingImpactCluster = cluster;
                    _impactDragAnchorOffset =
                        touchRatio - Offset(cluster.xRatio, cluster.yRatio);
                    _impactDragOffset = Offset(cluster.xRatio, cluster.yRatio);
                  });
                }
              : null,
          // 拖动更新位置
          onLongPressMoveUpdate: isEditMode
              ? (details) {
                  if (_impactDragAnchorOffset == null) return;

                  final touchRatio = _getLocalPosition(details.globalPosition);
                  if (touchRatio == null) return;

                  setState(() {
                    final newPos = touchRatio - _impactDragAnchorOffset!;
                    _impactDragOffset = Offset(
                      newPos.dx.clamp(0.0, 1.0),
                      newPos.dy.clamp(0.0, 1.0),
                    );
                  });
                }
              : null,
          // 拖动结束，保存位置
          onLongPressEnd: isEditMode
              ? (_) => _onImpactClusterDragEnd(
                  constraints.maxWidth, constraints.maxHeight)
              : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: (isDragging || isJoystickMoving)
                  ? Colors.cyan.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: denseStyle ? 0.28 : 0.4),
              shape: BoxShape.circle,
              border: Border.all(
                  color: (isDragging || isJoystickMoving)
                      ? Colors.cyan
                      : (isSelected ? Colors.white : impactColor),
                  width: (isDragging || isJoystickMoving) ? 3 : 2),
              boxShadow: useGlowEffects
                  ? (isDragging || isJoystickMoving)
                      ? [
                          BoxShadow(
                            color: Colors.cyan.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 3,
                          )
                        ]
                      : isSelected
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 2,
                              )
                            ]
                          : [
                              BoxShadow(
                                color: impactColor.withValues(alpha: 0.3),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                  : null,
            ),
            child: Icon(
              (isDragging || isJoystickMoving) ? Icons.open_with : Icons.close,
              size: size * 0.6,
              color: (isDragging || isJoystickMoving)
                  ? Colors.white
                  : (isSelected ? Colors.white : impactColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClusterMarker(
    GrenadeCluster cluster,
    BoxConstraints constraints,
    bool isEditMode,
    int layerId,
    double markerScale,
    ({
      double width,
      double height,
      double offsetX,
      double offsetY
    }) imageBounds, {
    bool denseStyle = false,
  }) {
    final color = _getTeamColor(cluster.primaryTeam);
    final icon = _getTypeIcon(cluster.primaryType);
    final count = cluster.grenades.length;
    final showCountText = count > 1;

    const double baseHalfSize = 10.0;

    double effectiveX = cluster.xRatio;
    double effectiveY = cluster.yRatio;

    if ((_isSameCluster(_draggingCluster, cluster) ||
            _isSameCluster(_joystickCluster, cluster)) &&
        _dragOffset != null) {
      effectiveX = _dragOffset!.dx;
      effectiveY = _dragOffset!.dy;
    }

    final left =
        imageBounds.offsetX + effectiveX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + effectiveY * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => _handleClusterTap(cluster, layerId),
          onLongPressStart: isEditMode
              ? (details) async {
                  // 移动端检查是否使用摇杆模式
                  if (Platform.isAndroid || Platform.isIOS) {
                    final prefs = await SharedPreferences.getInstance();
                    final markerMoveMode =
                        prefs.getInt('marker_move_mode') ?? 0;
                    if (markerMoveMode == 1) {
                      // 摇杆模式：弹出摇杆底部弹窗
                      _showJoystickSheet(cluster);
                      return;
                    }
                  }
                  // 长按选定模式（桌面端或移动端选择此模式）
                  // 获取按下的触摸点位置（Ratio）
                  final touchRatio = _getLocalPosition(details.globalPosition);
                  if (touchRatio == null) return;

                  setState(() {
                    _draggingCluster = cluster;
                    // 计算锚点偏移：触摸点 - Cluster中心
                    // 这样在拖动时，我们只需要用 新触摸点 - 锚点偏移 就能还原出 Cluster中心
                    _dragAnchorOffset =
                        touchRatio - Offset(cluster.xRatio, cluster.yRatio);
                    _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
                  });
                }
              : null,
          onLongPressMoveUpdate: isEditMode
              ? (details) {
                  if (_dragAnchorOffset == null) return;

                  // 获取当前触摸点位置（Ratio）
                  final touchRatio = _getLocalPosition(details.globalPosition);
                  if (touchRatio == null) return;

                  setState(() {
                    // 新 Cluster 中心 = 当前触摸点 - 锚点偏移
                    final newPos = touchRatio - _dragAnchorOffset!;
                    _dragOffset = newPos;
                  });
                }
              : null,
          onLongPressEnd: isEditMode
              ? (_) =>
                  _onClusterDragEnd(constraints.maxWidth, constraints.maxHeight)
              : null,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3), // 背景半透明
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: color.withValues(alpha: 0.5), // 边框轻微透明
                        width: 2),
                    boxShadow: denseStyle
                        ? null
                        : [
                            if (cluster.hasFavorite)
                              BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  spreadRadius: 1)
                          ]),
                child: Icon(cluster.hasMultipleTypes ? Icons.layers : icon,
                    size: 10,
                    color: cluster.hasMultipleTypes
                        ? Colors.purpleAccent.withValues(alpha: 0.9)
                        : _getTypeColor(cluster.primaryType))), // 图标使用道具类型颜色
            if (showCountText)
              Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                      child: Text('$count',
                          style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)))),
            if (cluster.hasNewImport && !denseStyle)
              Positioned(
                  left: -2,
                  top: -2,
                  child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle))),
          ]),
        ),
      ),
    );
  }

  /// 构建投掷点标记（爆点模式下显示关联的投掷位置）
  Widget _buildThrowPointMarker(
      Grenade grenade,
      BoxConstraints constraints,
      double markerScale,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    final icon = _getTypeIcon(grenade.type);

    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + grenade.xRatio * imageBounds.width - baseHalfSize;
    final top = imageBounds.offsetY +
        grenade.yRatio * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.orangeAccent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.orangeAccent.withValues(alpha: 0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, size: 10, color: _getTypeColor(grenade.type)),
        ),
      ),
    );
  }

  /// 构建选中状态的投掷点标记（标准模式下显示cluster内所有投掷点，带光圈效果）
  Widget _buildSelectedThrowPointMarker(
      Grenade grenade,
      BoxConstraints constraints,
      double markerScale,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    final icon = _getTypeIcon(grenade.type);
    final typeColor = _getTypeColor(grenade.type);

    const double baseHalfSize = 12.0;
    final left =
        imageBounds.offsetX + grenade.xRatio * imageBounds.width - baseHalfSize;
    final top = imageBounds.offsetY +
        grenade.yRatio * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            shape: BoxShape.circle,
            border: Border.all(
              color: typeColor,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: typeColor.withValues(alpha: 0.6),
                blurRadius: 8,
                spreadRadius: 3,
              ),
              BoxShadow(
                color: typeColor.withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, size: 12, color: typeColor),
        ),
      ),
    );
  }

  /// 构建选中状态的聚合标记（标准模式下仍然聚合时显示，带光圈效果）
  Widget _buildSelectedClusterMarker(
      GrenadeCluster cluster,
      BoxConstraints constraints,
      double markerScale,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    final color = _getTeamColor(cluster.primaryTeam);
    final icon = _getTypeIcon(cluster.primaryType);
    final count = cluster.grenades.length;
    final typeColor = cluster.hasMultipleTypes
        ? Colors.purpleAccent
        : _getTypeColor(cluster.primaryType);

    const double baseHalfSize = 14.0;
    final left =
        imageBounds.offsetX + cluster.xRatio * imageBounds.width - baseHalfSize;
    final top = imageBounds.offsetY +
        cluster.yRatio * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              shape: BoxShape.circle,
              border: Border.all(
                color: typeColor,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: typeColor.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: typeColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 8,
                ),
                if (cluster.hasFavorite)
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: Icon(
              cluster.hasMultipleTypes ? Icons.layers : icon,
              size: 14,
              color: typeColor,
            ),
          ),
          if (count > 1)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// 构建爆点标记（紫色圆形外圈 + X 内部）
  Widget _buildImpactMarker(
      Grenade grenade,
      BoxConstraints constraints,
      double markerScale,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    if (grenade.impactXRatio == null || grenade.impactYRatio == null) {
      return const SizedBox.shrink();
    }

    const double baseHalfSize = 8.0;
    final left = imageBounds.offsetX +
        grenade.impactXRatio! * imageBounds.width -
        baseHalfSize;
    final top = imageBounds.offsetY +
        grenade.impactYRatio! * imageBounds.height -
        baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.purpleAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withValues(alpha: 0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 10, color: Colors.purpleAccent),
        ),
      ),
    );
  }

  /// 构建投掷点到爆点的连线
  Widget _buildConnectionLine(
      Grenade grenade,
      double scale,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    if (grenade.impactXRatio == null || grenade.impactYRatio == null) {
      return const SizedBox.shrink();
    }

    final startX = imageBounds.offsetX + grenade.xRatio * imageBounds.width;
    final startY = imageBounds.offsetY + grenade.yRatio * imageBounds.height;
    final endX =
        imageBounds.offsetX + grenade.impactXRatio! * imageBounds.width;
    final endY =
        imageBounds.offsetY + grenade.impactYRatio! * imageBounds.height;

    final lineColorVal = ref.watch(mapLineColorProvider);
    final lineOpacity = ref.watch(mapLineOpacityProvider);
    final lineColor = Color(lineColorVal).withValues(alpha: lineOpacity);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DashedLinePainter(
            start: Offset(startX, startY),
            end: Offset(endX, endY),
            color: lineColor,
            strokeWidth: 1.5 * scale,
            dashLength: 6 * scale,
            gapLength: 4 * scale,
          ),
        ),
      ),
    );
  }

  /// 构建出生点标记（方形 + 数字）- 带透明度，可点击创建道具
  Widget _buildSpawnPointMarker(
      SpawnPoint spawn,
      bool isCT,
      BoxConstraints constraints,
      double markerScale,
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds,
      int layerId,
      bool isEditMode) {
    final color = isCT ? Colors.blueAccent : Colors.amber;
    // Base size is 16, use FIXED half-size for positioning
    const double baseHalfSize = 8.0;

    // 计算标记在 Stack 中的实际位置（考虑图片偏移）
    final left =
        imageBounds.offsetX + spawn.x * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + spawn.y * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 点击出生点显示底部菜单
            _showSpawnPointBottomSheet(spawn, isCT, layerId);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  '${spawn.id}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示出生点底部菜单
  void _showSpawnPointBottomSheet(SpawnPoint spawn, bool isCT, int layerId) {
    final color = isCT ? Colors.blueAccent : Colors.amber;
    final teamName = isCT ? "CT" : "T";
    final isEditMode = ref.read(isEditModeProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2126),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${spawn.id}',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "$teamName 出生点 #${spawn.id}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "坐标: (${spawn.x.toStringAsFixed(3)}, ${spawn.y.toStringAsFixed(3)})",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (isEditMode)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // 在出生点位置创建道具
                    setState(() {
                      _tempTapPosition = Offset(spawn.x, spawn.y);
                    });
                    _createGrenade(layerId);
                  },
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text("在此位置创建道具"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "💡 开启编辑模式可在此位置创建道具",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// 构建出生点侧边栏（可折叠）
  Widget _buildSpawnPointSidebar(
      MapSpawnConfig config, int layerId, bool isEditMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 折叠/展开按钮
        GestureDetector(
          onTap: () => setState(
              () => _isSpawnSidebarExpanded = !_isSpawnSidebarExpanded),
          child: Container(
            width: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21).withValues(alpha: 0.9),
              border: Border(
                  left: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Center(
              child: Icon(
                _isSpawnSidebarExpanded
                    ? Icons.chevron_right
                    : Icons.chevron_left,
                color: Colors.greenAccent,
                size: 16,
              ),
            ),
          ),
        ),
        // 侧边栏内容
        if (_isSpawnSidebarExpanded)
          Container(
            width: 75,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21).withValues(alpha: 0.9),
            ),
            child: Column(
              children: [
                // 标题
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.place, color: Colors.greenAccent, size: 14),
                      SizedBox(width: 4),
                      Text("出生点",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                // 列表
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // CT 标题
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text("CT",
                                style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // CT 出生点列表
                        ...config.ctSpawns.map((spawn) => _buildSpawnListItem(
                            spawn, true, layerId, isEditMode)),
                        const SizedBox(height: 8),
                        // T 标题
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text("T",
                                style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // T 出生点列表
                        ...config.tSpawns.map((spawn) => _buildSpawnListItem(
                            spawn, false, layerId, isEditMode)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 构建出生点列表项
  Widget _buildSpawnListItem(
      SpawnPoint spawn, bool isCT, int layerId, bool isEditMode) {
    final color = isCT ? Colors.blueAccent : Colors.amber;
    return GestureDetector(
      onTap: () => _showSpawnPointBottomSheet(spawn, isCT, layerId),
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    '${spawn.id}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesBar(
      BuildContext context, FavoriteFolderService folderService) {
    return Container(
      height: 60,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: StreamBuilder<List<FolderWithGrenades>>(
        stream: _mapFavoritesStream,
        builder: (context, snapshot) {
          final allFolders = snapshot.data ?? const <FolderWithGrenades>[];
          final visibleFolders =
              allFolders.where((f) => f.grenades.isNotEmpty).toList();

          return Row(
            children: [
              IconButton(
                tooltip: '管理收藏夹',
                onPressed: () => _showFavoriteFolderManager(folderService),
                icon: const Icon(Icons.folder_open),
                color: Colors.orangeAccent,
              ),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : visibleFolders.isEmpty
                        ? Center(
                            child: Text(
                              "暂无收藏夹道具",
                              style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(
                                left: 4, right: 16, top: 8, bottom: 8),
                            itemCount: visibleFolders.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, index) {
                              final folderData = visibleFolders[index];
                              return ActionChip(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                                avatar: const Icon(Icons.folder,
                                    size: 14, color: Colors.orangeAccent),
                                label: Text(
                                  '${folderData.folder.name} (${folderData.grenades.length})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () => _showFavoriteFolderItemsSheet(
                                    folderService, folderData.folder.id),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showFavoriteFolderItemsSheet(
      FavoriteFolderService folderService, int folderId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: StreamBuilder<List<FolderWithGrenades>>(
            stream: folderService.watchMapFavorites(widget.gameMap.id),
            builder: (ctx, snapshot) {
              final folders = snapshot.data ?? const <FolderWithGrenades>[];
              FolderWithGrenades? folderData;
              for (final item in folders) {
                if (item.folder.id == folderId) {
                  folderData = item;
                  break;
                }
              }
              if (folderData == null) {
                return const Center(child: Text('收藏夹不存在或已删除'));
              }

              final grenades = folderData.grenades;
              return Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(Icons.folder, color: Colors.orangeAccent),
                    title: Text(folderData.folder.name),
                    subtitle: Text('${grenades.length} 个收藏道具'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: grenades.isEmpty
                        ? const Center(child: Text('该收藏夹暂无道具'))
                        : ListView.separated(
                            itemCount: grenades.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final g = grenades[index];
                              g.layer.loadSync();
                              final layerName = g.layer.value?.name ?? '未知楼层';
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  _getTypeIcon(g.type),
                                  color: _getTypeColor(g.type),
                                  size: 18,
                                ),
                                title: Text(
                                  g.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '$layerName · ${_getTypeName(g.type)} · ${_getTeamName(g.team)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'move') {
                                      await _showMoveFavoriteDialog(
                                          folderService,
                                          g,
                                          folderData!.folder.id);
                                    } else if (value == 'unfavorite') {
                                      await folderService.setFavorite(g.id,
                                          favorite: false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('已取消收藏'),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem<String>(
                                        value: 'move', child: Text('移动到其他收藏夹')),
                                    PopupMenuItem<String>(
                                        value: 'unfavorite',
                                        child: Text('取消收藏')),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _handleGrenadeTap(g, isEditing: false);
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showMoveFavoriteDialog(FavoriteFolderService folderService,
      Grenade grenade, int currentFolderId) async {
    final folders = await folderService.getFoldersByMap(widget.gameMap.id);
    final targets = folders.where((f) => f.id != currentFolderId).toList();
    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('暂无可移动的目标收藏夹'), duration: Duration(seconds: 1)));
      return;
    }
    if (!mounted) return;

    int? selectedFolderId = targets.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('移动到收藏夹'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: targets
                  .map((f) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          selectedFolderId == f.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: selectedFolderId == f.id
                              ? Theme.of(ctx).colorScheme.primary
                              : Theme.of(ctx).disabledColor,
                        ),
                        title: Text(f.name, overflow: TextOverflow.ellipsis),
                        onTap: () =>
                            setDialogState(() => selectedFolderId = f.id),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定')),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedFolderId == null) return;

    try {
      await folderService.moveFavorite(grenade.id, selectedFolderId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已移动收藏夹'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移动失败：$e'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _showFavoriteFolderManager(
      FavoriteFolderService folderService) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: StreamBuilder<List<FolderWithGrenades>>(
          stream: folderService.watchMapFavorites(widget.gameMap.id),
          builder: (ctx, snapshot) {
            final folders = snapshot.data ?? const <FolderWithGrenades>[];
            return Column(
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.folder_open, color: Colors.orangeAccent),
                  title: const Text('收藏夹管理'),
                  subtitle: Text('共 ${folders.length} 个收藏夹'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '新建收藏夹',
                    onPressed: () => _showCreateFavoriteFolderDialog(
                        folderService,
                        context: ctx),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: folders.isEmpty
                      ? const Center(child: Text('暂无收藏夹'))
                      : ListView.separated(
                          itemCount: folders.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final folderData = folders[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder,
                                  color: Colors.orangeAccent),
                              title: Text(
                                folderData.folder.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${folderData.grenades.length} 个道具',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(ctx).textTheme.bodySmall?.color,
                                ),
                              ),
                              onTap: () => _showFavoriteFolderItemsSheet(
                                  folderService, folderData.folder.id),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () =>
                                        _showRenameFavoriteFolderDialog(
                                            folderService, folderData.folder,
                                            context: ctx),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: Colors.redAccent),
                                    onPressed: () =>
                                        _showDeleteFavoriteFolderDialog(
                                            folderService, folderData),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCreateFavoriteFolderDialog(
      FavoriteFolderService folderService,
      {BuildContext? context}) async {
    final ctx = context ?? this.context;
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入收藏夹名称',
          ),
          onSubmitted: (_) => Navigator.pop(dialogCtx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('创建')),
        ],
      ),
    );

    if (created != true) return;

    try {
      await folderService.createFolder(widget.gameMap.id, controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
          content: Text('收藏夹已创建'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('创建失败：$e'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _showRenameFavoriteFolderDialog(
      FavoriteFolderService folderService, FavoriteFolder folder,
      {BuildContext? context}) async {
    final ctx = context ?? this.context;
    final controller = TextEditingController(text: folder.name);
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('重命名收藏夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入新名称',
          ),
          onSubmitted: (_) => Navigator.pop(dialogCtx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('保存')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await folderService.renameFolder(folder.id, controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
          content: Text('收藏夹已重命名'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('重命名失败：$e'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _showDeleteFavoriteFolderDialog(
      FavoriteFolderService folderService,
      FolderWithGrenades folderData) async {
    final folder = folderData.folder;
    final count = folderData.grenades.length;

    if (count == 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除收藏夹'),
          content: Text('确认删除收藏夹「${folder.name}」吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (confirmed != true) return;
      await folderService.deleteFolder(
          folder.id, FavoriteFolderDeleteStrategy.unfavorite);
      return;
    }

    final strategy = await showDialog<FavoriteFolderDeleteStrategy>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除非空收藏夹'),
        content: Text('收藏夹「${folder.name}」中有 $count 个道具。\n请选择删除后如何处理这些收藏道具：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, FavoriteFolderDeleteStrategy.unfavorite),
            child: const Text('取消收藏'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, FavoriteFolderDeleteStrategy.moveToDefault),
            child: const Text('迁移到默认夹'),
          ),
        ],
      ),
    );

    if (strategy == null) return;

    try {
      await folderService.deleteFolder(folder.id, strategy);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('收藏夹已删除'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e'), duration: Duration(seconds: 1)));
    }
  }

  /// 显示标签筛选底部弹窗
  void _showTagFilterSheet(int layerId) async {
    if (!kEnableGrenadeTags) return;
    final isar = ref.read(isarProvider);
    final tagService = TagService(isar);
    await tagService.initializeSystemTags(
        widget.gameMap.id, widget.gameMap.name);
    final allTags = await tagService.getAllTags(widget.gameMap.id);
    final areaTagIds =
        (await isar.mapAreas.filter().mapIdEqualTo(widget.gameMap.id).findAll())
            .map((a) => a.tagId)
            .toSet();
    final tags = allTags
        .where((tag) =>
            tag.dimension != TagDimension.area || areaTagIds.contains(tag.id))
        .toList();
    final validTagIds = tags.map((e) => e.id).toSet();
    final selectedBefore = ref.read(selectedTagIdsProvider);
    final selectedSanitized =
        selectedBefore.where((id) => validTagIds.contains(id)).toSet();
    if (selectedBefore.length != selectedSanitized.length) {
      ref.read(selectedTagIdsProvider.notifier).state = selectedSanitized;
    }
    if (!mounted) return;
    Set<int> selectedIds = Set<int>.from(
      ref.read(selectedTagIdsProvider),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final grouped = <int, List<Tag>>{};
        for (final tag in tags) {
          grouped.putIfAbsent(tag.dimension, () => []).add(tag);
        }
        return Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.label, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text('标签筛选',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).textTheme.titleLarge?.color)),
                const Spacer(),
                if (selectedIds.isNotEmpty)
                  TextButton(
                      onPressed: () {
                        selectedIds = {};
                        ref.read(selectedTagIdsProvider.notifier).state =
                            selectedIds;
                        setSheetState(() {});
                      },
                      child: const Text('清除')),
                // 区域管理按钮
                IconButton(
                  icon: const Icon(Icons.map_outlined, color: Colors.grey),
                  tooltip: '管理区域',
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                AreaManagerScreen(gameMap: widget.gameMap)));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.grey),
                  tooltip: '管理标签',
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TagManagerScreen(
                                mapId: widget.gameMap.id,
                                mapName: widget.gameMap.name)));
                  },
                ),
              ]),
              if (selectedIds.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('已选 ${selectedIds.length} 个标签',
                        style: TextStyle(
                            color: Theme.of(ctx).textTheme.bodySmall?.color,
                            fontSize: 12))),
              const SizedBox(height: 8),
              Flexible(
                child: tags.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('暂无标签，点击右上角管理',
                                style: TextStyle(
                                    color: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.color))))
                    : ListView(
                        shrinkWrap: true,
                        children: grouped.entries
                            .where((e) => e.key != TagDimension.role)
                            .map((e) => _buildTagDimensionGroup(
                                    e.key, e.value, selectedIds, (tagId) {
                                  if (selectedIds.contains(tagId)) {
                                    selectedIds.remove(tagId);
                                  } else {
                                    selectedIds.add(tagId);
                                  }
                                  ref
                                      .read(selectedTagIdsProvider.notifier)
                                      .state = Set<int>.from(selectedIds);
                                }, setSheetState))
                            .toList()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('确定'))),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTagDimensionGroup(
      int dimension,
      List<Tag> tags,
      Set<int> selectedIds,
      void Function(int tagId) onToggleTag,
      void Function(void Function()) setSheetState) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(TagDimension.getName(dimension),
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500))),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            final isSelected = selectedIds.contains(tag.id);
            final color = Color(tag.colorValue);
            return GestureDetector(
              onTap: () {
                onToggleTag(tag.id);
                setSheetState(() {});
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: isSelected ? color : color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            isSelected ? color : color.withValues(alpha: 0.4))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isSelected)
                    const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child:
                            Icon(Icons.check, size: 14, color: Colors.white)),
                  Text(tag.name,
                      style: TextStyle(
                          fontSize: 13,
                          color: isSelected ? Colors.white : color)),
                ]),
              ),
            );
          }).toList()),
      const SizedBox(height: 12),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = ref.watch(isEditModeProvider);
    final layerIndex = ref.watch(selectedLayerIndexProvider);
    final teamFilter = ref.watch(teamFilterProvider);
    final onlyFav = ref.watch(onlyFavoritesProvider);
    final selectedTypes = ref.watch(typeFilterProvider);
    final showSpawnPoints = ref.watch(showSpawnPointsProvider);

    // 获取当前地图的出生点数据
    final mapName = widget.gameMap.name.toLowerCase();
    final spawnConfig = spawnPointData[mapName];

    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final currentLayer = (layers.isNotEmpty && layerIndex < layers.length)
        ? layers[layerIndex]
        : (layers.isNotEmpty ? layers.last : null);
    if (currentLayer == null) {
      return const Scaffold(body: Center(child: Text("数据错误：无楼层信息")));
    }

    final grenadesAsync = ref.watch(_filteredGrenadesProvider(currentLayer.id));
    final showMapGrenadeListPanel =
        globalSettingsService?.getShowMapGrenadeList() ?? false;

    final folderService = _favoriteFolderService;
    final allMapGrenades = _cachedAllMapGrenades;
    final allMapGrenadeEntries = _cachedAllMapGrenadeEntries;
    final isar = ref.read(isarProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.1))),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // 地图名作为搜索栏前缀
                    Text(
                      widget.gameMap.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 1,
                      height: 16,
                      color:
                          Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    ),
                    Icon(Icons.search,
                        color: Theme.of(context).hintColor, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Autocomplete<Grenade>(
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Grenade>.empty();
                          }
                          final query = textEditingValue.text.toLowerCase();
                          return allMapGrenades.where((g) {
                            // 匹配标题
                            if (g.title.toLowerCase().contains(query)) {
                              return true;
                            }
                            // 匹配标签名
                            final grenadeTags = isar.grenadeTags
                                .filter()
                                .grenadeIdEqualTo(g.id)
                                .findAllSync();
                            for (final gt in grenadeTags) {
                              final tag = isar.tags.getSync(gt.tagId);
                              if (tag != null &&
                                  tag.name.toLowerCase().contains(query)) {
                                return true;
                              }
                            }
                            return false;
                          });
                        },
                        displayStringForOption: (g) => g.title,
                        onSelected: _onSearchResultSelected,
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              color: const Color(0xFF2A2D33),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: MediaQuery.of(context).size.width *
                                    0.6, // Adjust width as needed
                                constraints:
                                    const BoxConstraints(maxHeight: 250),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    option.layer.loadSync();
                                    return ListTile(
                                        title: Text(option.title,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        subtitle: Text(
                                            "${option.layer.value?.name ?? ''} • ${_getTypeName(option.type)}",
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12)),
                                        onTap: () => onSelected(option));
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        fieldViewBuilder: (context, controller, focusNode,
                                onFieldSubmitted) =>
                            TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color),
                          decoration: const InputDecoration(
                            hintText: "搜索道具...",
                            hintStyle:
                                TextStyle(color: Colors.grey, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Row(children: [
                Text(isEditMode ? "编辑" : "浏览",
                    style: TextStyle(
                        color: isEditMode ? Colors.redAccent : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                Transform.scale(
                  scale: 0.7,
                  child: Switch(
                      value: isEditMode,
                      activeThumbColor: Colors.redAccent,
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                      onChanged: (val) {
                        ref.read(isEditModeProvider.notifier).state = val;
                        if (val) {
                          _showGrenadeCreateModeHint();
                        }
                      }),
                ),
              ])),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  _buildFilterChip("全部", TeamType.all, teamFilter, Colors.grey),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      "通用", TeamType.onlyAll, teamFilter, Colors.white),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      "CT", TeamType.ct, teamFilter, Colors.blueAccent),
                  const SizedBox(width: 8),
                  _buildFilterChip("T", TeamType.t, teamFilter, Colors.amber),
                  const SizedBox(width: 20),
                  FilterChip(
                      label: const Icon(Icons.star,
                          size: 16, color: Colors.yellowAccent),
                      selected: onlyFav,
                      onSelected: (val) =>
                          ref.read(onlyFavoritesProvider.notifier).state = val,
                      backgroundColor: Colors.white10,
                      selectedColor: Colors.orange.withValues(alpha: 0.3),
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  const SizedBox(width: 8),
                  FilterChip(
                      label: const Text("出生点", style: TextStyle(fontSize: 12)),
                      selected: showSpawnPoints,
                      onSelected: (val) => ref
                          .read(showSpawnPointsProvider.notifier)
                          .state = val,
                      backgroundColor: Colors.white10,
                      selectedColor: Colors.green.withValues(alpha: 0.3),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                          color: showSpawnPoints
                              ? Colors.greenAccent
                              : Colors.grey),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                ]))),
      ),
      body: Column(
        children: [
          // 地图区域（自适应填充剩余空间）
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(children: [
                Positioned.fill(
                    child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent) {
                            _handleMouseWheelZoom(event, constraints);
                          }
                        },
                        child: PhotoView.customChild(
                          key: ValueKey(currentLayer.id),
                          controller: _photoViewController,
                          initialScale: PhotoViewComputedScale.covered,
                          minScale: PhotoViewComputedScale.contained * 0.8,
                          maxScale: PhotoViewComputedScale.covered * 5.0,
                          child: StreamBuilder<PhotoViewControllerValue>(
                            stream: _photoViewController.outputStateStream,
                            builder: (context, snapshot) {
                              final controllerValue = snapshot.data;
                              final double scale =
                                  controllerValue?.scale ?? 1.0;
                              final Offset position =
                                  controllerValue?.position ??
                                      _photoViewController.position;
                              final double markerScale = 1.0 / scale;

                              // 计算 BoxFit.contain 模式下图片的实际显示区域
                              final imageBounds = _getImageBounds(
                                  constraints.maxWidth, constraints.maxHeight);
                              final visibleRatioRect =
                                  _getVisibleImageRatioRect(
                                constraints: constraints,
                                scale: scale,
                                position: position,
                                imageBounds: imageBounds,
                              );
                              final pointCullMarginX = 28 / imageBounds.width;
                              final pointCullMarginY = 28 / imageBounds.height;
                              final lineCullMarginX = 40 / imageBounds.width;
                              final lineCullMarginY = 40 / imageBounds.height;

                              return GestureDetector(
                                  onTapUp: (d) => _handleTap(
                                      d,
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                      currentLayer.id),
                                  onLongPressStart: (d) {
                                    if (_getGrenadeCreateMode() !=
                                        _grenadeCreateModeLongPress) {
                                      return;
                                    }
                                    _tryCreateGrenadeAtGlobalPosition(
                                        d.globalPosition, currentLayer.id);
                                  },
                                  child: Stack(key: _stackKey, children: [
                                    Image.asset(currentLayer.assetPath,
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        fit: BoxFit.contain),
                                    // 道具点位标记和所有依赖选中状态的元素
                                    ...grenadesAsync.when(
                                        data: (list) {
                                          final clusterThreshold =
                                              _getAdaptiveClusterThreshold(
                                            scale: scale,
                                            grenadeCount: list.length,
                                          );
                                          bool isThrowPointVisible(Grenade g) =>
                                              _isRatioPointVisible(
                                                g.xRatio,
                                                g.yRatio,
                                                visibleRect: visibleRatioRect,
                                                marginX: pointCullMarginX,
                                                marginY: pointCullMarginY,
                                              );
                                          bool isImpactPointVisible(Grenade g) {
                                            final x = g.impactXRatio;
                                            final y = g.impactYRatio;
                                            if (x == null || y == null) {
                                              return false;
                                            }
                                            return _isRatioPointVisible(
                                              x,
                                              y,
                                              visibleRect: visibleRatioRect,
                                              marginX: pointCullMarginX,
                                              marginY: pointCullMarginY,
                                            );
                                          }

                                          // 根据当前筛选结果过滤选中的grenades
                                          final filteredIds =
                                              list.map((g) => g.id).toSet();
                                          final filteredSelectedGrenades =
                                              _selectedClusterForImpact
                                                      ?.grenades
                                                      .where((g) => filteredIds
                                                          .contains(g.id))
                                                      .toList() ??
                                                  [];

                                          final widgets = <Widget>[];
                                          // 爆点区域显示（最底层）
                                          if (_selectedClusterForImpact !=
                                              null) {
                                            // 根据类型和分组过滤器筛选
                                            var areaGrenades =
                                                filteredSelectedGrenades
                                                    .where((g) {
                                              if (_selectedImpactTypeFilter !=
                                                      null &&
                                                  g.type !=
                                                      _selectedImpactTypeFilter) {
                                                return false;
                                              }
                                              if (_selectedImpactGroupId !=
                                                      null &&
                                                  g.impactGroupId !=
                                                      _selectedImpactGroupId) {
                                                return false;
                                              }
                                              return true;
                                            });

                                            // 去重逻辑：避免重复绘制相同的 strokes 导致透明度叠加
                                            final visitedStrokes = <String>{};
                                            for (final g in areaGrenades) {
                                              if (g.impactAreaStrokes != null &&
                                                  g.impactAreaStrokes!
                                                      .isNotEmpty &&
                                                  !visitedStrokes.contains(
                                                      g.impactAreaStrokes)) {
                                                visitedStrokes
                                                    .add(g.impactAreaStrokes!);
                                                widgets.add(
                                                    _buildImpactAreaOverlay(
                                                        g, constraints));
                                              }
                                            }
                                          }

                                          if (_isImpactMode) {
                                            // 爆点模式：显示爆点聚合
                                            final impactClusters =
                                                _getImpactClusters(
                                              list,
                                              threshold: clusterThreshold,
                                            );
                                            final denseMarkerStyle =
                                                _shouldUseDenseMarkerStyle(
                                              grenadeCount: list.length,
                                              clusterCount:
                                                  impactClusters.length,
                                            );
                                            final visibleImpactClusters =
                                                impactClusters
                                                    .where((c) =>
                                                        _isRatioPointVisible(
                                                          c.xRatio,
                                                          c.yRatio,
                                                          visibleRect:
                                                              visibleRatioRect,
                                                          marginX:
                                                              pointCullMarginX,
                                                          marginY:
                                                              pointCullMarginY,
                                                        ))
                                                    .toList(growable: false);

                                            widgets.addAll(
                                                visibleImpactClusters.map((c) =>
                                                    _buildImpactClusterMarker(
                                                        c,
                                                        constraints,
                                                        isEditMode,
                                                        currentLayer.id,
                                                        markerScale,
                                                        imageBounds,
                                                        denseStyle:
                                                            denseMarkerStyle)));
                                          } else {
                                            // 标准模式：显示投掷点聚合
                                            final cachedClusters =
                                                _getThrowClusters(
                                              list,
                                              threshold: clusterThreshold,
                                            );

                                            // 如果有选中的点位，只显示选中的点位
                                            final visibleClusters =
                                                _selectedClusterForImpact ==
                                                        null
                                                    ? cachedClusters
                                                    : cachedClusters
                                                        .where((c) =>
                                                            _isSameCluster(c,
                                                                _selectedClusterForImpact))
                                                        .toList();
                                            final visibleClustersInViewport =
                                                visibleClusters
                                                    .where((c) =>
                                                        _isRatioPointVisible(
                                                          c.xRatio,
                                                          c.yRatio,
                                                          visibleRect:
                                                              visibleRatioRect,
                                                          marginX:
                                                              pointCullMarginX,
                                                          marginY:
                                                              pointCullMarginY,
                                                        ))
                                                    .toList(growable: false);
                                            final denseMarkerStyle =
                                                _shouldUseDenseMarkerStyle(
                                              grenadeCount: list.length,
                                              clusterCount:
                                                  cachedClusters.length,
                                            );

                                            widgets.addAll(visibleClustersInViewport
                                                .map((c) => _buildClusterMarker(
                                                    c,
                                                    constraints,
                                                    isEditMode,
                                                    currentLayer.id,
                                                    markerScale,
                                                    imageBounds,
                                                    denseStyle:
                                                        denseMarkerStyle)));
                                          }

                                          // 爆点连线
                                          if (_selectedClusterForImpact !=
                                              null) {
                                            // 根据类型和分组过滤器筛选连线
                                            final lineGrenades =
                                                filteredSelectedGrenades
                                                    .where((g) {
                                              if (_selectedImpactTypeFilter !=
                                                      null &&
                                                  g.type !=
                                                      _selectedImpactTypeFilter) {
                                                return false;
                                              }
                                              if (_selectedImpactGroupId !=
                                                      null &&
                                                  g.impactGroupId !=
                                                      _selectedImpactGroupId) {
                                                return false;
                                              }
                                              return true;
                                            });
                                            widgets.addAll(lineGrenades
                                                .where((g) =>
                                                    g.impactXRatio != null &&
                                                    g.impactYRatio != null &&
                                                    _isRatioSegmentVisible(
                                                      g.xRatio,
                                                      g.yRatio,
                                                      g.impactXRatio!,
                                                      g.impactYRatio!,
                                                      visibleRect:
                                                          visibleRatioRect,
                                                      marginX: lineCullMarginX,
                                                      marginY: lineCullMarginY,
                                                    ) &&
                                                    g.type !=
                                                        GrenadeType.wallbang)
                                                .map((g) =>
                                                    _buildConnectionLine(
                                                        g,
                                                        markerScale,
                                                        imageBounds)));
                                          }
                                          // 标准模式下的爆点标记（选中点位时显示）
                                          if (!_isImpactMode &&
                                              _selectedClusterForImpact !=
                                                  null) {
                                            // 检查当前缩放级别下投掷点是否仍然会聚合
                                            final subClusters = clusterGrenades(
                                                filteredSelectedGrenades,
                                                threshold: clusterThreshold);

                                            if (subClusters.length == 1 &&
                                                filteredSelectedGrenades
                                                        .length >
                                                    1) {
                                              // 仍然聚合：显示聚合图标（带光圈效果）
                                              if (_isRatioPointVisible(
                                                subClusters.first.xRatio,
                                                subClusters.first.yRatio,
                                                visibleRect: visibleRatioRect,
                                                marginX: pointCullMarginX,
                                                marginY: pointCullMarginY,
                                              )) {
                                                widgets.add(
                                                    _buildSelectedClusterMarker(
                                                        subClusters.first,
                                                        constraints,
                                                        markerScale,
                                                        imageBounds));
                                              }
                                            } else {
                                              // 会分开：显示选中cluster内的所有投掷点标记（带光圈效果）
                                              widgets.addAll(
                                                  filteredSelectedGrenades
                                                      .where(
                                                          isThrowPointVisible)
                                                      .map((g) =>
                                                          _buildSelectedThrowPointMarker(
                                                              g,
                                                              constraints,
                                                              markerScale,
                                                              imageBounds)));
                                            }
                                            // 显示爆点标记
                                            widgets.addAll(
                                                filteredSelectedGrenades
                                                    .where((g) =>
                                                        g.impactXRatio != null &&
                                                        g.impactYRatio !=
                                                            null &&
                                                        isImpactPointVisible(
                                                            g) &&
                                                        g.type !=
                                                            GrenadeType
                                                                .wallbang)
                                                    .map((g) =>
                                                        _buildImpactMarker(
                                                            g,
                                                            constraints,
                                                            markerScale,
                                                            imageBounds)));
                                          }
                                          // 爆点模式下的投掷点标记（选中爆点时显示）
                                          if (_isImpactMode &&
                                              _selectedClusterForImpact !=
                                                  null) {
                                            // 根据类型和分组过滤器筛选投掷点
                                            final displayGrenades =
                                                filteredSelectedGrenades
                                                    .where((g) {
                                              if (_selectedImpactTypeFilter !=
                                                      null &&
                                                  g.type !=
                                                      _selectedImpactTypeFilter) {
                                                return false;
                                              }
                                              if (_selectedImpactGroupId !=
                                                      null &&
                                                  g.impactGroupId !=
                                                      _selectedImpactGroupId) {
                                                return false;
                                              }
                                              return true;
                                            }).toList();
                                            widgets.addAll(displayGrenades
                                                .where(isThrowPointVisible)
                                                .map((g) =>
                                                    _buildThrowPointMarker(
                                                        g,
                                                        constraints,
                                                        markerScale,
                                                        imageBounds)));
                                          }
                                          return widgets;
                                        },
                                        error: (_, __) => [],
                                        loading: () => []),
                                    // 移动单个爆点时显示其原始位置及连线（无论在哪种模式）
                                    if (_movingSingleImpactGrenade != null) ...[
                                      if (_movingSingleImpactGrenade!.type !=
                                          GrenadeType.wallbang)
                                        _buildConnectionLine(
                                            _movingSingleImpactGrenade!,
                                            markerScale,
                                            imageBounds),
                                      _buildImpactMarker(
                                          _movingSingleImpactGrenade!,
                                          constraints,
                                          markerScale,
                                          imageBounds),
                                    ],
                                    // 移动投掷点时显示原始位置标记（爆点模式）
                                    if (_isImpactMode &&
                                        _movingSingleGrenade != null)
                                      _buildThrowPointMarker(
                                          _movingSingleGrenade!,
                                          constraints,
                                          markerScale,
                                          imageBounds),
                                    // 出生点标记（后渲染，在上层，但不响应点击）
                                    if (showSpawnPoints && spawnConfig != null)
                                      IgnorePointer(
                                        child: Stack(
                                          children: [
                                            ...spawnConfig.ctSpawns.map(
                                                (spawn) =>
                                                    _buildSpawnPointMarker(
                                                        spawn,
                                                        true,
                                                        constraints,
                                                        markerScale,
                                                        imageBounds,
                                                        currentLayer.id,
                                                        isEditMode)),
                                            ...spawnConfig.tSpawns.map(
                                                (spawn) =>
                                                    _buildSpawnPointMarker(
                                                        spawn,
                                                        false,
                                                        constraints,
                                                        markerScale,
                                                        imageBounds,
                                                        currentLayer.id,
                                                        isEditMode)),
                                          ],
                                        ),
                                      ),
                                    if (_draggingCluster != null &&
                                        _dragOffset != null)
                                      Positioned(
                                          left: imageBounds.offsetX +
                                              _dragOffset!.dx *
                                                  imageBounds.width -
                                              14.0, // Fixed offset, not scaled
                                          top: imageBounds.offsetY +
                                              _dragOffset!.dy *
                                                  imageBounds.height -
                                              14.0, // Fixed offset, not scaled
                                          child: Transform.scale(
                                            scale: markerScale,
                                            alignment: Alignment.center,
                                            child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                    color: Colors.cyan
                                                        .withValues(alpha: 0.6),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: Colors.cyan,
                                                        width: 2)),
                                                child: const Icon(
                                                    Icons.open_with,
                                                    size: 14,
                                                    color: Colors.white)),
                                          )),
                                    if (_tempTapPosition != null)
                                      Positioned(
                                          left: imageBounds.offsetX +
                                              _tempTapPosition!.dx *
                                                  imageBounds.width -
                                              12.0, // Fixed offset, not scaled
                                          top: imageBounds.offsetY +
                                              _tempTapPosition!.dy *
                                                  imageBounds.height -
                                              12.0, // Fixed offset, not scaled
                                          child: Transform.scale(
                                            scale: markerScale,
                                            child: const Icon(Icons.add_circle,
                                                color: Colors.greenAccent,
                                                size: 24),
                                          )),
                                  ]));
                            },
                          ),
                        ))),
                // 顶部UI
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(16),
                                      border:
                                          Border.all(color: Colors.white12)),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildTypeFilterBtn(
                                            selectedTypes,
                                            GrenadeType.smoke,
                                            "烟",
                                            Icons.cloud,
                                            Colors.grey),
                                        _buildTypeFilterBtn(
                                            selectedTypes,
                                            GrenadeType.flash,
                                            "闪",
                                            Icons.flash_on,
                                            Colors.yellow),
                                        _buildTypeFilterBtn(
                                            selectedTypes,
                                            GrenadeType.molotov,
                                            "火",
                                            Icons.local_fire_department,
                                            Colors.red),
                                        _buildTypeFilterBtn(
                                            selectedTypes,
                                            GrenadeType.he,
                                            "雷",
                                            Icons.trip_origin,
                                            Colors.green),
                                        _buildTypeFilterBtn(
                                            selectedTypes,
                                            GrenadeType.wallbang,
                                            "穿",
                                            Icons.apps,
                                            Colors.cyan),
                                      ])),
                              const SizedBox(height: 10),
                              /* Search bar moved to AppBar */
                            ],
                          ))),
                ),
                // 爆点模式切换按钮
                Positioned(
                  left: 16,
                  bottom: !isEditMode ? 80 : 30, // 与右边按钮组保持一致
                  child: FloatingActionButton.small(
                    heroTag: 'impact_mode_toggle',
                    backgroundColor:
                        _isImpactMode ? Colors.redAccent : Colors.blueGrey,
                    onPressed: () {
                      setState(() {
                        _isImpactMode = !_isImpactMode;
                        // 切换模式时清除选中状态
                        _selectedClusterForImpact = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(_isImpactMode ? "已开启爆点浏览模式" : "已切换回标准模式"),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ));
                    },
                    child: Icon(
                      _isImpactMode
                          ? FontAwesomeIcons.crosshairs
                          : FontAwesomeIcons.locationDot,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),

                // 右下角按钮组（标签筛选 + 楼层切换）
                Positioned(
                  right: 16,
                  bottom: !isEditMode ? 80 : 30,
                  child: Column(
                    children: [
                      if (kEnableGrenadeTags)
                        FloatingActionButton.small(
                          heroTag: "btn_tag_filter",
                          backgroundColor: Colors.blueGrey,
                          onPressed: () => _showTagFilterSheet(currentLayer.id),
                          child: const Icon(Icons.label_outline,
                              color: Colors.white),
                        ),
                      if (layers.length > 1) ...[
                        SizedBox(height: kEnableGrenadeTags ? 16 : 0),
                        FloatingActionButton.small(
                            heroTag: "btn_up",
                            backgroundColor: layerIndex < layers.length - 1
                                ? Colors.orange
                                : Colors.grey[800],
                            onPressed: layerIndex < layers.length - 1
                                ? () => ref
                                    .read(selectedLayerIndexProvider.notifier)
                                    .state++
                                : null,
                            child: const Icon(Icons.arrow_upward)),
                        Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text("F${layerIndex + 1}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold))),
                        FloatingActionButton.small(
                            heroTag: "btn_down",
                            backgroundColor: layerIndex > 0
                                ? Colors.orange
                                : Colors.grey[800],
                            onPressed: layerIndex > 0
                                ? () => ref
                                    .read(selectedLayerIndexProvider.notifier)
                                    .state--
                                : null,
                            child: const Icon(Icons.arrow_downward)),
                      ],
                    ],
                  ),
                ),
                // 出生点侧边栏
                if (showSpawnPoints &&
                    spawnConfig != null &&
                    _selectedClusterForImpact == null)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: isEditMode ? 0 : 60,
                    child: _buildSpawnPointSidebar(
                        spawnConfig, currentLayer.id, isEditMode),
                  ),
                // 底部收藏栏（仅在未选中点位时显示）
                if (!isEditMode && _selectedClusterForImpact == null)
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildFavoritesBar(context, folderService)),
              ]);
            }),
          ),
          // 底部道具列表面板（选中点位时显示）
          if (_selectedClusterForImpact != null)
            _buildClusterListPanel(currentLayer.id, isEditMode)
          else if (showMapGrenadeListPanel)
            _buildAllMapGrenadesPanel(
              allMapGrenadeEntries,
              isEditMode,
              currentLayer.id,
            ),
        ],
      ),
    );
  }

  /// 构建底部道具列表面板
  Widget _buildClusterListPanel(int layerId, bool isEditMode) {
    final cluster = _selectedClusterForImpact!;

    return Consumer(
      builder: (context, ref, _) {
        final grenadesAsync = ref.watch(_filteredGrenadesProvider(layerId));
        return grenadesAsync.when(
          data: (filteredList) {
            // 根据筛选结果过滤cluster中的grenades
            final filteredIds = filteredList.map((g) => g.id).toSet();
            final grenades = cluster.grenades
                .where((g) => filteredIds.contains(g.id))
                .toList();
            // 如果所有道具都被筛选掉，自动关闭面板
            if (grenades.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _closeClusterPanel();
                }
              });
              return const SizedBox.shrink();
            }
            return _buildClusterListPanelContent(
                grenades, cluster, layerId, isEditMode);
          },
          error: (_, __) => const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
        );
      },
    );
  }

  /// 构建底部道具列表面板内容
  Widget _buildClusterListPanelContent(List<Grenade> grenades,
      GrenadeCluster cluster, int layerId, bool isEditMode) {
    // 多选删除模式状态
    bool isMultiSelectMode = false;
    Set<int> selectedIds = {};

    // 获取道具类型分组
    Map<int, List<Grenade>> getTypeGroups() {
      final groups = <int, List<Grenade>>{};
      for (final g in grenades) {
        groups.putIfAbsent(g.type, () => []).add(g);
      }
      return groups;
    }

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: FutureBuilder<List<ImpactGroup>>(
        future: _loadImpactGroups(cluster, layerId),
        builder: (context, snapshot) {
          final customGroups = snapshot.data ?? [];
          return StatefulBuilder(
            builder: (context, setPanelState) {
              // 计算当前显示的道具列表
              List<Grenade> displayGrenades;
              if (_selectedImpactGroupId != null) {
                if (_selectedImpactGroupId == -1) {
                  // 未分类：显示所有 impactGroupId 为 null 的投掷点
                  displayGrenades =
                      grenades.where((g) => g.impactGroupId == null).toList();
                } else {
                  // 自定义分组：显示属于该分组的投掷点
                  displayGrenades = grenades
                      .where((g) => g.impactGroupId == _selectedImpactGroupId)
                      .toList();
                }
              } else if (_selectedImpactTypeFilter != null) {
                displayGrenades = grenades
                    .where((g) => g.type == _selectedImpactTypeFilter)
                    .toList();
              } else {
                displayGrenades = grenades;
              }
              // 计算未分类道具
              final unassignedGrenades =
                  grenades.where((g) => g.impactGroupId == null).toList();
              // 浏览模式下：只有一个分组且无未分类道具 -> 自动选中该分组
              if (!isEditMode &&
                  customGroups.length == 1 &&
                  unassignedGrenades.isEmpty &&
                  _selectedImpactGroupId == null &&
                  _selectedImpactTypeFilter == null &&
                  _isImpactMode) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedImpactGroupId == null) {
                    setState(() {
                      _selectedImpactGroupId = customGroups.first.id;
                      _selectedImpactTypeFilter = customGroups.first.type;
                    });
                  }
                });
              }
              final showTypeSelector = _isImpactMode &&
                  grenades.length > 1 &&
                  _selectedImpactTypeFilter == null &&
                  _selectedImpactGroupId == null;
              return Column(
                children: [
                  // 头部
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // 返回按钮（选择了类型或分组后显示）
                        if ((_selectedImpactTypeFilter != null ||
                                _selectedImpactGroupId != null) &&
                            _isImpactMode)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedImpactTypeFilter = null;
                                _selectedImpactGroupId = null;
                              });
                              setPanelState(() {
                                isMultiSelectMode = false;
                                selectedIds.clear();
                              });
                            },
                            icon: const Icon(Icons.arrow_back),
                            color: Colors.grey,
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        Text(
                          showTypeSelector
                              ? "该爆点共 ${grenades.length} 个道具"
                              : isMultiSelectMode
                                  ? "已选择 ${selectedIds.length} 个"
                                  : _selectedImpactGroupId != null
                                      ? "${_selectedImpactGroupId == -1 ? "未分类" : (customGroups.any((g) => g.id == _selectedImpactGroupId) ? customGroups.firstWhere((g) => g.id == _selectedImpactGroupId).name : "未知分组")} (${displayGrenades.length})"
                                      : _selectedImpactTypeFilter != null
                                          ? "${_getTypeName(_selectedImpactTypeFilter!)} (${displayGrenades.length})"
                                          : grenades.length == 1
                                              ? (grenades.first.description ??
                                                  "未命名爆点")
                                              : "该点位共 ${grenades.length} 个道具",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        if (isEditMode &&
                            !showTypeSelector &&
                            !isMultiSelectMode &&
                            ((_selectedImpactGroupId != null &&
                                    _selectedImpactGroupId != -1) ||
                                (_selectedImpactGroupId == null &&
                                    _selectedImpactTypeFilter == null &&
                                    grenades.length == 1)))
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16),
                            padding: const EdgeInsets.only(left: 4),
                            constraints: const BoxConstraints(),
                            tooltip: "重命名",
                            color: Colors.grey,
                            onPressed: () {
                              ImpactGroup? group;
                              if (_selectedImpactGroupId != null) {
                                try {
                                  group = customGroups.firstWhere(
                                      (g) => g.id == _selectedImpactGroupId);
                                } catch (_) {}
                              }
                              _showRenameImpactPointDialog(context,
                                  group: group,
                                  grenade: grenades.length == 1 && group == null
                                      ? grenades.first
                                      : null, onSuccess: () {
                                setState(() {});
                                setPanelState(() {});
                              });
                            },
                          ),
                        const Spacer(),
                        if (isEditMode && !showTypeSelector)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 批量删除按钮
                              if (isMultiSelectMode)
                                TextButton.icon(
                                  onPressed: selectedIds.isEmpty
                                      ? null
                                      : () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: Theme.of(ctx)
                                                  .colorScheme
                                                  .surface,
                                              title: Text("批量删除",
                                                  style: TextStyle(
                                                      color: Theme.of(ctx)
                                                          .textTheme
                                                          .bodyLarge
                                                          ?.color)),
                                              content: Text(
                                                  "确定要删除选中的 ${selectedIds.length} 个道具吗？",
                                                  style: TextStyle(
                                                      color: Theme.of(ctx)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.color)),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, false),
                                                    child: const Text("取消")),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, true),
                                                    child: const Text("删除",
                                                        style: TextStyle(
                                                            color:
                                                                Colors.red))),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            final toDelete = <Grenade>[];
                                            for (final id in selectedIds) {
                                              final g = grenades.firstWhere(
                                                  (g) => g.id == id,
                                                  orElse: () => grenades.first);
                                              if (!toDelete
                                                  .any((x) => x.id == g.id)) {
                                                toDelete.add(g);
                                              }
                                            }
                                            await _deleteGrenadesInBatch(
                                                toDelete);
                                            if (grenades.isEmpty ||
                                                toDelete.length ==
                                                    grenades.length) {
                                              _closeClusterPanel();
                                            } else {
                                              setPanelState(() {
                                                isMultiSelectMode = false;
                                                selectedIds.clear();
                                              });
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: Text("删除(${selectedIds.length})"),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                )
                              else
                                IconButton(
                                  onPressed: () {
                                    setPanelState(() {
                                      isMultiSelectMode = true;
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                  color: Colors.red,
                                  tooltip: "批量删除",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              // 取消多选按钮
                              if (isMultiSelectMode)
                                IconButton(
                                  onPressed: () {
                                    setPanelState(() {
                                      isMultiSelectMode = false;
                                      selectedIds.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                  color: Colors.grey,
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              // 移动整体按钮（爆点模式下隐藏）
                              if (!isMultiSelectMode && !_isImpactMode)
                                IconButton(
                                  onPressed: () {
                                    _closeClusterPanel();
                                    _startMoveCluster(cluster);
                                  },
                                  icon: const Icon(Icons.open_with),
                                  color: Colors.cyan,
                                  tooltip: "移动整体",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              // 移动到爆点按钮（仅在爆点模式下显示）
                              if (!isMultiSelectMode && _isImpactMode)
                                IconButton(
                                  onPressed: () {
                                    _closeClusterPanel();
                                    _startMoveImpactCluster(cluster);
                                  },
                                  icon: const Icon(Icons.gps_fixed),
                                  color: Colors.purpleAccent,
                                  tooltip: "移动爆点",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),

                              // 添加按钮
                              if (!isMultiSelectMode)
                                IconButton(
                                  onPressed: () {
                                    _closeClusterPanel();
                                    _createGrenadeAtCluster(cluster, layerId);
                                  },
                                  icon: const Icon(Icons.add_circle),
                                  color: Colors.orange,
                                  tooltip: "添加道具",
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                            ],
                          ),
                        // 类型选择器工具栏（添加分组按钮）
                        if (showTypeSelector && isEditMode)
                          IconButton(
                            onPressed: () => _showAddImpactGroupDialog(
                                context, cluster, layerId, setPanelState),
                            icon: const Icon(Icons.add_circle),
                            color: Colors.purpleAccent,
                            tooltip: "添加爆点分组",
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        // 关闭按钮
                        IconButton(
                          onPressed: _closeClusterPanel,
                          icon: const Icon(Icons.close),
                          color: Colors.grey,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  // 类型选择器或道具列表
                  Expanded(
                    child: showTypeSelector
                        ? _buildTypeSelector(
                            getTypeGroups(),
                            (type) {
                              setState(() {
                                _selectedImpactTypeFilter = type;
                                _selectedImpactGroupId = null;
                              });
                              setPanelState(() {});
                            },
                            cluster: cluster,
                            layerId: layerId,
                            isEditMode: isEditMode,
                            setPanelState: setPanelState,
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: displayGrenades.length,
                            itemBuilder: (_, index) {
                              final g = displayGrenades[index];
                              // 根据类型获取颜色
                              Color typeColor;
                              switch (g.type) {
                                case GrenadeType.smoke:
                                  typeColor = Colors.white;
                                  break;
                                case GrenadeType.he:
                                  typeColor = Colors.greenAccent;
                                  break;
                                case GrenadeType.molotov:
                                  typeColor = Colors.deepOrangeAccent;
                                  break;
                                case GrenadeType.flash:
                                  typeColor = Colors.yellowAccent;
                                  break;
                                case GrenadeType.wallbang:
                                  typeColor = Colors.lightBlueAccent;
                                  break;
                                default:
                                  typeColor = Colors.white;
                              }

                              final icon = _getTypeIcon(g.type);
                              final isSelected = selectedIds.contains(g.id);

                              // 左滑删除功能（编辑模式下）
                              Widget listItem = ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 多选模式显示复选框
                                    if (isMultiSelectMode)
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (val) {
                                          setPanelState(() {
                                            if (val == true) {
                                              selectedIds.add(g.id);
                                            } else {
                                              selectedIds.remove(g.id);
                                            }
                                          });
                                        },
                                        activeColor: Colors.red,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    // 道具图标
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: typeColor, width: 2),
                                      ),
                                      child: Icon(icon,
                                          size: 14, color: typeColor),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  g.title,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  "${_getTypeName(g.type)} • ${_getTeamName(g.team)}",
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                    fontSize: 10,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (g.isFavorite)
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 12),
                                    if (g.isNewImport)
                                      Container(
                                        margin: const EdgeInsets.only(left: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 2, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          "NEW",
                                          style: TextStyle(
                                              fontSize: 6, color: Colors.white),
                                        ),
                                      ),
                                    // 单独移动按钮
                                    if (isEditMode && !isMultiSelectMode)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 移除 _isImpactMode 限制，使得普通模式下也可以移动爆点
                                          IconButton(
                                            onPressed: () {
                                              _closeClusterPanel();
                                              _startMoveSingleGrenadeImpact(g);
                                            },
                                            icon: const Icon(Icons.gps_fixed),
                                            color: Colors.purpleAccent,
                                            tooltip: "设置/移动爆点",
                                            iconSize: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32),
                                          ),
                                          // 绘制爆点区域按钮（仅在爆点模式下显示，且仅限烟雾和燃烧）
                                          if (_isImpactMode &&
                                              (g.type == GrenadeType.smoke ||
                                                  g.type ==
                                                      GrenadeType.molotov))
                                            IconButton(
                                              onPressed: () {
                                                _closeClusterPanel();
                                                _openImpactAreaDrawing(
                                                    g, layerId);
                                              },
                                              icon: const Icon(Icons.brush),
                                              color: Colors.amber,
                                              tooltip: "绘制爆点区域",
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 32, minHeight: 32),
                                            ),
                                          // 移动投掷点按钮（爆点模式下隐藏）
                                          if (!_isImpactMode)
                                            IconButton(
                                              onPressed: () {
                                                _closeClusterPanel();
                                                _startMoveSingleGrenade(g);
                                              },
                                              icon: const Icon(Icons.open_with),
                                              color: Colors.cyan,
                                              tooltip: "移动投掷点",
                                              iconSize: 18,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 32, minHeight: 32),
                                            ),
                                        ],
                                      ),
                                    if (!isMultiSelectMode)
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey, size: 16),
                                  ],
                                ),
                                onTap: isMultiSelectMode
                                    ? () {
                                        setPanelState(() {
                                          if (isSelected) {
                                            selectedIds.remove(g.id);
                                          } else {
                                            selectedIds.add(g.id);
                                          }
                                        });
                                      }
                                    : () {
                                        _closeClusterPanel();
                                        _handleGrenadeTap(g,
                                            isEditing: isEditMode);
                                      },
                              );

                              // 编辑模式下添加左滑删除
                              if (isEditMode && !isMultiSelectMode) {
                                return Dismissible(
                                  key: Key('grenade_${g.id}'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    color: Colors.red,
                                    child: const Icon(Icons.delete,
                                        color: Colors.white),
                                  ),
                                  confirmDismiss: (_) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor:
                                            Theme.of(ctx).colorScheme.surface,
                                        title: Text("删除道具",
                                            style: TextStyle(
                                                color: Theme.of(ctx)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color)),
                                        content: Text("确定要删除 \"${g.title}\" 吗？",
                                            style: TextStyle(
                                                color: Theme.of(ctx)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color)),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text("取消")),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text("删除",
                                                  style: TextStyle(
                                                      color: Colors.red))),
                                        ],
                                      ),
                                    );
                                  },
                                  onDismissed: (_) async {
                                    await _deleteGrenadesInBatch([g]);
                                    if (grenades.length <= 1) {
                                      _closeClusterPanel();
                                    }
                                  },
                                  child: listItem,
                                );
                              }

                              return listItem;
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 显示添加爆点分组对话框
  void _showAddImpactGroupDialog(BuildContext context, GrenadeCluster cluster,
      int layerId, void Function(void Function()) setPanelState) {
    final nameController = TextEditingController();
    int selectedType = GrenadeType.smoke;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: Row(
            children: [
              const Icon(Icons.add_circle, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text("添加爆点分组",
                  style: TextStyle(
                      color: Theme.of(ctx).textTheme.bodyLarge?.color)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("选择道具类型",
                  style: TextStyle(
                      color: Theme.of(ctx).textTheme.bodySmall?.color,
                      fontSize: 12)),
              const SizedBox(height: 12),
              // 使用2x2网格布局
              Row(
                children: [
                  Expanded(
                      child: _buildTypeChip(
                          ctx, GrenadeType.smoke, selectedType, (type) {
                    setDialogState(() => selectedType = type);
                  })),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildTypeChip(
                          ctx, GrenadeType.flash, selectedType, (type) {
                    setDialogState(() => selectedType = type);
                  })),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _buildTypeChip(
                          ctx, GrenadeType.molotov, selectedType, (type) {
                    setDialogState(() => selectedType = type);
                  })),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _buildTypeChip(ctx, GrenadeType.he, selectedType,
                          (type) {
                    setDialogState(() => selectedType = type);
                  })),
                ],
              ),
              const SizedBox(height: 16),
              Text("分组名称",
                  style: TextStyle(
                      color: Theme.of(ctx).textTheme.bodySmall?.color,
                      fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: "例如: 烟雾1、A点闪等",
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => errorText = "请输入分组名称");
                  return;
                }
                // 检查当前爆点下名称是否重复
                final currentGroups = await _loadImpactGroups(cluster, layerId);
                if (currentGroups.any((g) => g.name == name)) {
                  setDialogState(() => errorText = "该爆点下分组名称已存在");
                  return;
                }
                // 创建分组
                final group = ImpactGroup(
                  name: name,
                  type: selectedType,
                  impactXRatio: cluster.xRatio,
                  impactYRatio: cluster.yRatio,
                  layerId: layerId,
                );
                final isar = ref.read(isarProvider);
                await isar.writeTxn(() async {
                  await isar.impactGroups.put(group);
                });
                if (ctx.mounted) Navigator.pop(ctx);
                // 刷新UI
                setPanelState(() {});
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text("创建"),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建类型选择芯片
  Widget _buildTypeChip(
      BuildContext context, int type, int selectedType, Function(int) onTap) {
    final isSelected = type == selectedType;
    final icon = _getTypeIcon(type);
    final name = _getTypeName(type);
    Color typeColor;
    switch (type) {
      case GrenadeType.smoke:
        typeColor = Colors.white;
        break;
      case GrenadeType.he:
        typeColor = Colors.greenAccent;
        break;
      case GrenadeType.molotov:
        typeColor = Colors.deepOrangeAccent;
        break;
      case GrenadeType.flash:
        typeColor = Colors.yellowAccent;
        break;
      default:
        typeColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => onTap(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? typeColor.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? typeColor : Colors.grey.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: typeColor),
            const SizedBox(width: 6),
            Text(name,
                style: TextStyle(
                    color: typeColor,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// 构建类型选择器（爆点模式下有多种类型时显示）
  Widget _buildTypeSelector(
      Map<int, List<Grenade>> typeGroups, Function(int) onTypeSelected,
      {GrenadeCluster? cluster,
      int? layerId,
      bool isEditMode = false,
      void Function(void Function())? setPanelState}) {
    return FutureBuilder<List<ImpactGroup>>(
      future: _loadImpactGroups(cluster, layerId),
      builder: (context, snapshot) {
        final customGroups = snapshot.data ?? [];
        final allGrenades = typeGroups.values.expand((e) => e).toList();

        // 计算未分类的投掷点
        final unassignedGrenades =
            allGrenades.where((g) => g.impactGroupId == null).toList();

        if (customGroups.isEmpty && unassignedGrenades.isEmpty) {
          // 只有当没有自定义分组且没有未分类道具时才显示提示
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open,
                      size: 48,
                      color: Colors.purpleAccent.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text("暂无分组和道具",
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 14)),
                  const SizedBox(height: 8),
                  Text("点击右上角 + 按钮创建分组或添加道具",
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.6),
                          fontSize: 12)),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // 未分类分组（始终显示在顶部，但仅当有未分类道具或没有自定义分组时显示）
            if (unassignedGrenades.isNotEmpty || customGroups.isEmpty)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey, width: 2),
                  ),
                  child: const Icon(Icons.inbox, size: 20, color: Colors.grey),
                ),
                title: const Text("未分类",
                    style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                subtitle: Text("${unassignedGrenades.length} 个投掷点",
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12)),
                trailing: Icon(Icons.chevron_right,
                    color: Colors.grey.withValues(alpha: 0.7)),
                onTap: () {
                  // 选择未分类，显示所有未分配的投掷点
                  setState(() {
                    _selectedImpactGroupId = -1; // -1 表示未分类
                    _selectedImpactTypeFilter = null;
                  });
                  setPanelState?.call(() {});
                },
              ),
            // 分隔线
            if (customGroups.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                        width: 20,
                        height: 1,
                        color: Colors.purpleAccent.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Text("自定义分组",
                        style: TextStyle(
                            color: Colors.purpleAccent.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Container(
                            height: 1,
                            color: Colors.purpleAccent.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            // 自定义分组列表
            ...customGroups.map((group) {
              final icon = _getTypeIcon(group.type);
              Color typeColor;
              switch (group.type) {
                case GrenadeType.smoke:
                  typeColor = Colors.white;
                  break;
                case GrenadeType.he:
                  typeColor = Colors.greenAccent;
                  break;
                case GrenadeType.molotov:
                  typeColor = Colors.deepOrangeAccent;
                  break;
                case GrenadeType.flash:
                  typeColor = Colors.yellowAccent;
                  break;
                default:
                  typeColor = Colors.white;
              }
              // 计算属于该分组的投掷点数量
              final groupGrenades = allGrenades
                  .where((g) => g.impactGroupId == group.id)
                  .toList();

              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.purpleAccent, width: 2),
                  ),
                  child: Icon(icon, size: 20, color: typeColor),
                ),
                title: Text(group.name,
                    style: const TextStyle(
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                subtitle: Text(
                    "${_getTypeName(group.type)} · ${groupGrenades.length} 个投掷点",
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 绘制爆点范围按钮（仅限烟雾和燃烧，且 layerId 不为空，且在编辑模式下）
                    if ((group.type == GrenadeType.smoke ||
                            group.type == GrenadeType.molotov) &&
                        layerId != null &&
                        isEditMode)
                      IconButton(
                        onPressed: () => _openGroupImpactAreaDrawing(
                            group, groupGrenades, layerId, setPanelState),
                        icon: const Icon(Icons.brush),
                        color: Colors.amber,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "绘制分组爆点范围",
                      ),
                    // 分类投掷点按钮
                    if (isEditMode)
                      IconButton(
                        onPressed: () => _showAssignGrenadesToGroupDialog(
                            context, group, allGrenades, setPanelState),
                        icon: const Icon(Icons.playlist_add),
                        color: Colors.amber,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "分类投掷点",
                      ),
                    // 删除分组按钮
                    if (isEditMode)
                      IconButton(
                        onPressed: () =>
                            _deleteImpactGroup(group, setPanelState),
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red.withValues(alpha: 0.7),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "删除分组",
                      ),
                    Icon(Icons.chevron_right,
                        color: Colors.purpleAccent.withValues(alpha: 0.7)),
                  ],
                ),
                onTap: () {
                  // 选择自定义分组，设置过滤器
                  setState(() {
                    _selectedImpactGroupId = group.id;
                    _selectedImpactTypeFilter = group.type;
                  });
                  setPanelState?.call(() {});
                },
              );
            }),
          ],
        );
      },
    );
  }

  /// 用于存储选中的自定义分组ID
  int? _selectedImpactGroupId;

  /// 加载与当前爆点关联的自定义分组
  Future<List<ImpactGroup>> _loadImpactGroups(
      GrenadeCluster? cluster, int? layerId) async {
    if (cluster == null || layerId == null) return [];
    final isar = ref.read(isarProvider);
    // 加载该图层上的所有分组，然后按爆点坐标过滤
    final allGroups =
        await isar.impactGroups.filter().layerIdEqualTo(layerId).findAll();
    // 使用坐标匹配，阈值为 0.02（与聚合阈值一致）
    const threshold = 0.02;
    return allGroups.where((g) {
      final dx = (g.impactXRatio - cluster.xRatio).abs();
      final dy = (g.impactYRatio - cluster.yRatio).abs();
      return (dx * dx + dy * dy) < threshold * threshold;
    }).toList();
  }

  /// 显示分类投掷点对话框
  void _showAssignGrenadesToGroupDialog(
      BuildContext context,
      ImpactGroup group,
      List<Grenade> allGrenades,
      void Function(void Function())? setPanelState) {
    // 筛选同类型的投掷点
    final eligibleGrenades =
        allGrenades.where((g) => g.type == group.type).toList();
    // 当前已分配到该组的投掷点ID
    final assignedIds = eligibleGrenades
        .where((g) => g.impactGroupId == group.id)
        .map((g) => g.id)
        .toSet();
    // 用于跟踪选中状态
    Set<int> selectedIds = Set.from(assignedIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: Row(
            children: [
              const Icon(Icons.playlist_add, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text("分类投掷点到 \"${group.name}\"",
                    style: TextStyle(
                        color: Theme.of(ctx).textTheme.bodyLarge?.color,
                        fontSize: 16),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: eligibleGrenades.isEmpty
                ? Center(
                    child: Text("没有 ${_getTypeName(group.type)} 类型的投掷点",
                        style: TextStyle(
                            color: Theme.of(ctx).textTheme.bodySmall?.color)),
                  )
                : ListView.builder(
                    itemCount: eligibleGrenades.length,
                    itemBuilder: (ctx, index) {
                      final g = eligibleGrenades[index];
                      final isSelected = selectedIds.contains(g.id);
                      Color typeColor;
                      switch (g.type) {
                        case GrenadeType.smoke:
                          typeColor = Colors.white;
                          break;
                        case GrenadeType.he:
                          typeColor = Colors.greenAccent;
                          break;
                        case GrenadeType.molotov:
                          typeColor = Colors.deepOrangeAccent;
                          break;
                        case GrenadeType.flash:
                          typeColor = Colors.yellowAccent;
                          break;
                        default:
                          typeColor = Colors.white;
                      }

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedIds.add(g.id);
                            } else {
                              selectedIds.remove(g.id);
                            }
                          });
                        },
                        activeColor: Colors.purpleAccent,
                        title: Text(g.title,
                            style: TextStyle(
                                color: Theme.of(ctx).textTheme.bodyLarge?.color,
                                fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(_getTypeName(g.type),
                            style: TextStyle(color: typeColor, fontSize: 12)),
                        secondary: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: typeColor, width: 1.5),
                          ),
                          child: Icon(_getTypeIcon(g.type),
                              size: 14, color: typeColor),
                        ),
                        dense: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("取消"),
            ),
            ElevatedButton(
              onPressed: () async {
                final isar = ref.read(isarProvider);
                await isar.writeTxn(() async {
                  for (final g in eligibleGrenades) {
                    if (selectedIds.contains(g.id)) {
                      g.impactGroupId = group.id;
                    } else if (g.impactGroupId == group.id) {
                      g.impactGroupId = null;
                    }
                    await isar.grenades.put(g);
                  }
                });
                if (ctx.mounted) Navigator.pop(ctx);
                setPanelState?.call(() {});
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text("确定"),
            ),
          ],
        ),
      ),
    );
  }

  /// 删除自定义分组
  Future<void> _deleteImpactGroup(
      ImpactGroup group, void Function(void Function())? setPanelState) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text("删除分组",
            style: TextStyle(color: Theme.of(ctx).textTheme.bodyLarge?.color)),
        content: Text("确定要删除分组 \"${group.name}\" 吗？\n该分组下的投掷点不会被删除。",
            style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("取消")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final isar = ref.read(isarProvider);
      // 将属于该分组的投掷点的 impactGroupId 设为 null
      final grenades =
          await isar.grenades.filter().impactGroupIdEqualTo(group.id).findAll();
      await isar.writeTxn(() async {
        for (final g in grenades) {
          g.impactGroupId = null;
          await isar.grenades.put(g);
        }
        await isar.impactGroups.delete(group.id);
      });
      setPanelState?.call(() {});
      setState(() {});
    }
  }

  Future<void> _showRenameImpactPointDialog(BuildContext context,
      {ImpactGroup? group,
      Grenade? grenade,
      required VoidCallback onSuccess}) async {
    final isGroup = group != null;
    final TextEditingController controller = TextEditingController(
        text: isGroup ? group.name : (grenade?.description ?? ""));

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isGroup ? "重命名分组" : "重命名爆点"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "名称"),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("取消")),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();

              final isar = ref.read(isarProvider);
              await isar.writeTxn(() async {
                if (isGroup) {
                  group.name = newName;
                  await isar.impactGroups.put(group);
                } else if (grenade != null) {
                  grenade.description = newName;
                  await isar.grenades.put(grenade);
                }
              });
              onSuccess();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }
}

/// 虚线画笔，用于绘制投掷点到爆点的连线
class _DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedLinePainter({
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength = 4,
    this.gapLength = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final totalLength = (end - start).distance;
    final direction = (end - start) / totalLength;

    double currentLength = 0;
    bool draw = true;

    path.moveTo(start.dx, start.dy);

    while (currentLength < totalLength) {
      final segmentLength = draw ? dashLength : gapLength;
      final nextLength =
          (currentLength + segmentLength).clamp(0.0, totalLength);
      final nextPoint = start + direction * nextLength;

      if (draw) {
        path.lineTo(nextPoint.dx, nextPoint.dy);
      } else {
        path.moveTo(nextPoint.dx, nextPoint.dy);
      }

      currentLength = nextLength;
      draw = !draw;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        color != oldDelegate.color;
  }
}

class _ImpactAreaPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final List<Offset> currentStroke;
  final double currentStrokeWidth;
  final bool isCurrentEraser;
  final Color color;
  final double opacity;
  final ({
    double width,
    double height,
    double offsetX,
    double offsetY
  }) imageBounds;

  _ImpactAreaPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentStrokeWidth,
    required this.isCurrentEraser,
    required this.color,
    required this.imageBounds,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 使用 saveLayer 创建新的图层，并应用整体透明度
    // 这样笔画叠加时不会导致透明度累积，而是作为一个整体显示
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: opacity));

    for (final stroke in strokes) {
      final points =
          (stroke['points'] as List).map((p) => Offset(p[0], p[1])).toList();
      final width = (stroke['strokeWidth'] as num).toDouble();
      final isEraser = stroke['isEraser'] as bool? ?? false;
      final isShape = stroke['isShape'] as bool? ?? false;
      _drawStroke(canvas, points, width, isEraser, isShape: isShape);
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke, currentStrokeWidth, isCurrentEraser);
    }

    canvas.restore();
  }

  void _drawStroke(
      Canvas canvas, List<Offset> points, double width, bool isEraser,
      {bool isShape = false}) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = isEraser
          ? Colors.transparent
          : color.withValues(alpha: 1.0) // 笔画使用不透明颜色
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style =
          isShape && !isEraser ? PaintingStyle.fill : PaintingStyle.stroke;

    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    final path = Path();
    final start = _limitPoint(points[0]);
    path.moveTo(start.dx, start.dy);

    // 如果只有一个点，画一个点
    if (points.length == 1) {
      path.lineTo(start.dx, start.dy);
    }

    for (int i = 1; i < points.length; i++) {
      final p = _limitPoint(points[i]);
      path.lineTo(p.dx, p.dy);
    }

    // 如果是填充模式，需要闭合路径
    if (isShape && !isEraser) {
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  // 将相对坐标转换为画布坐标，并限制在图片区域内
  Offset _limitPoint(Offset ratio) {
    return Offset(
      imageBounds.offsetX + ratio.dx * imageBounds.width,
      imageBounds.offsetY + ratio.dy * imageBounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant _ImpactAreaPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
  }
}
