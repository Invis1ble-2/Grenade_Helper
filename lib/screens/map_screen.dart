import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:photo_view/photo_view.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../providers.dart';
import '../main.dart';
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
    {double threshold = 0.03}) {
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
  bool _isMovingCluster = false;

  @override
  void initState() {
    super.initState();
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
    // 离开地图时清除悬浮窗状态
    globalOverlayState?.clearMap();
    // 通知独立悬浮窗清除地图
    _notifyOverlayWindowClearMap();
    super.dispose();
  }

  void _updateOverlayState(int layerIndex) {
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    if (layerIndex < layers.length) {
      final layer = layers[layerIndex];
      globalOverlayState?.setCurrentMap(widget.gameMap, layer);
      // 通知独立悬浮窗
      _notifyOverlayWindowSetMap(widget.gameMap.id, layer.id);
    }
  }

  void _notifyOverlayWindowSetMap(int mapId, int layerId) {
    if (overlayWindowController != null) {
      try {
        overlayWindowController!.invokeMethod('set_map', {
          'map_id': mapId,
          'layer_id': layerId,
        });
      } catch (_) {}
    }
  }

  void _notifyOverlayWindowClearMap() {
    if (overlayWindowController != null) {
      try {
        overlayWindowController!.invokeMethod('clear_map');
      } catch (_) {}
    }
  }

  void _handleTap(
      TapUpDetails details, double width, double height, int layerId) {
    if (_isMovingCluster) {
      _handleMoveClusterTap(details, width, height);
      return;
    }
    final isEditMode = ref.read(isEditModeProvider);
    if (!isEditMode) return;

    // 计算点击位置比例
    final xRatio = details.localPosition.dx / width;
    final yRatio = details.localPosition.dy / height;

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

  void _handleClusterTap(GrenadeCluster cluster, int layerId) {
    _showClusterBottomSheet(cluster, layerId);
  }

  void _showClusterBottomSheet(GrenadeCluster cluster, int layerId) {
    final isEditMode = ref.read(isEditModeProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2126),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final grenades = cluster.grenades;
          return DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.25,
            maxChildSize: 0.7,
            expand: false,
            builder: (_, scrollController) {
              return Column(
                children: [
                  Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("该点位共 ${grenades.length} 个道具",
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        if (isEditMode)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _startMoveCluster(cluster);
                              },
                              icon: const Icon(Icons.open_with, size: 18),
                              label: const Text("移动"),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.cyan,
                                  side: const BorderSide(color: Colors.cyan)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _createGrenadeAtCluster(cluster, layerId);
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text("添加"),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white),
                            ),
                          ]),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: grenades.length,
                      itemBuilder: (_, index) {
                        final g = grenades[index];
                        final color = _getTeamColor(g.team);
                        final icon = _getTypeIcon(g.type);
                        return Dismissible(
                          key: ValueKey(g.id),
                          direction: isEditMode
                              ? DismissDirection.endToStart
                              : DismissDirection.none,
                          background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete,
                                  color: Colors.white)),
                          confirmDismiss: (_) async =>
                              await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF2A2D33),
                                        title: const Text("确认删除",
                                            style:
                                                TextStyle(color: Colors.white)),
                                        content: Text("确定要删除「${g.title}」吗？",
                                            style: const TextStyle(
                                                color: Colors.grey)),
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
                                                      color: Colors.red)))
                                        ],
                                      )) ??
                              false,
                          onDismissed: (_) {
                            _deleteGrenade(g);
                            setModalState(() {
                              cluster.grenades.remove(g);
                            });
                            if (cluster.grenades.isEmpty)
                              Navigator.pop(context);
                          },
                          child: ListTile(
                            leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 2)),
                                child: Icon(icon, size: 18, color: color)),
                            title: Text(g.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(
                                "${_getTypeName(g.type)} • ${_getTeamName(g.team)}",
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (g.isFavorite)
                                const Icon(Icons.star,
                                    color: Colors.amber, size: 18),
                              if (g.isNewImport)
                                Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: const Text("NEW",
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white))),
                              const Icon(Icons.chevron_right,
                                  color: Colors.grey),
                            ]),
                            onTap: () {
                              Navigator.pop(context);
                              _handleGrenadeTap(g, isEditing: isEditMode);
                            },
                          ),
                        );
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

  void _deleteGrenade(Grenade g) async {
    final isar = ref.read(isarProvider);
    g.steps.loadSync();
    await isar.writeTxn(() async {
      for (final step in g.steps) {
        step.medias.loadSync();
        await isar.stepMedias.deleteAll(step.medias.map((m) => m.id).toList());
      }
      await isar.grenadeSteps.deleteAll(g.steps.map((s) => s.id).toList());
      await isar.grenades.delete(g.id);
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
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _handleMoveClusterTap(
      TapUpDetails details, double width, double height) async {
    if (_draggingCluster == null) return;
    final newX = details.localPosition.dx / width;
    final newY = details.localPosition.dy / height;

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
    });
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
                color: isSelected ? activeColor : Colors.grey.shade700),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, size: 16, color: isSelected ? activeColor : Colors.grey),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: isSelected ? activeColor : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold))
        ]),
      ),
    );
  }

  Widget _buildFilterChip(
      String label, int value, int groupValue, Color color) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => ref.read(teamFilterProvider.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            border:
                Border.all(color: isSelected ? color : Colors.grey.shade700),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? color : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12)),
      ),
    );
  }

  Widget _buildClusterMarker(GrenadeCluster cluster, BoxConstraints constraints,
      bool isEditMode, int layerId) {
    final color = _getTeamColor(cluster.primaryTeam);
    final icon = _getTypeIcon(cluster.primaryType);
    final count = cluster.grenades.length;
    return Positioned(
      left: cluster.xRatio * constraints.maxWidth - 10,
      top: cluster.yRatio * constraints.maxHeight - 10,
      child: GestureDetector(
        onTap: () => _handleClusterTap(cluster, layerId),
        onLongPressStart: isEditMode
            ? (_) {
                setState(() {
                  _draggingCluster = cluster;
                  _dragOffset = Offset(cluster.xRatio, cluster.yRatio);
                });
              }
            : null,
        onLongPressMoveUpdate: isEditMode
            ? (details) {
                setState(() {
                  _dragOffset = Offset(
                      details.localPosition.dx / constraints.maxWidth +
                          cluster.xRatio -
                          10 / constraints.maxWidth,
                      details.localPosition.dy / constraints.maxHeight +
                          cluster.yRatio -
                          10 / constraints.maxHeight);
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
                  color: Colors.black87,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                  boxShadow: [
                    if (cluster.hasFavorite)
                      BoxShadow(
                          color: color.withOpacity(0.6),
                          blurRadius: 4,
                          spreadRadius: 1)
                  ]),
              child: Icon(cluster.hasMultipleTypes ? Icons.layers : icon,
                  size: 10,
                  color:
                      cluster.hasMultipleTypes ? Colors.purpleAccent : color)),
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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.gameMap.name,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(currentLayer.name,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(children: [
                Text(isEditMode ? "编辑模式" : "浏览模式",
                    style: TextStyle(
                        color: isEditMode ? Colors.redAccent : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(width: 8),
                Switch(
                    value: isEditMode,
                    activeColor: Colors.redAccent,
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.grey.withOpacity(0.3),
                    onChanged: (val) =>
                        ref.read(isEditModeProvider.notifier).state = val),
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
                ]))),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        return Stack(children: [
          Positioned.fill(
              child: PhotoView.customChild(
            key: ValueKey(currentLayer.id),
            initialScale: PhotoViewComputedScale.covered,
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 5.0,
            child: GestureDetector(
                onTapUp: (d) => _handleTap(d, constraints.maxWidth,
                    constraints.maxHeight, currentLayer.id),
                child: Stack(children: [
                  Image.asset(currentLayer.assetPath,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.contain),
                  ...grenadesAsync.when(
                      data: (list) {
                        final clusters = clusterGrenades(list);
                        return clusters.map((c) => _buildClusterMarker(
                            c, constraints, isEditMode, currentLayer.id));
                      },
                      error: (_, __) => [],
                      loading: () => []),
                  if (_draggingCluster != null && _dragOffset != null)
                    Positioned(
                        left: _dragOffset!.dx * constraints.maxWidth - 14,
                        top: _dragOffset!.dy * constraints.maxHeight - 14,
                        child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.8),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2)),
                            child: const Icon(Icons.place,
                                size: 16, color: Colors.white))),
                  if (_tempTapPosition != null)
                    Positioned(
                        left: _tempTapPosition!.dx * constraints.maxWidth - 12,
                        top: _tempTapPosition!.dy * constraints.maxHeight - 12,
                        child: const Icon(Icons.add_circle,
                            color: Colors.greenAccent, size: 24)),
                ])),
          )),
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
                            Container(
                                height: 45,
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(color: Colors.white24)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(children: [
                                  const Icon(Icons.search,
                                      color: Colors.grey, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Autocomplete<Grenade>(
                                    optionsBuilder: (textEditingValue) {
                                      if (textEditingValue.text.isEmpty)
                                        return const Iterable<Grenade>.empty();
                                      return allMapGrenades.where((g) => g.title
                                          .toLowerCase()
                                          .contains(textEditingValue.text
                                              .toLowerCase()));
                                    },
                                    displayStringForOption: (g) => g.title,
                                    onSelected: _onSearchResultSelected,
                                    optionsViewBuilder:
                                        (context, onSelected, options) => Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                                elevation: 8.0,
                                                color: const Color(0xFF2A2D33),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Container(
                                                    width:
                                                        constraints.maxWidth -
                                                            40,
                                                    constraints:
                                                        const BoxConstraints(
                                                            maxHeight: 250),
                                                    child: ListView.builder(
                                                        padding:
                                                            EdgeInsets.zero,
                                                        shrinkWrap: true,
                                                        itemCount:
                                                            options.length,
                                                        itemBuilder:
                                                            (context, index) {
                                                          final option = options
                                                              .elementAt(index);
                                                          option.layer
                                                              .loadSync();
                                                          return ListTile(
                                                              title: Text(
                                                                  option.title,
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white)),
                                                              subtitle: Text(
                                                                  "${option.layer.value?.name ?? ''} • ${_getTypeName(option.type)}",
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .grey,
                                                                      fontSize:
                                                                          12)),
                                                              onTap: () =>
                                                                  onSelected(
                                                                      option));
                                                        })))),
                                    fieldViewBuilder: (context, controller,
                                            focusNode, onFieldSubmitted) =>
                                        TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            style: const TextStyle(
                                                color: Colors.white),
                                            decoration: const InputDecoration(
                                                hintText: "搜索本图道具...",
                                                hintStyle: TextStyle(
                                                    color: Colors.grey),
                                                border: InputBorder.none)),
                                  )),
                                ])),
                          ])))),
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
