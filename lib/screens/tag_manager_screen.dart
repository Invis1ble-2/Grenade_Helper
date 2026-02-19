import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import '../models/map_area.dart';
import '../models/tag.dart';
import '../models.dart';
import '../services/area_service.dart';
import '../services/tag_service.dart';
import '../widgets/color_picker_widget.dart';
import '../providers.dart';
import 'area_draw_screen.dart';

class TagManagerScreen extends ConsumerStatefulWidget {
  final int mapId;
  final String mapName;

  const TagManagerScreen(
      {super.key, required this.mapId, required this.mapName});

  @override
  ConsumerState<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends ConsumerState<TagManagerScreen> {
  late TagService _tagService;
  List<Tag> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final isar = ref.read(isarProvider);
    _tagService = TagService(isar);
    await _tagService.initializeSystemTags(widget.mapId, widget.mapName);
    await _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() => _isLoading = true);
    final tags = await _tagService.getAllTags(widget.mapId);
    setState(() {
      _tags = tags;
      _isLoading = false;
    });
  }

  Future<void> _createTag() async {
    final templateOptions = await _loadAreaTemplateOptions();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateTagDialog(areaTemplateOptions: templateOptions),
    );
    if (result != null && result['action'] == 'save') {
      final createdTag = await _tagService.createTag(
          widget.mapId, result['name'], result['color'],
          dimension: result['dimension']);
      await _handleAreaTagPostSetup(createdTag, result);
      await _loadTags();
    }
  }

  Future<List<_AreaTemplateOption>> _loadAreaTemplateOptions() async {
    final isar = ref.read(isarProvider);
    final areas =
        await isar.mapAreas.filter().mapIdEqualTo(widget.mapId).findAll();
    if (areas.isEmpty) return const [];

    final layerNameById = <int, String>{};
    for (final area in areas) {
      final layerId = area.layerId;
      if (layerId == null || layerNameById.containsKey(layerId)) continue;
      final layer = await isar.mapLayers.get(layerId);
      if (layer != null) {
        layerNameById[layerId] = layer.name;
      }
    }

    final sorted = List<MapArea>.from(areas)
      ..sort((a, b) {
        if (a.createdAt.isAfter(b.createdAt)) return -1;
        if (a.createdAt.isBefore(b.createdAt)) return 1;
        return b.id.compareTo(a.id);
      });

    return sorted
        .map((area) => _AreaTemplateOption(
              areaId: area.id,
              label:
                  '${area.name}${area.layerId != null ? " · ${layerNameById[area.layerId] ?? "未知楼层"}" : ""}',
            ))
        .toList(growable: false);
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

  Future<MapArea?> _findLatestAreaForTag(int tagId) async {
    final isar = ref.read(isarProvider);
    final areas = await isar.mapAreas
        .filter()
        .mapIdEqualTo(widget.mapId)
        .tagIdEqualTo(tagId)
        .findAll();
    if (areas.isEmpty) return null;
    areas.sort((a, b) {
      if (a.createdAt.isAfter(b.createdAt)) return -1;
      if (a.createdAt.isBefore(b.createdAt)) return 1;
      return b.id.compareTo(a.id);
    });
    return areas.first;
  }

  Future<void> _openAreaDrawForTag(Tag tag, {MapArea? area}) async {
    final isar = ref.read(isarProvider);
    final gameMap = await isar.gameMaps.get(widget.mapId);
    if (gameMap == null) return;

    await gameMap.layers.load();
    final layers = gameMap.layers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (layers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('当前地图没有楼层，无法编辑区域'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    MapLayer? layer;
    if (area != null && area.layerId != null) {
      final matched = layers.where((l) => l.id == area.layerId);
      if (matched.isNotEmpty) layer = matched.first;
    }
    layer ??= layers.length == 1 ? layers.first : await _selectLayer(layers);
    if (layer == null || !mounted) return;
    final selectedLayer = layer;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AreaDrawScreen(
          gameMap: gameMap,
          layer: selectedLayer,
          area: area,
          existingTagId: area == null ? tag.id : null,
          initialName: tag.name,
          initialColor: tag.colorValue,
          lockName: true,
        ),
      ),
    );
  }

  Future<void> _handleAreaTagPostSetup(
      Tag tag, Map<String, dynamic> dialogResult) async {
    if (tag.dimension != TagDimension.area) return;

    final setupMode = dialogResult['areaSetupMode'] as String? ?? 'none';
    if (setupMode == 'none') return;
    final continueEditAfterReuse =
        dialogResult['continueEditAfterReuse'] as bool? ?? false;

    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    final latestArea = await _findLatestAreaForTag(tag.id);

    if (setupMode == 'reuse') {
      final sourceAreaId = dialogResult['sourceAreaId'] as int?;
      if (sourceAreaId == null) return;
      final sourceArea = await isar.mapAreas.get(sourceAreaId);
      if (sourceArea == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('所选区域模板不存在'),
          backgroundColor: Colors.red,
        ));
        return;
      }

      MapArea targetArea;
      if (latestArea != null) {
        await areaService.updateArea(
          area: latestArea,
          name: tag.name,
          colorValue: tag.colorValue,
          strokes: sourceArea.strokes,
          layerId: sourceArea.layerId,
        );
        targetArea = latestArea;
      } else {
        targetArea = await areaService.createArea(
          name: tag.name,
          colorValue: tag.colorValue,
          strokes: sourceArea.strokes,
          mapId: widget.mapId,
          layerId: sourceArea.layerId,
          existingTagId: tag.id,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已复用区域数据'),
        duration: Duration(seconds: 1),
      ));
      if (continueEditAfterReuse) {
        await _openAreaDrawForTag(tag, area: targetArea);
      }
      return;
    }

    if (setupMode == 'edit') {
      await _openAreaDrawForTag(tag, area: latestArea);
    }
  }

  Future<void> _editTag(Tag tag) async {
    // 允许编辑系统标签，但提示可能会影响默认逻辑
    final templateOptions = await _loadAreaTemplateOptions();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateTagDialog(
          initialName: tag.name,
          initialColor: tag.colorValue,
          initialDimension: tag.dimension,
          areaTemplateOptions: templateOptions),
    );
    if (result != null) {
      if (result['action'] == 'delete') {
        await _deleteTag(tag);
        return;
      }
      if (result['action'] == 'save') {
        tag.name = result['name'];
        tag.colorValue = result['color'];
        tag.dimension = result['dimension'];
        await _tagService.updateTag(tag);
        await _handleAreaTagPostSetup(tag, result);
        await _loadTags();
      }
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final isar = ref.read(isarProvider);
    final relatedAreaCount =
        await isar.mapAreas.filter().tagIdEqualTo(tag.id).count();
    bool deleteRelatedAreas = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('删除标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '确定要删除标签 "${tag.name}" 吗？${tag.isSystem ? "\n(警告：这是一个系统预设标签)" : ""}\n关联的道具标签也将被移除。'),
              if (relatedAreaCount > 0) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: deleteRelatedAreas,
                  onChanged: (value) =>
                      setDialogState(() => deleteRelatedAreas = value ?? false),
                  title: Text('同时删除区域数据（$relatedAreaCount 条）'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                      'confirm': true,
                      'deleteRelatedAreas': deleteRelatedAreas,
                    }),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 248, 121, 121)),
                child: const Text('删除')),
          ],
        ),
      ),
    );
    if (result?['confirm'] == true) {
      await _tagService.deleteTag(
        tag.id,
        deleteRelatedAreas: result?['deleteRelatedAreas'] == true,
      );
      await _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.mapName} - 标签管理'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: _createTag,
              tooltip: '新建标签')
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? const Center(
                  child: Text('暂无标签', style: TextStyle(color: Colors.grey)))
              : _buildTagList(),
    );
  }

  Widget _buildTagList() {
    final grouped = <int, List<Tag>>{};
    for (final tag in _tags) {
      grouped.putIfAbsent(tag.dimension, () => []).add(tag);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: grouped.entries
          .where((e) => e.key != TagDimension.role)
          .map((e) => _buildGroup(e.key, e.value))
          .toList(),
    );
  }

  Widget _buildGroup(int dimension, List<Tag> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(TagDimension.getName(dimension),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(width: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${tags.length}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _renameGroup(dimension),
                child: const Icon(Icons.edit, size: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) => _buildTagItem(tag)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _renameGroup(int dimension) async {
    final controller =
        TextEditingController(text: TagDimension.getName(dimension));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: '分组名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      TagDimension.setName(dimension, result);
      setState(() {});
    }
  }

  Widget _buildTagItem(Tag tag) {
    final color = Color(tag.colorValue);
    return GestureDetector(
      onTap: () => _editTag(tag),
      onLongPress: () => _deleteTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(tag.name, style: TextStyle(color: color)),
            if (tag.isSystem) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified,
                  size: 12, color: color.withValues(alpha: 0.6))
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateTagDialog extends StatefulWidget {
  final String? initialName;
  final int? initialColor;
  final int? initialDimension;
  final List<_AreaTemplateOption> areaTemplateOptions;

  const _CreateTagDialog(
      {this.initialName,
      this.initialColor,
      this.initialDimension,
      this.areaTemplateOptions = const []});

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  late TextEditingController _nameController;
  late int _selectedColor;
  late int _selectedDimension;
  String _areaSetupMode = 'none';
  int? _sourceAreaId;
  bool _continueEditAfterReuse = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedColor = widget.initialColor ?? presetColors.first;
    _selectedDimension = widget.initialDimension ?? TagDimension.custom;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialName != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑标签' : '新建标签'),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: '标签名称', border: OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedDimension,
                decoration: const InputDecoration(
                    labelText: '标签分组', border: OutlineInputBorder()),
                items: [
                  TagDimension.phase,
                  TagDimension.spawn,
                  TagDimension.purpose,
                  TagDimension.area,
                  TagDimension.custom,
                ]
                    .map((dim) => DropdownMenuItem(
                        value: dim, child: Text(TagDimension.getName(dim))))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedDimension = val;
                    if (_selectedDimension != TagDimension.area) {
                      _areaSetupMode = 'none';
                      _sourceAreaId = null;
                    }
                  });
                },
              ),
              if (_selectedDimension == TagDimension.area) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _areaSetupMode,
                  decoration: const InputDecoration(
                      labelText: '区域数据快捷操作', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('仅创建标签（稍后配置）')),
                    DropdownMenuItem(value: 'edit', child: Text('立即绘制区域')),
                    DropdownMenuItem(value: 'reuse', child: Text('复用已有区域数据')),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _areaSetupMode = val;
                      if (val != 'reuse') {
                        _sourceAreaId = null;
                        _continueEditAfterReuse = false;
                      }
                    });
                  },
                ),
                if (_areaSetupMode == 'reuse') ...[
                  const SizedBox(height: 12),
                  if (widget.areaTemplateOptions.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4)),
                        color: Colors.orange.withValues(alpha: 0.12),
                      ),
                      child: const Text(
                        '当前地图还没有可复用的区域数据，请先创建区域或改为“创建后立即绘制区域”。',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _sourceAreaId,
                      decoration: const InputDecoration(
                          labelText: '选择已有区域数据', border: OutlineInputBorder()),
                      items: widget.areaTemplateOptions
                          .map((e) => DropdownMenuItem<int>(
                                value: e.areaId,
                                child: Text(
                                  e.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _sourceAreaId = val),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title:
                        const Text('复用后立即继续编辑', style: TextStyle(fontSize: 13)),
                    value: _continueEditAfterReuse,
                    onChanged: (value) =>
                        setState(() => _continueEditAfterReuse = value),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              const Text('标签颜色',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              TagColorPicker(
                  initialColor: _selectedColor,
                  onColorSelected: (c) => _selectedColor = c,
                  showPreview: false),
            ],
          ),
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () => Navigator.pop(context, {'action': 'delete'}),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('请输入标签名称')));
              return;
            }
            if (_selectedDimension == TagDimension.area &&
                _areaSetupMode == 'reuse' &&
                _sourceAreaId == null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('请选择要复用的区域数据')));
              return;
            }
            Navigator.pop(context, {
              'action': 'save',
              'name': name,
              'color': _selectedColor,
              'dimension': _selectedDimension,
              'areaSetupMode': _areaSetupMode,
              'sourceAreaId': _sourceAreaId,
              'continueEditAfterReuse': _continueEditAfterReuse,
            });
          },
          child: Text(isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

class _AreaTemplateOption {
  final int areaId;
  final String label;

  const _AreaTemplateOption({
    required this.areaId,
    required this.label,
  });
}
