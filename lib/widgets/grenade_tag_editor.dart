import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../models/grenade_tag.dart';
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

// 标签较多时先折叠展示，避免占用整个道具详情页。
const int _collapsedTagCount = 12;

int _tagDimensionRank(int dimension) {
  final index = _tagDimensionDisplayOrder.indexOf(dimension);
  return index >= 0 ? index : _tagDimensionDisplayOrder.length + dimension;
}

int? roleTagToTeamType(Tag tag) {
  if (tag.dimension != TagDimension.role) return null;
  switch (tag.name.trim().toUpperCase()) {
    case '通用':
      return TeamType.all;
    case 'CT方':
    case 'CT':
      return TeamType.ct;
    case 'T方':
    case 'T':
      return TeamType.t;
    default:
      return null;
  }
}

bool isRoleTeamTag(Tag tag) => roleTagToTeamType(tag) != null;

int _normalizeRoleTeam(int? team) {
  return (team == TeamType.ct || team == TeamType.t) ? team! : TeamType.all;
}

int _roleTagDisplayPriority(Tag tag) {
  return switch (roleTagToTeamType(tag)) {
    TeamType.all => 0,
    TeamType.ct => 1,
    TeamType.t => 2,
    _ => 3,
  };
}

Tag? _findRoleTagByTeam(List<Tag> roleTags, int team) {
  final normalizedTeam = _normalizeRoleTeam(team);
  for (final tag in roleTags) {
    if (roleTagToTeamType(tag) == normalizedTeam) return tag;
  }
  return null;
}

/// 统一解析道具展示的标签 ID，仅归一化阵营标签而不静默写库
Set<int> resolveDisplayedTagIds({
  required List<Tag> allTags,
  required Set<int> selectedIds,
  required int? grenadeTeam,
}) {
  final roleTags = allTags.where(isRoleTeamTag).toList();
  if (roleTags.isEmpty) return Set<int>.from(selectedIds);
  final roleById = {for (final tag in roleTags) tag.id: tag};
  final selectedRoleIds = selectedIds.where(roleById.containsKey).toSet();
  final expectedTeam = _normalizeRoleTeam(grenadeTeam);
  final singleRole =
      selectedRoleIds.length == 1 ? roleById[selectedRoleIds.first] : null;
  if (singleRole != null && roleTagToTeamType(singleRole) == expectedTeam) {
    return Set<int>.from(selectedIds);
  }
  final adjusted = Set<int>.from(selectedIds)..removeAll(roleById.keys);
  final targetRoleTag = _findRoleTagByTeam(roleTags, expectedTeam);
  if (targetRoleTag != null) {
    adjusted.add(targetRoleTag.id);
  }
  return adjusted;
}

/// 统一解析只读展示的道具标签列表，与编辑态保持一致
List<Tag> resolveDisplayedGrenadeTags({
  required List<Tag> allTags,
  required List<Tag> boundTags,
  required int? grenadeTeam,
}) {
  final roleTags = allTags.where(isRoleTeamTag).toList();
  if (roleTags.isEmpty) return sortTagsForDisplay(boundTags);
  final boundRoleTags = boundTags.where(isRoleTeamTag).toList();
  final expectedTeam = _normalizeRoleTeam(grenadeTeam);
  if (boundRoleTags.length == 1 &&
      roleTagToTeamType(boundRoleTags.first) == expectedTeam) {
    return sortTagsForDisplay(boundTags);
  }
  final adjusted = boundTags.where((t) => !isRoleTeamTag(t)).toList();
  final targetRoleTag = _findRoleTagByTeam(roleTags, expectedTeam);
  if (targetRoleTag != null) {
    adjusted.add(targetRoleTag);
  }
  return sortTagsForDisplay(adjusted);
}

