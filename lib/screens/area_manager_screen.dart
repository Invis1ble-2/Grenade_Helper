import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../models.dart';
import '../providers.dart';
import '../services/area_service.dart';
import 'area_draw_screen.dart';
import 'area_auto_tag_preview_screen.dart';
import 'default_area_tag_dev_editor_screen.dart';

/// 区域管理界面
class AreaManagerScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;

  const AreaManagerScreen({super.key, required this.gameMap});

  @override
  ConsumerState<AreaManagerScreen> createState() => _AreaManagerScreenState();
}

class _AreaManagerScreenState extends ConsumerState<AreaManagerScreen> {
  List<MapArea> _customAreas = [];
  List<MapArea> _defaultAreas = [];
  Map<int, Tag> _areaTagsById = {};
  bool _isLoading = true;
  bool _isAutoTaggingAll = false;
  bool _autoTagByImpact = false;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    final areas = await areaService.getAreas(widget.gameMap.id);
    final areaTags = await isar.tags
        .filter()
        .mapIdEqualTo(widget.gameMap.id)
        .dimensionEqualTo(TagDimension.area)
        .findAll();
    final tagsById = {for (final t in areaTags) t.id: t};
    final customAreas = <MapArea>[];
    final defaultAreas = <MapArea>[];

    for (final area in areas) {
      final tag = tagsById[area.tagId];
      if (tag?.isSystem == true) {
        defaultAreas.add(area);
      } else {
        customAreas.add(area);
      }
    }

    int sortByTime(MapArea a, MapArea b) {
      if (a.createdAt.isAfter(b.createdAt)) return -1;
      if (a.createdAt.isBefore(b.createdAt)) return 1;
      return b.id.compareTo(a.id);
    }

    customAreas.sort(sortByTime);
    defaultAreas.sort(sortByTime);

    if (!mounted) return;
    setState(() {
      _customAreas = customAreas;
      _defaultAreas = defaultAreas;
      _areaTagsById = tagsById;
      _isLoading = false;
    });
  }

  Future<MapLayer?> _selectLayer(List<MapLayer> layers) async {
    return showDialog<MapLayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择楼层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: layers
              .map((l) => ListTile(
                    title: Text(l.name),
                    onTap: () => Navigator.pop(ctx, l),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _createArea() async {
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    if (layers.isEmpty) return;

    final layer =
        layers.length == 1 ? layers.first : await _selectLayer(layers);
    if (layer == null) return;
    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaDrawScreen(gameMap: widget.gameMap, layer: layer),
      ),
    );
    if (result == true) _loadAreas();
  }

  Future<void> _deleteArea(MapArea area) async {
    final isDefault = _areaTagsById[area.tagId]?.isSystem == true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除区域'),
        content: Text(isDefault
            ? '确定删除区域 "${area.name}"？\n仅删除区域几何，保留默认标签。'
            : '确定删除区域 "${area.name}"？\n关联的标签也会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;

    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    await areaService.deleteArea(area, deleteTag: !isDefault);
    _loadAreas();
  }

  Future<void> _editArea(MapArea area) async {
    if (area.layerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('该区域未关联楼层，无法编辑'), backgroundColor: Colors.red));
      return;
    }

    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(area.layerId!);

    if (layer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('关联楼层不存在'), backgroundColor: Colors.red));
      return;
    }

    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => AreaDrawScreen(
              gameMap: widget.gameMap, layer: layer, area: area)),
    );
    if (result == true) _loadAreas();
  }

  Future<void> _openAreaAutoTag(MapArea area) async {
    if (area.layerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('该区域未关联楼层，无法可视化标注'), backgroundColor: Colors.red));
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaAutoTagPreviewScreen(
          gameMap: widget.gameMap,
          area: area,
        ),
      ),
    );
    if (mounted) {
      _loadAreas();
    }
  }

  Future<void> _quickAutoTagAllGrenades() async {
    if (_isAutoTaggingAll) return;
    if (_customAreas.isEmpty && _defaultAreas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('当前地图还没有区域数据，无法自动添加标签'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    bool selectedByImpact = _autoTagByImpact;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('全图自动添加区域标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('将按当前区域数据为该地图所有道具自动同步区域标签。'),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('按站位')),
                  ButtonSegment<bool>(value: true, label: Text('按爆点')),
                ],
                selected: {selectedByImpact},
                onSelectionChanged: (values) {
                  setDialogState(() => selectedByImpact = values.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _autoTagByImpact = selectedByImpact);

    setState(() => _isAutoTaggingAll = true);
    try {
      final isar = ref.read(isarProvider);
      final areaService = AreaService(isar);
      final result = await areaService.autoTagAllGrenades(
        widget.gameMap.id,
        useImpactPoint: selectedByImpact,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${selectedByImpact ? "按爆点" : "按站位"}全图同步完成：处理${result.processedGrenades}个，命中${result.matchedGrenades}个，新增${result.addedLinks}条，移除${result.removedLinks}条'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('全图自动添加失败：$e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) {
        setState(() => _isAutoTaggingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarActions = <Widget>[
      IconButton(
        tooltip: '全图自动添加区域标签',
        onPressed: _isAutoTaggingAll ? null : _quickAutoTagAllGrenades,
        icon: _isAutoTaggingAll
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_fix_high),
      ),
      if (kDebugMode)
        IconButton(
          tooltip: '默认标签开发编辑器',
          icon: const Icon(Icons.construction_outlined),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    DefaultAreaTagDevEditorScreen(gameMap: widget.gameMap),
              ),
            );
            if (mounted) _loadAreas();
          },
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.gameMap.name} 区域管理'),
        actions: appBarActions,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createArea,
        icon: const Icon(Icons.add),
        label: const Text('新建区域'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_customAreas.isEmpty && _defaultAreas.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined,
                          size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text('暂无区域',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('点击下方按钮创建区域',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_customAreas.isNotEmpty) ...[
                      _buildSectionHeader('自定义区域', _customAreas.length),
                      ..._customAreas.map((area) => _buildAreaTile(area)),
                    ],
                    if (_defaultAreas.isNotEmpty) ...[
                      _buildSectionHeader('默认标签区域', _defaultAreas.length),
                      ..._defaultAreas.map((area) => _buildAreaTile(area)),
                    ],
                  ],
                ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaTile(MapArea area) {
    final isDefault = _areaTagsById[area.tagId]?.isSystem == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color(area.colorValue).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Color(area.colorValue)),
          ),
          child: Icon(Icons.map, color: Color(area.colorValue)),
        ),
        title: Text(
          area.name,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isDefault
              ? '默认标签'
              : '自定义 · 创建于 ${area.createdAt.toString().substring(0, 16)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '可视化自动添加该区域标签',
              onPressed: () => _openAreaAutoTag(area),
              icon: const Icon(Icons.auto_awesome, color: Colors.greenAccent),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
              onPressed: () => _editArea(area),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteArea(area),
            ),
          ],
        ),
      ),
    );
  }
}
