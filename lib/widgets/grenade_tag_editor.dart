import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';
import '../widgets/color_picker_widget.dart';

const List<int> _tagDimensionDisplayOrder = <int>[
  TagDimension.role,
  TagDimension.phase,
  TagDimension.spawn,
  TagDimension.purpose,
  TagDimension.area,
  TagDimension.custom,
];

int _tagDimensionRank(int dimension) {
  final index = _tagDimensionDisplayOrder.indexOf(dimension);
  return index >= 0 ? index : _tagDimensionDisplayOrder.length + dimension;
}

List<Tag> _sortTagsForDisplay(List<Tag> tags) {
  final sorted = List<Tag>.from(tags);
  sorted.sort((a, b) {
    final rankCompare = _tagDimensionRank(a.dimension)
        .compareTo(_tagDimensionRank(b.dimension));
    if (rankCompare != 0) return rankCompare;

    final orderCompare = a.sortOrder.compareTo(b.sortOrder);
    if (orderCompare != 0) return orderCompare;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

/// 道具标签编辑器
class GrenadeTagEditor extends StatefulWidget {
  final int grenadeId;
  final int mapId;
  final TagService tagService;
  final VoidCallback? onTagsChanged;

  const GrenadeTagEditor({
    super.key,
    required this.grenadeId,
    required this.mapId,
    required this.tagService,
    this.onTagsChanged,
  });

  @override
  State<GrenadeTagEditor> createState() => _GrenadeTagEditorState();
}

class _GrenadeTagEditorState extends State<GrenadeTagEditor> {
  List<Tag> _allTags = [];
  Set<int> _selectedTagIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final allTags = await widget.tagService.getAllTags(widget.mapId);
    final selectedIds =
        await widget.tagService.getGrenadeTagIds(widget.grenadeId);
    setState(() {
      _allTags = allTags;
      _selectedTagIds = selectedIds;
      _isLoading = false;
    });
  }

  Future<void> _toggleTag(int tagId) async {
    final newSelection = Set<int>.from(_selectedTagIds);
    if (newSelection.contains(tagId)) {
      newSelection.remove(tagId);
      await widget.tagService.removeTagFromGrenade(widget.grenadeId, tagId);
    } else {
      newSelection.add(tagId);
      await widget.tagService.addTagToGrenade(widget.grenadeId, tagId);
    }
    setState(() => _selectedTagIds = newSelection);
    widget.onTagsChanged?.call();
  }

  Future<void> _createQuickTag() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _QuickCreateTagDialog(),
    );
    if (result != null) {
      final tag = await widget.tagService
          .createTag(widget.mapId, result['name'], result['color']);
      await widget.tagService.addTagToGrenade(widget.grenadeId, tag.id);
      await _loadData();
      widget.onTagsChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('标签',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_selectedTagIds.isNotEmpty)
              Text('${_selectedTagIds.length} 个已选',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).primaryColor)),
            IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _createQuickTag,
                tooltip: '快速创建标签'),
          ],
        ),
        const SizedBox(height: 8),
        _allTags.isEmpty
            ? const Text('暂无标签，点击右上角创建',
                style: TextStyle(color: Colors.grey, fontSize: 12))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sortTagsForDisplay(_allTags)
                    .map((tag) => _buildTagChip(tag))
                    .toList(),
              ),
      ],
    );
  }

  Widget _buildTagChip(Tag tag) {
    final isSelected = _selectedTagIds.contains(tag.id);
    final color = Color(tag.colorValue);
    return GestureDetector(
      onTap: () => _toggleTag(tag.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check, size: 12, color: Colors.white)),
            Text(tag.name,
                style: TextStyle(
                    fontSize: 12, color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    );
  }
}

class _QuickCreateTagDialog extends StatefulWidget {
  @override
  State<_QuickCreateTagDialog> createState() => _QuickCreateTagDialogState();
}

class _QuickCreateTagDialogState extends State<_QuickCreateTagDialog> {
  final _nameController = TextEditingController();
  int _selectedColor = presetColors.first;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('快速创建标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: '标签名称', border: OutlineInputBorder()),
              autofocus: true),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presetColors
                .map((c) => GestureDetector(
                      onTap: () => setState(() => _selectedColor = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _selectedColor == c
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2)),
                        child: _selectedColor == c
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {'name': name, 'color': _selectedColor});
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 显示道具标签的只读展示组件
class GrenadeTagDisplay extends StatelessWidget {
  final List<Tag> tags;
  final bool compact;

  const GrenadeTagDisplay(
      {super.key, required this.tags, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final sortedTags = _sortTagsForDisplay(tags);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: sortedTags.map((tag) {
        final color = Color(tag.colorValue);
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(compact ? 8 : 12),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Text(tag.name,
              style: TextStyle(fontSize: compact ? 10 : 12, color: color)),
        );
      }).toList(),
    );
  }
}
