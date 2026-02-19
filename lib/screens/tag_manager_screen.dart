import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';
import '../widgets/color_picker_widget.dart';
import '../providers.dart';

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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateTagDialog(),
    );
    if (result != null && result['action'] == 'save') {
      await _tagService.createTag(widget.mapId, result['name'], result['color'],
          dimension: result['dimension']);
      await _loadTags();
    }
  }

  Future<void> _editTag(Tag tag) async {
    // 允许编辑系统标签，但提示可能会影响默认逻辑
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CreateTagDialog(
          initialName: tag.name,
          initialColor: tag.colorValue,
          initialDimension: tag.dimension),
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
        await _loadTags();
      }
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text(
            '确定要删除标签 "${tag.name}" 吗？${tag.isSystem ? "\n(警告：这是一个系统预设标签)" : ""}\n关联的道具标签也将被移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 248, 121, 121)),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await _tagService.deleteTag(tag.id);
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
  const _CreateTagDialog(
      {this.initialName, this.initialColor, this.initialDimension});

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  late TextEditingController _nameController;
  late int _selectedColor;
  late int _selectedDimension;

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
                if (val != null) setState(() => _selectedDimension = val);
              },
            ),
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
            Navigator.pop(context, {
              'action': 'save',
              'name': name,
              'color': _selectedColor,
              'dimension': _selectedDimension
            });
          },
          child: Text(isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}