List<Tag> sortTagsForDisplay(List<Tag> tags) {
  final sorted = List<Tag>.from(tags);
  sorted.sort((a, b) {
    final rankCompare = _tagDimensionRank(a.dimension)
        .compareTo(_tagDimensionRank(b.dimension));
    if (rankCompare != 0) return rankCompare;
    if (a.dimension == TagDimension.role) {
      final roleCompare =
          _roleTagDisplayPriority(a).compareTo(_roleTagDisplayPriority(b));
      if (roleCompare != 0) return roleCompare;
    }

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
  final ValueChanged<int>? onTeamChanged;

  const GrenadeTagEditor({
    super.key,
    required this.grenadeId,
    required this.mapId,
    required this.tagService,
    this.onTagsChanged,
    this.onTeamChanged,
  });

  @override
  State<GrenadeTagEditor> createState() => _GrenadeTagEditorState();
}

class _GrenadeTagEditorState extends State<GrenadeTagEditor> {
  List<Tag> _allTags = [];
  Set<int> _selectedTagIds = {};
  bool _isLoading = true;
  bool _showAllTags = false;
  Future<void>? _activeWrite;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant GrenadeTagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grenadeId != widget.grenadeId ||
        oldWidget.mapId != widget.mapId) {
      _activeWrite = null;
      _loadData();
    }
  }

  Future<void> _enqueueWrite(Future<void> Function() action) {
    final prev = _activeWrite;
    late final Future<void> current;
    current = (prev == null
            ? Future<void>.sync(action)
            : prev.catchError((_) {}).then((_) => action()))
        .whenComplete(() {
      if (identical(_activeWrite, current)) {
        _activeWrite = null;
      }
    });
    _activeWrite = current;
    return current;
  }

  Future<void> _loadData({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
    final allTags = await widget.tagService.getAllTags(widget.mapId);
    final selectedIds =
        await widget.tagService.getGrenadeTagIds(widget.grenadeId);
    final grenade = await widget.tagService.isar.grenades.get(widget.grenadeId);
    final resolvedSelection = resolveDisplayedTagIds(
      allTags: allTags,
      selectedIds: selectedIds,
      grenadeTeam: grenade?.team,
    );
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _allTags = allTags;
      _selectedTagIds = resolvedSelection;
      _isLoading = false;
    });
  }

  Future<void> _toggleTag(Tag tag) {
    final targetGrenadeId = widget.grenadeId;
    return _enqueueWrite(() async {
      if (!mounted || widget.grenadeId != targetGrenadeId) return;
      final clickedTeam = roleTagToTeamType(tag);
      if (clickedTeam != null) {
        await _toggleRoleTag(tag, clickedTeam, targetGrenadeId);
        return;
      }
      final wasSelected = _selectedTagIds.contains(tag.id);
      if (wasSelected) {
        await widget.tagService.removeTagFromGrenade(targetGrenadeId, tag.id);
      } else {
        await widget.tagService.addTagToGrenade(targetGrenadeId, tag.id);
      }
      if (!mounted || widget.grenadeId != targetGrenadeId) return;
      final newSelection = Set<int>.from(_selectedTagIds);
      if (wasSelected) {
        newSelection.remove(tag.id);
      } else {
        newSelection.add(tag.id);
      }
      setState(() => _selectedTagIds = newSelection);
      widget.onTagsChanged?.call();
    });
  }

  Future<void> _toggleRoleTag(
    Tag tag,
    int clickedTeam,
    int targetGrenadeId,
  ) async {
    final roleTags = _allTags.where(isRoleTeamTag).toList();
    final isCurrentlySelected = _selectedTagIds.contains(tag.id);

    final int targetTeam;
    final Tag? targetTag;
    if (!isCurrentlySelected) {
      targetTeam = clickedTeam;
      targetTag = tag;
    } else if (clickedTeam == TeamType.all) {
      targetTeam = TeamType.all;
      targetTag = tag;
    } else {
      targetTeam = TeamType.all;
      targetTag = _findRoleTagByTeam(roleTags, TeamType.all);
    }

    final roleTagIds = roleTags.map((t) => t.id).toSet();
    final isar = widget.tagService.isar;
    final now = DateTime.now();

    // 历史脏数据下点击「通用」也需校验库内实际关联，仅在库已一致时跳过写库
    if (isCurrentlySelected && clickedTeam == TeamType.all) {
      final currentLinks = isar.grenadeTags
          .filter()
          .grenadeIdEqualTo(targetGrenadeId)
          .findAllSync();
      final persistedRoleIds = currentLinks
          .map((link) => link.tagId)
          .where(roleTagIds.contains)
          .toList();
      final currentGrenade = isar.grenades.getSync(targetGrenadeId);
      final targetTagId = targetTag?.id;
      final linksAlreadyClean = targetTagId == null
          ? persistedRoleIds.isEmpty
          : (persistedRoleIds.length == 1 &&
              persistedRoleIds.first == targetTagId);
      if (linksAlreadyClean &&
          (currentGrenade == null || currentGrenade.team == targetTeam)) {
        return;
      }
    }

    var persistedChanged = false;
    await isar.writeTxn(() async {
      final existingLinks = await isar.grenadeTags
          .filter()
          .grenadeIdEqualTo(targetGrenadeId)
          .findAll();
      var hasTargetLink = false;
      final deleteIds = <int>[];
      for (final link in existingLinks) {
        if (!roleTagIds.contains(link.tagId)) continue;
        if (targetTag != null &&
            link.tagId == targetTag.id &&
            !hasTargetLink) {
          hasTargetLink = true;
        } else {
          deleteIds.add(link.id);
        }
      }
      if (deleteIds.isNotEmpty) {
        await isar.grenadeTags.deleteAll(deleteIds);
        persistedChanged = true;
      }
      if (targetTag != null && !hasTargetLink) {
        await isar.grenadeTags.put(
          GrenadeTag(grenadeId: targetGrenadeId, tagId: targetTag.id),
        );
        persistedChanged = true;
      }
      final grenade = await isar.grenades.get(targetGrenadeId);
      if (grenade != null && (persistedChanged || grenade.team != targetTeam)) {
        grenade.team = targetTeam;
        grenade.updatedAt = now;
        grenade.hasLocalEdits = true;
        await isar.grenades.put(grenade);
        persistedChanged = true;
      }
    });

    if (!mounted || widget.grenadeId != targetGrenadeId) return;
    final newSelection = Set<int>.from(_selectedTagIds)..removeAll(roleTagIds);
    if (targetTag != null) {
      newSelection.add(targetTag.id);
    }
    setState(() => _selectedTagIds = newSelection);
    if (persistedChanged) {
      widget.onTeamChanged?.call(targetTeam);
      widget.onTagsChanged?.call();
    }
  }

  Future<void> _createQuickTag() async {
    final targetGrenadeId = widget.grenadeId;
    final targetMapId = widget.mapId;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _QuickCreateTagDialog(),
    );
    if (result != null) {
      await _enqueueWrite(() async {
        final tag = await widget.tagService
            .createTag(targetMapId, result['name'], result['color']);
        await widget.tagService.addTagToGrenade(targetGrenadeId, tag.id);
        if (!mounted || widget.grenadeId != targetGrenadeId) return;
        await _loadData(showLoading: false);
        widget.onTagsChanged?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final sortedTags = sortTagsForDisplay(_allTags);
    final visibleTags = _showAllTags
        ? sortedTags
        : sortedTags.take(_collapsedTagCount).toList();

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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        visibleTags.map((tag) => _buildTagChip(tag)).toList(),
                  ),
                  if (sortedTags.length > _collapsedTagCount)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _showAllTags = !_showAllTags),
                        icon: Icon(
                          _showAllTags ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(_showAllTags
                            ? '收起'
                            : '显示更多（${sortedTags.length - visibleTags.length}）'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                ],
              ),
      ],
    );
  }

  Widget _buildTagChip(Tag tag) {
    final isSelected = _selectedTagIds.contains(tag.id);
    final color = Color(tag.colorValue);
    return GestureDetector(
      onTap: () => _toggleTag(tag),
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
class GrenadeTagDisplay extends StatefulWidget {
  final List<Tag> tags;
  final bool compact;

  const GrenadeTagDisplay(
      {super.key, required this.tags, this.compact = false});

  @override
  State<GrenadeTagDisplay> createState() => _GrenadeTagDisplayState();
}

class _GrenadeTagDisplayState extends State<GrenadeTagDisplay> {
  bool _showAllTags = false;

  @override
  Widget build(BuildContext context) {
    if (widget.tags.isEmpty) return const SizedBox.shrink();
    final sortedTags = sortTagsForDisplay(widget.tags);
    final visibleTags = _showAllTags
        ? sortedTags
        : sortedTags.take(_collapsedTagCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: visibleTags.map((tag) {
            final color = Color(tag.colorValue);
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 6 : 8,
                vertical: widget.compact ? 2 : 4,
              ),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(widget.compact ? 8 : 12),
                  border: Border.all(color: color.withValues(alpha: 0.3))),
              child: Text(tag.name,
                  style: TextStyle(
                      fontSize: widget.compact ? 10 : 12, color: color)),
            );
          }).toList(),
        ),
        if (sortedTags.length > _collapsedTagCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAllTags = !_showAllTags),
              icon: Icon(
                _showAllTags ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(_showAllTags
                  ? '收起'
                  : '显示更多（${sortedTags.length - visibleTags.length}）'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
      ],
    );
  }
}
