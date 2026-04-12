import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models.dart';
import '../providers.dart';
import '../main.dart';
import '../services/map_management_service.dart';
import '../widgets/fireworks_effect.dart';
import '../widgets/snowfall_effect.dart';
import '../widgets/map_icon.dart';
import '../widgets/path_image_provider.dart';
import 'map_screen.dart';
import 'grenade_detail_screen.dart';
import 'import_screen.dart';
import 'share_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'lan_sync_screen.dart';
import '../widgets/spring_festival_fu.dart';
import '../widgets/spring_festival_banner.dart';

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
          leading: Icon(_getTypeIcon(g.type)),
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
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

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
                        await isar.gameMaps.put(newMap);

                        final newLayer = MapLayer(
                          name: 'Default',
                          assetPath: copiedRadarPath,
                          sortOrder: 0,
                        );
                        await isar.mapLayers.put(newLayer);
                        newMap.layers.add(newLayer);
                        await newMap.layers.save();
                      });
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

  Widget _buildMapCard(BuildContext context, Isar isar, GameMap map) {
    final imageProvider = imageProviderFromPath(map.backgroundPath);
    final isCustomMap = MapManagementService.isCustomMap(map);

    Widget card = Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MapScreen(gameMap: map)),
        ),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF616161),
            image: imageProvider == null
                ? null
                : DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.4),
                      BlendMode.darken,
                    ),
                  ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MapIcon(path: map.iconPath, size: 40),
                const SizedBox(width: 16),
                Text(
                  map.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isCustomMap) {
      card = Dismissible(
        key: ValueKey('map-${map.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(16),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showAddCustomMapDialog(context, isar),
        child: Container(
          height: 120,
          color: const Color(0xFF757575),
          child: const Center(
            child: Text(
              '添加自定义地图',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isar = ref.watch(isarProvider);
    final maps = isar.gameMaps.where().findAllSync()
      ..sort((a, b) => a.id.compareTo(b.id));
    final visibleMaps = maps
        .where((map) => !_pendingDeleteMapIds.contains(map.id))
        .toList(growable: false);
    final seasonalTheme = ref.watch(activeSeasonalThemeProvider);
    final seasonalThemeId = seasonalTheme?.id;
    final isChristmasTheme = seasonalThemeId == 'christmas';
    final isSpringFestivalTheme = seasonalThemeId == 'spring_festival';

    Widget body = Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () =>
              showSearch(context: context, delegate: GlobalSearchDelegate(ref)),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20)),
            child: const Row(
              children: [
                Icon(Icons.search, color: Colors.grey),
                SizedBox(width: 8),
                Text("搜索道具...",
                    style: TextStyle(color: Colors.grey, fontSize: 14))
              ],
            ),
          ),
        ),
        // 圣诞灯带
        bottom: isChristmasTheme
            ? const PreferredSize(
                preferredSize: Size.fromHeight(24),
                child: ChristmasLights(height: 24),
              )
            : (isSpringFestivalTheme
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(40),
                    child: SpringFestivalBanner(),
                  )
                : null),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipOval(
                            child: Image.asset(
                              'assets/icons/app_icon.png',
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // 圣诞帽
                          if (isChristmasTheme)
                            const Positioned(
                              top: -25,
                              left: 5,
                              child: ChristmasHat(width: 70),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (seasonalTheme != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(seasonalTheme.emoji,
                                  style: const TextStyle(fontSize: 24)),
                            ),
                          const Text("Grenade Helper",
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                          if (seasonalTheme != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(seasonalTheme.emoji,
                                  style: const TextStyle(fontSize: 24)),
                            ),
                        ],
                      ),
                    ],
                  )),
                  ListTile(
                    leading: const Icon(Icons.file_download),
                    title: const Text("导入"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ImportScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share),
                    title: const Text("分享"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ShareScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.wifi_tethering),
                    title: const Text("局域网同步"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LanSyncScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text("设置"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                            settingsService: globalSettingsService,
                            onHotkeyChanged: (action, config) async {
                              if (globalHotkeyService != null) {
                                await globalHotkeyService!
                                    .updateHotkey(action, config);
                              }
                            },
                            onHotkeysReset: () async {
                              await globalHotkeyService?.reloadFromSettings();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text("关于"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (isSpringFestivalTheme)
              const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: SpringFestivalFu(size: 140),
              ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: visibleMaps.length + 1,
        itemBuilder: (ctx, index) {
          if (index == visibleMaps.length) {
            return _buildAddCustomMapCard(context, isar);
          }
          return _buildMapCard(context, isar, visibleMaps[index]);
        },
      ),
    );

    // 节日装饰（互斥触发）
    if (isChristmasTheme) {
      body = SnowfallEffect(
        snowflakeCount: 25,
        child: body,
      );
    } else if (isSpringFestivalTheme) {
      body = FireworksEffect(
        maxFireworks: 4,
        child: body,
      );
    }

    return body;
  }
}
