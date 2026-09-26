import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models.dart';
import '../providers.dart';
import '../services/map_management_service.dart';
import '../services/tag_service.dart';
import '../widgets/map_icon.dart';
import '../widgets/path_image_provider.dart';
import '../widgets/grenade_type_icon.dart';
import '../theme/app_design_system.dart';
import 'map_screen.dart';
import 'grenade_detail_screen.dart';

// 全局搜索
class GlobalSearchDelegate extends SearchDelegate {
  final WidgetRef ref;
  GlobalSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);
  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    if (query.isEmpty) return const SizedBox();

    final isar = ref.read(isarProvider);
    // 模糊搜索
    final results = isar.grenades
        .filter()
        .titleContains(query, caseSensitive: false)
        .findAllSync();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (ctx, index) {
        final g = results[index];
        g.layer.loadSync();
        g.layer.value?.map.loadSync();
        final mapName = g.layer.value?.map.value?.name ?? "";
        return ListTile(
          leading: GrenadeTypeIcon(type: g.type),
          title: Text(g.title),
          subtitle: Text(mapName, style: const TextStyle(color: Colors.orange)),
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => GrenadeDetailScreen(
                        grenadeId: g.id, isEditing: false)));
          },
        );
      },
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const HomeScreen({super.key, this.embedded = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final Set<int> _pendingDeleteMapIds = <int>{};

  Future<bool> _deleteCustomMapQuick(Isar isar, GameMap map) async {
    if (!MapManagementService.isCustomMap(map)) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持删除自定义地图')),
      );
      return false;
    }

    try {
      final deleted = await MapManagementService(isar).deleteCustomMaps([map]);
      if (!mounted) return deleted > 0;
      if (deleted > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除自定义地图：${map.name}')),
        );
        return true;
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
    return false;
  }

  Future<void> _queueCustomMapDelete(Isar isar, GameMap map) async {
    if (_pendingDeleteMapIds.contains(map.id)) return;
    setState(() {
      _pendingDeleteMapIds.add(map.id);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    var undone = false;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('已移除「${map.name}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() {
              _pendingDeleteMapIds.remove(map.id);
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    await Future.delayed(const Duration(seconds: 4));
    controller.close();

    if (!mounted) return;
    if (undone) return;
    if (!_pendingDeleteMapIds.contains(map.id)) return;

    await _deleteCustomMapQuick(isar, map);
    if (!mounted) return;
    setState(() {
      _pendingDeleteMapIds.remove(map.id);
    });
  }

  Future<String> _copyCustomMapFileToDataDir(
      Isar isar, String sourcePath) async {
    final normalized = sourcePath.trim();
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('assets/')) return normalized;

    final sourceFile = File(normalized);
    if (!await sourceFile.exists()) {
      throw StateError('文件不存在：$normalized');
    }

    final dataPath = (isar.directory ?? '').trim();
    if (dataPath.isEmpty) {
      throw StateError('数据目录不可用');
    }

    final extension = p.extension(sourceFile.path);
    final targetPath = p.join(dataPath, '${const Uuid().v4()}$extension');
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<void> _showAddCustomMapDialog(
      BuildContext parentContext, Isar isar) async {
    String mapNameInput = '';
    String? radarPath;
    String? backgroundPath;
    String? iconPath;

    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickRadarImage() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: false,
                dialogTitle: '选择雷达图',
              );
              final selectedPath = result?.files.single.path?.trim();
              if (selectedPath == null || selectedPath.isEmpty) return;
              setDialogState(() {
                radarPath = selectedPath;
              });
            }

            Future<void> pickOptionalIcon() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const [
                  'png',
                  'jpg',
                  'jpeg',
                  'webp',
                  'bmp',
                  'gif',
                  'svg',
                ],
                allowMultiple: false,
                dialogTitle: '选择地图图标（可选）',
              );
              final selectedPath = result?.files.single.path?.trim();
              if (selectedPath == null || selectedPath.isEmpty) return;
              setDialogState(() {
                iconPath = selectedPath;
              });
            }

            Future<void> pickOptionalBackgroundImage() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: false,
                dialogTitle: '选择地图背景图（可选）',
              );
              final selectedPath = result?.files.single.path?.trim();
              if (selectedPath == null || selectedPath.isEmpty) return;
              setDialogState(() {
                backgroundPath = selectedPath;
              });
            }

            return AlertDialog(
              title: const Text('添加自定义地图'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (value) {
                      mapNameInput = value;
                    },
                    decoration: const InputDecoration(
                      labelText: '地图名称',
                      hintText: '例如：Cache',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Text('雷达图（必选）')),
                      OutlinedButton(
                        onPressed: pickRadarImage,
                        child: const Text('选择图片'),
                      ),
                    ],
                  ),
                  if (radarPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        p.basename(radarPath!),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('背景图（可选）')),
                      OutlinedButton(
                        onPressed: pickOptionalBackgroundImage,
                        child: const Text('选择背景'),
                      ),
                    ],
                  ),
                  if (backgroundPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        p.basename(backgroundPath!),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('地图图标（可选）')),
                      OutlinedButton(
                        onPressed: pickOptionalIcon,
                        child: const Text('选择图标'),
                      ),
                    ],
                  ),
                  if (iconPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        p.basename(iconPath!),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final mapName = mapNameInput.trim();
                    if (mapName.isEmpty) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(content: Text('请输入地图名称')),
                      );
                      return;
                    }
                    if (radarPath == null || radarPath!.isEmpty) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(content: Text('请先选择雷达图')),
                      );
                      return;
                    }

                    final existed = await isar.gameMaps
                        .filter()
                        .nameEqualTo(mapName, caseSensitive: false)
                        .findFirst();
                    if (!mounted) return;
                    if (!parentContext.mounted) return;
                    if (existed != null) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(content: Text('地图名称已存在')),
                      );
                      return;
                    }

                    try {
                      int? newMapId;
                      final tagService = TagService(isar);
                      final copiedRadarPath =
                          await _copyCustomMapFileToDataDir(isar, radarPath!);
                      final copiedBackgroundPath =
                          (backgroundPath?.trim().isNotEmpty ?? false)
                              ? await _copyCustomMapFileToDataDir(
                                  isar, backgroundPath!)
                              : copiedRadarPath;
                      final copiedIconPath = (iconPath?.trim().isNotEmpty ??
                              false)
                          ? await _copyCustomMapFileToDataDir(isar, iconPath!)
                          : '';

                      await isar.writeTxn(() async {
                        final newMap = GameMap(
                          name: mapName,
                          backgroundPath: copiedBackgroundPath,
                          iconPath: copiedIconPath,
                        );
                        newMapId = await isar.gameMaps.put(newMap);

                        final newLayer = MapLayer(
                          name: 'Default',
                          assetPath: copiedRadarPath,
                          sortOrder: 0,
                        );
                        await isar.mapLayers.put(newLayer);
                        newMap.layers.add(newLayer);
                        await newMap.layers.save();
                      });
                      if (newMapId != null) {
                        await tagService
                            .clearDeletedSystemTagRecordsForMap(newMapId!);
                        await tagService.initializeSystemTags(
                            newMapId!, mapName);
                      }
                    } catch (e) {
                      if (!mounted) return;
                      if (!parentContext.mounted) return;
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text('添加失败：$e')),
                      );
                      return;
                    }

                    if (!mounted) return;
                    if (!parentContext.mounted) return;
                    Navigator.pop(dialogContext);
                    setState(() {});
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(content: Text('已添加地图：$mapName')),
                    );
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _mapGrenadeCount(GameMap map) {
    map.layers.loadSync();
    var grenades = 0;
    for (final layer in map.layers) {
      layer.grenades.loadSync();
      grenades += layer.grenades.length;
    }
    return grenades;
  }

  Widget _buildMapCard(
      BuildContext context, Isar isar, GameMap map, int index) {
    final isCustomMap = MapManagementService.isCustomMap(map);
    final grenadeCount = _mapGrenadeCount(map);

    Widget card = _HomeMapCard(
      map: map,
      index: index,
      grenadeCount: grenadeCount,
      isCustomMap: isCustomMap,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MapScreen(gameMap: map)),
      ),
    );

    if (isCustomMap) {
      card = Dismissible(
        key: ValueKey('map-${map.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.delete_forever, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '删除地图',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        confirmDismiss: (_) async => true,
        onDismissed: (_) => _queueCustomMapDelete(isar, map),
        child: card,
      );
    }

    return card;
  }

  Widget _buildAddCustomMapCard(
    BuildContext context,
    Isar isar,
  ) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: context.appTheme.subtleBorder),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showAddCustomMapDialog(context, isar),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_photo_alternate_outlined,
                    size: 32, color: context.appTheme.mutedText),
                const SizedBox(height: 12),
                const Text('添加自定义地图',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('导入雷达图并建立自己的点位库',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appTheme.mutedText,
                        )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _compareHomeMaps(GameMap a, GameMap b) {
    final aIsCustom = MapManagementService.isCustomMap(a);
    final bIsCustom = MapManagementService.isCustomMap(b);
    if (aIsCustom != bIsCustom) {
      return aIsCustom ? 1 : -1;
    }
    return a.id.compareTo(b.id);
  }

  @override
  Widget build(BuildContext context) {
    final isar = ref.watch(isarProvider);
    final maps = isar.gameMaps.where().findAllSync()..sort(_compareHomeMaps);
    final visibleMaps = maps
        .where((map) => !_pendingDeleteMapIds.contains(map.id))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: !widget.embedded,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  AppBreakpoints.isMobile(context) ? 16 : 24,
                  20,
                  AppBreakpoints.isMobile(context) ? 16 : 24,
                  14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('地图库',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('${visibleMaps.length} 张地图',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: context.appTheme.mutedText)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: AppBreakpoints.isMobile(context) ? 220 : 360),
                    child: TextField(
                      readOnly: true,
                      onTap: () => showSearch(
                          context: context,
                          delegate: GlobalSearchDelegate(ref)),
                      decoration: const InputDecoration(
                          fillColor: Colors.transparent,
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: '搜索全部道具'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1280
                      ? 3
                      : (constraints.maxWidth >= 720 ? 2 : 1);
                  final gridPadding = EdgeInsets.fromLTRB(
                    AppBreakpoints.isMobile(context) ? 16 : 24,
                    8,
                    AppBreakpoints.isMobile(context) ? 16 : 24,
                    24,
                  );
                  return GridView.builder(
                    padding: AppBreakpoints.isMobile(context)
                        ? AppBreakpoints.withMobileBottomBarClearance(
                            context,
                            gridPadding,
                          )
                        : gridPadding,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 220,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: visibleMaps.length + 1,
                    itemBuilder: (ctx, index) => index == visibleMaps.length
                        ? _buildAddCustomMapCard(context, isar)
                        : _buildMapCard(
                            context, isar, visibleMaps[index], index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeMapCard extends StatefulWidget {
  final GameMap map;
  final int index;
  final int grenadeCount;
  final bool isCustomMap;
  final VoidCallback onTap;

  const _HomeMapCard({
    required this.map,
    required this.index,
    required this.grenadeCount,
    required this.isCustomMap,
    required this.onTap,
  });

  @override
  State<_HomeMapCard> createState() => _HomeMapCardState();
}

class _HomeMapCardState extends State<_HomeMapCard> {
  bool _hovered = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 35 * widget.index.clamp(0, 8)), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = imageProviderFromPath(widget.map.backgroundPath);
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.04),
      duration: AppMotion.panel,
      curve: AppMotion.enter,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: AppMotion.panel,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: _hovered ? 1.035 : 1,
                    duration: AppMotion.content,
                    curve: AppMotion.enter,
                    child: imageProvider == null
                        ? Container(color: const Color(0xFF30343A))
                        : Image(image: imageProvider, fit: BoxFit.cover),
                  ),
                  Positioned.fill(
                      child: ColoredBox(
                          color: Colors.black
                              .withValues(alpha: _hovered ? 0.28 : 0.38))),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: AnimatedSlide(
                      offset: _hovered ? const Offset(0, -0.03) : Offset.zero,
                      duration: AppMotion.quick,
                      child: Row(
                        children: [
                          Hero(
                              tag: 'map-icon-${widget.map.id}',
                              child:
                                  MapIcon(path: widget.map.iconPath, size: 40)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.map.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text('${widget.grenadeCount} 个道具',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.76),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                  if (widget.isCustomMap)
                    Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.54),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('自定义',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
            metric.extractPath(
                distance, (distance + 7).clamp(0, metric.length)),
            paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
