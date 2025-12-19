import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:photo_view/photo_view.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../providers.dart';
import '../main.dart';
import '../spawn_point_data.dart';
import '../widgets/joystick_widget.dart';
import 'grenade_detail_screen.dart';

// --- 页面级状态管理 ---

final isEditModeProvider = StateProvider.autoDispose<bool>((ref) => false);
final selectedLayerIndexProvider = StateProvider.autoDispose<int>((ref) => 0);

final _filteredGrenadesProvider =
    StreamProvider.autoDispose.family<List<Grenade>, int>((ref, layerId) {
  final isar = ref.watch(isarProvider);
  final teamFilter = ref.watch(teamFilterProvider);
  final onlyFav = ref.watch(onlyFavoritesProvider);
  final selectedTypes = ref.watch(typeFilterProvider);

  return isar.grenades
      .filter()
      .layer((q) => q.idEqualTo(layerId))
      .watch(fireImmediately: true)
      .map((allGrenades) {
    return allGrenades.where((g) {
      if (!selectedTypes.contains(g.type)) return false;
      if (teamFilter == TeamType.onlyAll && g.team != TeamType.all)
        return false;
      if (teamFilter == TeamType.ct && g.team != TeamType.ct) return false;
      if (teamFilter == TeamType.t && g.team != TeamType.t) return false;
      if (onlyFav && !g.isFavorite) return false;
      return true;
    }).toList();
  });
});

// --- 点位聚合模型 ---
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

  // 检查是否包含多种类型的道具
  bool get hasMultipleTypes {
    if (grenades.length <= 1) return false;
    final firstType = grenades.first.type;
    return grenades.any((g) => g.type != firstType);
  }
}

