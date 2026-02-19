import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../providers.dart';
import '../services/area_service.dart';
import '../services/default_area_export_service.dart';
import '../services/tag_service.dart';
import 'area_auto_tag_preview_screen.dart';
import 'area_draw_screen.dart';

/// 默认区域标签开发者编辑器（仅 Debug 入口可见）
class DefaultAreaTagDevEditorScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;

  const DefaultAreaTagDevEditorScreen({super.key, required this.gameMap});

  @override
  ConsumerState<DefaultAreaTagDevEditorScreen> createState() =>
      _DefaultAreaTagDevEditorScreenState();
}

class _DefaultAreaTagDevEditorScreenState
    extends ConsumerState<DefaultAreaTagDevEditorScreen> {
  bool _loading = true;
  List<Tag> _defaultAreaTags = [];
  List<MapLayer> _layers = [];
  Map<int, List<MapArea>> _areasByTagId = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _indexKey(int tagId, int layerId) => '$tagId:$layerId';

  bool _isAreaNewer(MapArea a, MapArea b) {
    if (a.createdAt.isAfter(b.createdAt)) return true;
    if (a.createdAt.isBefore(b.createdAt)) return false;
    return a.id > b.id;
  }

  Future<List<MapArea>> _dedupeAndCleanupDefaultAreas({
    required List<MapArea> areas,
    required Set<int> defaultTagIds,
  }) async {
    final deduped = <String, MapArea>{};
    final obsolete = <MapArea>[];

    for (final area in areas) {
      final layerId = area.layerId;
      if (!defaultTagIds.contains(area.tagId) || layerId == null) continue;

      final key = _indexKey(area.tagId, layerId);
      final previous = deduped[key];
      if (previous == null) {
        deduped[key] = area;
        continue;
      }

      if (_isAreaNewer(area, previous)) {
        deduped[key] = area;
        obsolete.add(previous);
      } else {
        obsolete.add(area);
      }
    }

    if (obsolete.isNotEmpty) {
      final isar = ref.read(isarProvider);
      final areaService = AreaService(isar);
      for (final area in obsolete) {
        await areaService.deleteArea(area, deleteTag: false);
      }
    }

    return deduped.values.toList();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final isar = ref.read(isarProvider);
    final tagService = TagService(isar);
    final areaService = AreaService(isar);

    await tagService.initializeSystemTags(
      widget.gameMap.id,
      widget.gameMap.name,
    );

    final tags = await isar.tags
        .filter()
        .mapIdEqualTo(widget.gameMap.id)
        .dimensionEqualTo(TagDimension.area)
        .isSystemEqualTo(true)
        .sortBySortOrder()
        .findAll();

    final allAreas = await areaService.getAreas(widget.gameMap.id);
    final defaultTagIds = tags.map((t) => t.id).toSet();
    final areas = await _dedupeAndCleanupDefaultAreas(
      areas: allAreas,
      defaultTagIds: defaultTagIds,
    );

    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final areasByTagId = <int, List<MapArea>>{};
    for (final area in areas) {
      final layerId = area.layerId;
      if (layerId == null) continue;
      areasByTagId.putIfAbsent(area.tagId, () => []).add(area);
    }

    if (!mounted) return;
    setState(() {
      _defaultAreaTags = tags;
      _layers = layers;
      _areasByTagId = areasByTagId;
      _loading = false;
    });
  }

  List<MapArea> _getAreasForTag(int tagId) {
    final list = _areasByTagId[tagId];
    if (list == null || list.isEmpty) return const [];
    final layerOrder = {for (final l in _layers) l.id: l.sortOrder};
    final sorted = List<MapArea>.from(list);
    sorted.sort((a, b) {
      final aLayer = layerOrder[a.layerId] ?? 1 << 30;
      final bLayer = layerOrder[b.layerId] ?? 1 << 30;
      if (aLayer != bLayer) return aLayer.compareTo(bLayer);
      if (a.createdAt.isAfter(b.createdAt)) return -1;
      if (a.createdAt.isBefore(b.createdAt)) return 1;
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  int _configuredLayerCount(int tagId) => _getAreasForTag(tagId).length;

  String _layerNameById(int? layerId) {
    if (layerId == null) return '未知楼层';
    for (final l in _layers) {
      if (l.id == layerId) return l.name;
    }
    return '未知楼层';
  }

  MapArea? _findPrimaryAreaForTag(int tagId) {
    final areas = _getAreasForTag(tagId);
    if (areas.isEmpty) return null;
    return areas.first;
  }

  Future<MapArea?> _pickAreaForTagAction(Tag tag, String title) async {
    final areas = _getAreasForTag(tag.id);
    if (areas.isEmpty) return null;
    if (areas.length == 1) return areas.first;

    return showDialog<MapArea>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: areas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final area = areas[index];
              return ListTile(
                title: Text(_layerNameById(area.layerId)),
                subtitle:
                    Text('创建于 ${area.createdAt.toString().substring(0, 16)}'),
                onTap: () => Navigator.pop(ctx, area),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDrawForTag(Tag tag) async {
    final existingArea = _findPrimaryAreaForTag(tag.id);
    final layer = (existingArea != null && existingArea.layerId != null)
        ? _layers.firstWhere(
            (l) => l.id == existingArea.layerId,
            orElse: () => _layers.first,
          )
        : _layers.first;

    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaDrawScreen(
          gameMap: widget.gameMap,
          layer: layer,
          area: existingArea,
          existingTagId: existingArea == null ? tag.id : null,
          initialName: existingArea == null ? tag.name : null,
          initialColor: existingArea == null ? tag.colorValue : null,
        ),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _deleteAreaForTag(Tag tag) async {
    final target = await _pickAreaForTagAction(tag, '选择要删除的楼层区域');
    if (target == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除区域数据'),
        content: Text(
            '确认删除「${tag.name}」在「${_layerNameById(target.layerId)}」的区域几何数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    await areaService.deleteArea(target, deleteTag: false);
    _loadData();
  }

  Future<void> _openAreaAutoTag(MapArea area) async {
    if (area.layerId == null) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAutoTagPreviewScreen(
          gameMap: widget.gameMap,
          area: area,
        ),
      ),
    );
    if (mounted) _loadData();
  }

  Future<void> _exportCurrentMap() async {
    final isar = ref.read(isarProvider);
    final exportService = const DefaultAreaExportService();
    final code = await exportService.exportCurrentMapDefaultAreaPresets(
      map: widget.gameMap,
      isar: isar,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出当前地图默认区域常量'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('已复制导出代码到剪贴板'),
                duration: Duration(seconds: 1),
              ));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制代码'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('默认区域开发编辑器')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_layers.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('默认区域开发编辑器')),
        body: const Center(child: Text('当前地图没有楼层数据，无法编辑')),
      );
    }

    final completedCount = _defaultAreaTags
        .where((tag) => _configuredLayerCount(tag.id) > 0)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.gameMap.name} 默认区域开发编辑器'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '导出当前地图默认区域常量',
            onPressed: _exportCurrentMap,
            icon: const Icon(Icons.code),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.centerLeft,
            child: Text('已配置 $completedCount / ${_defaultAreaTags.length}'),
          ),
          Expanded(
            child: _defaultAreaTags.isEmpty
                ? const Center(child: Text('当前地图没有系统区域标签'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _defaultAreaTags.length,
                    itemBuilder: (ctx, index) {
                      final tag = _defaultAreaTags[index];
                      final area = _findPrimaryAreaForTag(tag.id);
                      final layerCount = _configuredLayerCount(tag.id);
                      final done = layerCount > 0;
                      final color = Color(tag.colorValue);
                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: color),
                            ),
                          ),
                          title: Text(tag.name),
                          subtitle: Text(done
                              ? '已配置 $layerCount 层（入口楼层：${_layerNameById(area?.layerId)}）'
                              : '未配置区域数据'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (area != null)
                                IconButton(
                                  tooltip: '可视化自动添加该区域标签',
                                  onPressed: () => _openAreaAutoTag(area),
                                  icon: const Icon(Icons.auto_awesome,
                                      color: Colors.greenAccent),
                                ),
                              IconButton(
                                tooltip: done ? '编辑区域数据' : '新建区域数据',
                                onPressed: () => _openDrawForTag(tag),
                                icon: Icon(
                                  done ? Icons.edit : Icons.add,
                                  color: done
                                      ? Colors.blueAccent
                                      : Colors.lightGreenAccent,
                                ),
                              ),
                              if (done)
                                IconButton(
                                  tooltip: '删除区域几何',
                                  onPressed: () => _deleteAreaForTag(tag),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