List<GrenadeCluster> clusterGrenades(List<Grenade> grenades,
    {double threshold = 0.0}) {
  // 禁用合并：阈值设为 0
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

class MapScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  const MapScreen({super.key, required this.gameMap});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  Offset? _tempTapPosition;
  GrenadeCluster? _draggingCluster;
  Offset? _dragOffset;
  Offset? _dragAnchorOffset; // 拖拽锚点偏移
  bool _isMovingCluster = false;
  Grenade? _movingSingleGrenade; // 单个道具移动状态
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey(); // 添加 GlobalKey
  bool _isSpawnSidebarExpanded = true; // 出生点侧边栏展开状态

  // 摇杆模式相关状态
  GrenadeCluster? _joystickCluster; // 摇杆模式下选中的标点
  Offset? _joystickOriginalOffset; // 摇杆移动前的原始位置

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    widget.gameMap.layers.loadSync();
    final defaultIndex = widget.gameMap.layers.length > 1 ? 1 : 0;
    Future.microtask(() {
      ref.read(selectedLayerIndexProvider.notifier).state = defaultIndex;
      // 通知悬浮窗服务当前地图
      _updateOverlayState(defaultIndex);
    });
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    // 离开地图时清除悬浮窗状态
    globalOverlayState?.clearMap();
    // 通知独立悬浮窗清除地图
    _notifyOverlayWindowClearMap();
    super.dispose();
  }

  /// 比较两个 Cluster 是否相同（基于第一个 Grenade 的 ID）
  bool _isSameCluster(GrenadeCluster? c1, GrenadeCluster? c2) {
    if (c1 == null || c2 == null) return false;
    if (c1 == c2) return true;
    if (c1.grenades.isEmpty || c2.grenades.isEmpty) return false;
    return c1.grenades.first.id == c2.grenades.first.id;
  }

  /// 计算 BoxFit.contain 模式下正方形图片的实际显示区域
  /// 返回 (imageWidth, imageHeight, offsetX, offsetY)
  ({double width, double height, double offsetX, double offsetY})
      _getImageBounds(double containerWidth, double containerHeight) {
    const double imageAspectRatio = 1.0; // 地图图片是正方形
    final double containerAspectRatio = containerWidth / containerHeight;

    if (containerAspectRatio > imageAspectRatio) {
      // 容器更宽，图片以高度为准，左右有留白
      final imageHeight = containerHeight;
      final imageWidth = containerHeight * imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: (containerWidth - imageWidth) / 2,
        offsetY: 0.0,
      );
    } else {
      // 容器更高，图片以宽度为准，上下有留白
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

  /// 将屏幕全局坐标转换为原始图片坐标比例 (0-1)
  /// 返回 null 如果坐标无效
  Offset? _getLocalPosition(Offset globalPosition) {
    // 1. 获取 Stack 的 RenderBox
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    // 2. 将全局坐标转换为 Stack 的局部坐标
    // 这会自动处理 PhotoView 的缩放和平移变换，以及屏幕位置
    // 注意：因为 GlobalKey 放在 Stack 上，而 Stack 是 PhotoView 的 child，
    // 所以这里的 localPosition 已经是经过 PhotoView 逆变换后的坐标
    final localPosition = box.globalToLocal(globalPosition);

    // 3. 获取 Container 尺寸（Stack 的尺寸）
    final size = box.size;

    // 4. 计算图片实际显示区域
    final bounds = _getImageBounds(size.width, size.height);

    // 5. 将局部坐标转换为相对于图片区域的偏移
    final tapX = localPosition.dx - bounds.offsetX;
    final tapY = localPosition.dy - bounds.offsetY;

    // 6. 转换为比例
    return Offset(tapX / bounds.width, tapY / bounds.height);
  }

  void _updateOverlayState(int layerIndex) {
    print("DEBUG: _updateOverlayState called with index $layerIndex");
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
    print(
        "DEBUG: _notifyOverlayWindowSetMap called. Controller is ${overlayWindowController == null ? 'NULL' : 'NOT NULL'}");
    if (overlayWindowController != null) {
      try {
        overlayWindowController!
            .invokeMethod('set_map', {
              'map_id': mapId,
              'layer_id': layerId,
            })
            .then((_) => print("DEBUG: invokeMethod success"))
            .catchError((e) {
              print("DEBUG: invokeMethod error: $e");
              if (retryCount < 3) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  _notifyOverlayWindowSetMap(mapId, layerId,
                      retryCount: retryCount + 1);
                });
              }
            });
      } catch (e) {
        print("DEBUG: Exception: $e");
      }
    } else {
      if (retryCount < 5) {
        print("DEBUG: Controller null, retry $retryCount");
        Future.delayed(const Duration(milliseconds: 500), () {
          _notifyOverlayWindowSetMap(mapId, layerId,
              retryCount: retryCount + 1);
        });
      }
    }
  }

  void _notifyOverlayWindowClearMap() {
    if (overlayWindowController != null) {
      try {
        overlayWindowController!.invokeMethod('clear_map').catchError((_) {});
      } catch (_) {}
    }
  }

  void _handleTap(
      TapUpDetails details, double width, double height, int layerId) {
    if (_isMovingCluster || _movingSingleGrenade != null) {
      _handleMoveClusterTap(details, width, height);
      return;
    }
    final isEditMode = ref.read(isEditModeProvider);
    if (!isEditMode) return;

    // 使用 GlobalKey 和全局坐标获取精确的本地比例
    final localRatio = _getLocalPosition(details.globalPosition);

    if (localRatio == null) {
      return;
    }

    final xRatio = localRatio.dx;
    final yRatio = localRatio.dy;

    // 边界检查：只允许在地图范围内创建点位
    if (xRatio < 0 || xRatio > 1 || yRatio < 0 || yRatio > 1) {
      return; // 点击在地图外，忽略
    }

    setState(() {
      _tempTapPosition = Offset(xRatio, yRatio);
    });
    _createGrenade(layerId);
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
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GrenadeDetailScreen(grenadeId: id, isEditing: true)));
  }

  void _onSearchResultSelected(Grenade g) {
    g.layer.loadSync();
    final targetLayerId = g.layer.value?.id;
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    final targetIndex = layers.indexWhere((l) => l.id == targetLayerId);
    if (targetIndex != -1 &&
        targetIndex != ref.read(selectedLayerIndexProvider)) {
      ref.read(selectedLayerIndexProvider.notifier).state = targetIndex;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("已跳转至 ${g.layer.value?.name ?? '目标楼层'}"),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ));
    }
    _handleGrenadeTap(g, isEditing: false);
  }

  void _handleGrenadeTap(Grenade g, {required bool isEditing}) async {
    if (g.isNewImport) {
      g.isNewImport = false;
      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        await isar.grenades.put(g);
      });
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GrenadeDetailScreen(grenadeId: g.id, isEditing: isEditing)));
  }

  void _handleClusterTap(GrenadeCluster cluster, int layerId) async {
    // 处理合并：如果正在移动单个道具，点击现有点位则合并进去
    if (_movingSingleGrenade != null) {
      if (cluster.grenades.any((g) => g.id == _movingSingleGrenade!.id)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("不能合并到自己所在的点位"),
            behavior: SnackBarBehavior.floating, // 添加浮动样式，避免被其他遮挡
            duration: Duration(seconds: 1)));
        return;
      }

      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        final g = await isar.grenades.get(_movingSingleGrenade!.id);
        if (g != null) {
          // 使用 cluster 的坐标进行合并
          // 为了物理合并，将坐标设为 cluster 中第一个道具的坐标
          final targetX = cluster.grenades.first.xRatio;
          final targetY = cluster.grenades.first.yRatio;

          g.xRatio = targetX;
          g.yRatio = targetY;
          g.updatedAt = DateTime.now();
          await isar.grenades.put(g);
        }
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✓ 已合并到既有点位"),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1)));

      setState(() {
        _movingSingleGrenade = null;
      });
      return;
    }

    // 处理整组点位合并：如果正在移动点位组，点击现有点位则全部合并进去
    if (_isMovingCluster && _draggingCluster != null) {
      // 检查是否包含自身（只要有任意重叠ID即视为由于源点位尚未消失而点击了自己）
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
        // 使用目标 Cluster 的第一个坐标作为合并基准
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

  void _showClusterBottomSheet(GrenadeCluster cluster, int layerId) {
    final isEditMode = ref.read(isEditModeProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          // 多选删除模式状态
          bool isMultiSelectMode = false;
          Set<int> selectedIds = {};
          final grenades = cluster.grenades;

          return DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.25,
            maxChildSize: 0.7,
            expand: false,
            builder: (_, scrollController) {
              return StatefulBuilder(
                builder: (context, setInnerState) {
                  return Column(
                    children: [
                      // 拖动条
                      Container(
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey[600],
                              borderRadius: BorderRadius.circular(2))),
                      // 头部
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                isMultiSelectMode
                                    ? "已选择 ${selectedIds.length} 个"
                                    : "该点位共 ${grenades.length} 个道具",
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color)),
                            if (isEditMode)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                // 删除/确认删除按钮
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
                                              // 收集要删除的道具
                                              final toDelete = <Grenade>[];
                                              for (final id in selectedIds) {
                                                final g = grenades.firstWhere(
                                                    (g) => g.id == id,
                                                    orElse: () =>
                                                        grenades.first);
                                                if (!toDelete
                                                    .any((x) => x.id == g.id)) {
                                                  toDelete.add(g);
                                                }
                                              }
                                              // 在单个事务中批量删除
                                              await _deleteGrenadesInBatch(
                                                  toDelete);
                                              setModalState(() {
                                                grenades.removeWhere((g) =>
                                                    selectedIds.contains(g.id));
                                              });
                                              if (grenades.isEmpty) {
                                                Navigator.pop(context);
                                              } else {
                                                setInnerState(() {
                                                  isMultiSelectMode = false;
                                                  selectedIds.clear();
                                                });
                                              }
                                            }
                                          },
                                    icon: const Icon(Icons.delete, size: 18),
                                    label: Text("删除(${selectedIds.length})"),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.red),
                                  )
                                else
                                  IconButton(
                                    onPressed: () {
                                      setInnerState(() {
                                        isMultiSelectMode = true;
                                      });
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red,
                                    tooltip: "批量删除",
                                    iconSize: 22,
                                  ),
                                // 取消多选按钮
                                if (isMultiSelectMode)
                                  IconButton(
                                    onPressed: () {
                                      setInnerState(() {
                                        isMultiSelectMode = false;
                                        selectedIds.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.close),
                                    color: Colors.grey,
                                    iconSize: 22,
                                  ),
                                // 移动整体按钮
                                if (!isMultiSelectMode)
                                  IconButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _startMoveCluster(cluster);
                                    },
                                    icon: const Icon(Icons.open_with),
                                    color: Colors.cyan,
                                    tooltip: "移动整体",
                                    iconSize: 22,
                                  ),
                                // 添加按钮
                                if (!isMultiSelectMode)
                                  IconButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _createGrenadeAtCluster(cluster, layerId);
                                    },
                                    icon: const Icon(Icons.add_circle),
                                    color: Colors.orange,
                                    tooltip: "添加道具",
                                    iconSize: 22,
                                  ),
                              ]),
                          ],
                        ),
                      ),
                      Divider(color: Theme.of(context).dividerColor, height: 1),
                      // 道具列表
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: grenades.length,
                          itemBuilder: (_, index) {
                            final g = grenades[index];
                            final color = _getTeamColor(g.team);
                            final icon = _getTypeIcon(g.type);
                            final isSelected = selectedIds.contains(g.id);

                            return ListTile(
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 多选模式显示复选框
                                  if (isMultiSelectMode)
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (val) {
                                        setInnerState(() {
                                          if (val == true) {
                                            selectedIds.add(g.id);
                                          } else {
                                            selectedIds.remove(g.id);
                                          }
                                        });
                                      },
                                      activeColor: Colors.red,
                                    ),
                                  // 道具图标
                                  Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: color, width: 2)),
                                      child:
                                          Icon(icon, size: 16, color: color)),
                                ],
                              ),
                              title: Text(g.title,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.color,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14)),
                              subtitle: Text(
                                  "${_getTypeName(g.type)} • ${_getTeamName(g.team)}",
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color,
                                      fontSize: 11)),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (g.isFavorite)
                                      const Icon(Icons.star,
                                          color: Colors.amber, size: 16),
                                    if (g.isNewImport)
                                      Container(
                                          margin:
                                              const EdgeInsets.only(left: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: const Text("NEW",
                                              style: TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.white))),
                                    // 单独移动按钮（编辑模式且非多选模式）
                                    if (isEditMode && !isMultiSelectMode)
                                      IconButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _startMoveSingleGrenade(g);
                                        },
                                        icon: const Icon(Icons.open_with),
                                        color: Colors.cyan,
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                      ),
                                    if (!isMultiSelectMode)
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey, size: 20),
                                  ]),
                              onTap: isMultiSelectMode
                                  ? () {
                                      setInnerState(() {
                                        if (isSelected) {
                                          selectedIds.remove(g.id);
                                        } else {
                                          selectedIds.add(g.id);
                                        }
                                      });
                                    }
                                  : () {
                                      Navigator.pop(context);
                                      _handleGrenadeTap(g,
                                          isEditing: isEditMode);
                                    },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
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
        isNewImport: false);
    int id = 0;
    await isar.writeTxn(() async {
      id = await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
    });
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                GrenadeDetailScreen(grenadeId: id, isEditing: true)));
  }

  /// 批量删除道具（在单个事务中完成，避免嵌套事务错误）
  Future<void> _deleteGrenadesInBatch(List<Grenade> grenades) async {
    if (grenades.isEmpty) return;
    final isar = ref.read(isarProvider);

    // 先加载所有必要的数据
    for (final g in grenades) {
      g.steps.loadSync();
      for (final step in g.steps) {
        step.medias.loadSync();
      }
    }

    // 在单个事务中执行所有删除操作
    await isar.writeTxn(() async {
      for (final g in grenades) {
        // 删除所有媒体
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

  void _cancelMoveSingleGrenade() {
    setState(() {
      _movingSingleGrenade = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _handleMoveClusterTap(
      TapUpDetails details, double width, double height) async {
    // 处理单个道具移动
    if (_movingSingleGrenade != null) {
      final localRatio = _getLocalPosition(details.globalPosition);
      if (localRatio == null) return;

      double newX = localRatio.dx;
      double newY = localRatio.dy;

      // 边界检查
      if (newX < 0 || newX > 1 || newY < 0 || newY > 1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("无法移动到地图外"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1)));
        return;
      }

      final isar = ref.read(isarProvider);

      String successMessage = "✓ 道具已移动到新位置";
      Color messageColor = Colors.green;

      // 移除自动吸附逻辑，点击地图空白处只做移动

      await isar.writeTxn(() async {
        final g = await isar.grenades.get(_movingSingleGrenade!.id);
        if (g != null) {
          g.xRatio = newX;
          g.yRatio = newY;
          g.updatedAt = DateTime.now();
          await isar.grenades.put(g);
        }
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMessage),
          backgroundColor: messageColor,
          duration: const Duration(seconds: 1)));
      setState(() {
        _movingSingleGrenade = null;
      });
      return;
    }

    // 处理点位整体移动
    if (_draggingCluster == null) return;

    // 使用 GlobalKey 和全局坐标获取精确的本地比例
    final localRatio = _getLocalPosition(details.globalPosition);
    if (localRatio == null) return;

    final newX = localRatio.dx;
    final newY = localRatio.dy;

    // 边界检查：只允许移动到地图范围内
    if (newX < 0 || newX > 1 || newY < 0 || newY > 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("无法移动到地图外"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 1)));
      return;
    }

    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      for (final g in _draggingCluster!.grenades) {
        g.xRatio = newX;
        g.yRatio = newY;
        g.updatedAt = DateTime.now();
        await isar.grenades.put(g);
      }
    });
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
      default:
        return Icons.circle;
    }
  }

  Color _getTypeColor(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return Colors.grey;
      case GrenadeType.flash:
        return Colors.yellow;
      case GrenadeType.molotov:
        return Colors.red;
      case GrenadeType.he:
        return Colors.green;
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
      default:
        return "";
    }
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
            color:
                isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
            border: Border.all(
                color: isSelected
                    ? activeColor
                    : unselectedColor.withOpacity(0.4)),
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
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            border: Border.all(
                color: isSelected ? color : unselectedColor.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? color : unselectedColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12)),
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
      }) imageBounds) {
    final color = _getTeamColor(cluster.primaryTeam);
    final icon = _getTypeIcon(cluster.primaryType);
    final count = cluster.grenades.length;

    // Base size is 20, use FIXED half-size for positioning
    // Transform.scale only affects visual rendering, NOT layout position
    // So positioning offset must be constant to avoid drift during zoom
    const double baseHalfSize = 10.0;

    // 计算标记在 Stack 中的实际位置（考虑图片偏移）
    // 如果正在拖动或使用摇杆，使用 _dragOffset 中的实时位置
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
                    boxShadow: [
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
            if (count > 1)
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
            if (cluster.hasNewImport)
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
                color: color.withOpacity(0.5),
                borderRadius: BorderRadius.circular(3),
                border:
                    Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  '${spawn.id}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
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
                    color: color.withOpacity(0.3),
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
                  color: Colors.grey.withOpacity(0.2),
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
              color: const Color(0xFF1A1D21).withOpacity(0.9),
              border: Border(
                  left: BorderSide(color: Colors.white.withOpacity(0.1))),
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
              color: const Color(0xFF1A1D21).withOpacity(0.9),
            ),
            child: Column(
              children: [
                // 标题
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
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
                                color: Colors.blueAccent.withOpacity(0.8),
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
                                color: Colors.amber.withOpacity(0.8),
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
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.6),
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

  Widget _buildFavoritesBar(AsyncValue<List<Grenade>> asyncData) {
    return Container(
      height: 60,
      color: const Color(0xFF141619),
      child: asyncData.when(
        data: (grenades) {
          final favs = grenades.where((g) => g.isFavorite).toList();
          if (favs.isEmpty)
            return const Center(
                child: Text("暂无本层常用道具",
                    style: TextStyle(color: Colors.grey, fontSize: 12)));
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: favs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (ctx, index) {
              final g = favs[index];
              Color color = g.team == TeamType.ct
                  ? Colors.blueAccent
                  : (g.team == TeamType.t ? Colors.amber : Colors.white);
              return ActionChip(
                  backgroundColor: const Color(0xFF2A2D33),
                  padding: EdgeInsets.zero,
                  label: Text(g.title,
                      style: TextStyle(color: color, fontSize: 12)),
                  avatar: Icon(Icons.star, size: 14, color: color),
                  onPressed: () => _handleGrenadeTap(g, isEditing: false));
            },
          );
        },
        error: (_, __) => const SizedBox(),
        loading: () => const SizedBox(),
      ),
    );
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
    if (currentLayer == null)
      return const Scaffold(body: Center(child: Text("数据错误：无楼层信息")));

    final grenadesAsync = ref.watch(_filteredGrenadesProvider(currentLayer.id));

    // 搜索数据：从数据库查询该地图所有楼层的道具
    final isar = ref.read(isarProvider);
    final allMapGrenades = <Grenade>[];
    for (final layer in layers) {
      allMapGrenades.addAll(isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(layer.id))
          .findAllSync());
    }

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
                        color:
                            Theme.of(context).dividerColor.withOpacity(0.1))),
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
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
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
                          return allMapGrenades.where((g) => g.title
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()));
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
                      activeColor: Colors.redAccent,
                      inactiveThumbColor: Colors.grey,
                      inactiveTrackColor: Colors.grey.withOpacity(0.3),
                      onChanged: (val) =>
                          ref.read(isEditModeProvider.notifier).state = val),
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
                      selectedColor: Colors.orange.withOpacity(0.3),
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
                      selectedColor: Colors.green.withOpacity(0.3),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                          color: showSpawnPoints
                              ? Colors.greenAccent
                              : Colors.grey),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                ]))),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
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
                        final double scale = snapshot.data?.scale ?? 1.0;
                        // Calculate scale factor (inverse of zoom)
                        // Base scalar is 1.0, decreases as we zoom in
                        final double markerScale = 1.0 / scale;
                        // Clamp scale to prevent markers getting too small or too big if needed
                        // For now we use direct inverse scaling to keep visual size constant

                        // 计算 BoxFit.contain 模式下图片的实际显示区域
                        final imageBounds = _getImageBounds(
                            constraints.maxWidth, constraints.maxHeight);

                        return GestureDetector(
                            onTapUp: (d) => _handleTap(d, constraints.maxWidth,
                                constraints.maxHeight, currentLayer.id),
                            child: Stack(key: _stackKey, children: [
                              Image.asset(currentLayer.assetPath,
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  fit: BoxFit.contain),
                              // 道具点位标记（先渲染，在下层）
                              // 缩放 200% 以上时禁用合并，显示完整细节
                              ...grenadesAsync.when(
                                  data: (list) {
                                    final clusterThreshold =
                                        scale >= 2.0 ? 0.008 : 0.02;
                                    final clusters = clusterGrenades(list,
                                        threshold: clusterThreshold);
                                    return clusters.map((c) =>
                                        _buildClusterMarker(
                                            c,
                                            constraints,
                                            isEditMode,
                                            currentLayer.id,
                                            markerScale,
                                            imageBounds));
                                  },
                                  error: (_, __) => [],
                                  loading: () => []),
                              // 出生点标记（后渲染，在上层，但不响应点击）
                              if (showSpawnPoints && spawnConfig != null)
                                IgnorePointer(
                                  child: Stack(
                                    children: [
                                      ...spawnConfig.ctSpawns.map((spawn) =>
                                          _buildSpawnPointMarker(
                                              spawn,
                                              true,
                                              constraints,
                                              markerScale,
                                              imageBounds,
                                              currentLayer.id,
                                              isEditMode)),
                                      ...spawnConfig.tSpawns.map((spawn) =>
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
                                        _dragOffset!.dx * imageBounds.width -
                                        14.0, // Fixed offset, not scaled
                                    top: imageBounds.offsetY +
                                        _dragOffset!.dy * imageBounds.height -
                                        14.0, // Fixed offset, not scaled
                                    child: Transform.scale(
                                      scale: markerScale,
                                      child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withOpacity(0.8),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.white,
                                                  width: 2)),
                                          child: const Icon(Icons.place,
                                              size: 16, color: Colors.white)),
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
                                          color: Colors.greenAccent, size: 24),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12)),
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildTypeFilterBtn(
                                      selectedTypes,
                                      GrenadeType.smoke,
                                      "烟雾",
                                      Icons.cloud,
                                      Colors.grey),
                                  _buildTypeFilterBtn(
                                      selectedTypes,
                                      GrenadeType.flash,
                                      "闪光",
                                      Icons.flash_on,
                                      Colors.yellow),
                                  _buildTypeFilterBtn(
                                      selectedTypes,
                                      GrenadeType.molotov,
                                      "燃烧",
                                      Icons.local_fire_department,
                                      Colors.red),
                                  _buildTypeFilterBtn(
                                      selectedTypes,
                                      GrenadeType.he,
                                      "手雷",
                                      Icons.trip_origin,
                                      Colors.green),
                                ])),
                        const SizedBox(height: 10),
                        /* Search bar moved to AppBar */
                      ],
                    ))),
          ),
          // 楼层切换
          if (layers.length > 1)
            Positioned(
                right: 16,
                bottom: !isEditMode ? 80 : 30,
                child: Column(children: [
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
                      backgroundColor:
                          layerIndex > 0 ? Colors.orange : Colors.grey[800],
                      onPressed: layerIndex > 0
                          ? () => ref
                              .read(selectedLayerIndexProvider.notifier)
                              .state--
                          : null,
                      child: const Icon(Icons.arrow_downward)),
                ])),
          // 出生点侧边栏
          if (showSpawnPoints && spawnConfig != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: isEditMode ? 0 : 60,
              child: _buildSpawnPointSidebar(
                  spawnConfig, currentLayer.id, isEditMode),
            ),
          // 底部收藏栏
          if (!isEditMode)
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildFavoritesBar(grenadesAsync)),
        ]);
      }),
    );
  }
}
