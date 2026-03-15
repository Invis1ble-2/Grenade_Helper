import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../models/tag.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/lan_sync/lan_sync_local_store.dart';
import 'grenade_preview_screen.dart';

/// 导入预览
class ImportPreviewScreen extends ConsumerStatefulWidget {
  final String filePath;
  final ImportPackageMode importMode;
  final bool requireTrustedPackage;

  const ImportPreviewScreen({
    super.key,
    required this.filePath,
    this.importMode = ImportPackageMode.normal,
    this.requireTrustedPackage = false,
  });

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ConflictDialogResult<T> {
  final T resolution;
  final bool applyToRemaining;

  const _ConflictDialogResult({
    required this.resolution,
    required this.applyToRemaining,
  });
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  PackagePreviewResult? _preview;
  Map<String, GrenadePreviewItem> _localTombstoneItems = const {};
  bool _isLoading = true;
  String? _error;

  // 选中地图
  String? _selectedMap;

  // 选中ID
  Set<String> _selectedIds = {};

  // 类型筛选
  int? _filterType;

  // 正在导入
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final preview = await dataService.previewPackage(
        widget.filePath,
        mode: widget.importMode,
        requireTrustedPackage: widget.requireTrustedPackage,
      );

      if (preview == null) {
        setState(() {
          _error =
              widget.requireTrustedPackage ? "无法解析道具包，或包未通过安全校验" : "无法解析道具包";
          _isLoading = false;
        });
        return;
      }

      // 单地图自动选
      if (!preview.isMultiMap && preview.mapNames.isNotEmpty) {
        _selectedMap = preview.mapNames.first;
      }

      // 默认全选
      final allIds = <String>{};
      for (var grenades in preview.grenadesByMap.values) {
        for (var g in grenades) {
          if (g.status != ImportStatus.skip) {
            allIds.add(g.uniqueId);
          }
        }
      }

      final localTombstoneItems =
          widget.importMode != ImportPackageMode.lanSync ||
                  !preview.canApplyTombstones ||
                  preview.grenadeTombstones.isEmpty
              ? const <String, GrenadePreviewItem>{}
              : await dataService.loadLocalGrenadePreviewItemsByUniqueIds(
                  preview.grenadeTombstones.map((e) => e.uniqueId),
                );

      setState(() {
        _preview = preview;
        _localTombstoneItems = localTombstoneItems;
        _selectedIds = allIds;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "加载失败: $e";
        _isLoading = false;
      });
    }
  }

  /// 获取列表
  List<GrenadePreviewItem> _getCurrentGrenades() {
    if (_preview == null || _selectedMap == null) return [];
    var grenades = _preview!.grenadesByMap[_selectedMap] ?? [];

    // 类型过滤
    if (_filterType != null) {
      grenades = grenades.where((g) => g.type == _filterType).toList();
    }

    return grenades;
  }

  List<PackageGrenadeTombstoneData> _getCurrentTombstones() {
    if (_preview == null ||
        widget.importMode != ImportPackageMode.lanSync ||
        !_preview!.canApplyTombstones) {
      return const [];
    }
    final selectedMap = _selectedMap;
    final tombstones = _preview!.grenadeTombstones.where((item) {
      if (selectedMap == null) return true;
      return item.mapName.trim() == selectedMap.trim();
    }).toList(growable: false)
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return tombstones;
  }

  List<PackageEntityTombstoneData> _getCurrentEntityTombstones() {
    if (_preview == null ||
        widget.importMode != ImportPackageMode.lanSync ||
        !_preview!.canApplyTombstones) {
      return const [];
    }
    final selectedMap = _selectedMap;
    final tombstones = _preview!.entityTombstones.where((item) {
      if (selectedMap == null) return true;
      return item.mapName.trim() == selectedMap.trim();
    }).toList(growable: false)
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return tombstones;
  }

  int _metadataChangeCount() {
    final preview = _preview;
    if (preview == null) return 0;
    return preview.tagsByUuid.length +
        preview.areas.length +
        preview.favoriteFolders.length +
        preview.impactGroups.length;
  }

  /// 切换全选
  void _toggleSelectAll() {
    final currentGrenades = _getCurrentGrenades();
    final currentIds = currentGrenades.map((g) => g.uniqueId).toSet();
    final allSelected = currentIds.every((id) => _selectedIds.contains(id));

    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(currentIds);
      } else {
        _selectedIds.addAll(currentIds);
      }
    });
  }

  /// 执行导入
  Future<void> _doImport() async {
    if (_preview == null) return;
    if (_selectedIds.isEmpty &&
        _metadataChangeCount() == 0 &&
        (widget.importMode != ImportPackageMode.lanSync ||
            (_preview!.grenadeTombstones.isEmpty &&
                _preview!.entityTombstones.isEmpty))) {
      return;
    }

    setState(() => _isImporting = true);

    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final conflictNotice = await dataService.collectImportConflictNotice(
        _preview!,
        _selectedIds,
        mode: widget.importMode,
      );
      if (conflictNotice.hasConflicts) {
        if (!mounted) return;
        final continueImport = await _showConflictNoticeDialog(conflictNotice);
        if (continueImport != true) {
          if (mounted) {
            setState(() => _isImporting = false);
          }
          return;
        }
      }
      final tagResolutions = <String, ImportTagConflictResolution>{};
      final areaResolutions = <String, ImportAreaConflictResolution>{};
      ImportTagConflictResolution? tagResolutionForRemaining;
      ImportAreaConflictResolution? areaResolutionForRemaining;

      final tagConflictBundle =
          await dataService.collectTagConflicts(_preview!, _selectedIds);
      final tagConflicts = tagConflictBundle.tagConflicts;
      for (var i = 0; i < tagConflicts.length; i++) {
        if (!mounted) return;
        final conflict = tagConflicts[i];
        final dialogResult = tagResolutionForRemaining != null
            ? _ConflictDialogResult<ImportTagConflictResolution>(
                resolution: tagResolutionForRemaining,
                applyToRemaining: true,
              )
            : await _showTagConflictDialog(
                conflict,
                index: i + 1,
                total: tagConflicts.length,
              );
        if (dialogResult == null) {
          if (mounted) {
            setState(() => _isImporting = false);
          }
          return;
        }
        tagResolutions[conflict.sharedTag.tagUuid] = dialogResult.resolution;
        if (dialogResult.applyToRemaining) {
          tagResolutionForRemaining = dialogResult.resolution;
        }
      }

      final areaConflicts = await dataService.collectAreaConflicts(
        _preview!,
        _selectedIds,
        tagResolutions: tagResolutions,
      );
      for (var i = 0; i < areaConflicts.length; i++) {
        if (!mounted) return;
        final conflict = areaConflicts[i];
        final dialogResult = areaResolutionForRemaining != null
            ? _ConflictDialogResult<ImportAreaConflictResolution>(
                resolution: areaResolutionForRemaining,
                applyToRemaining: true,
              )
            : await _showAreaConflictDialog(
                conflict,
                index: i + 1,
                total: areaConflicts.length,
              );
        if (dialogResult == null) {
          if (mounted) {
            setState(() => _isImporting = false);
          }
          return;
        }
        areaResolutions[conflict.tagUuid] = dialogResult.resolution;
        if (dialogResult.applyToRemaining) {
          areaResolutionForRemaining = dialogResult.resolution;
        }
      }

      final result = await dataService.importFromPreview(
        _preview!,
        _selectedIds,
        tagResolutions: tagResolutions,
        areaResolutions: areaResolutions,
        mode: widget.importMode,
      );

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("导入失败: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<bool?> _showConflictNoticeDialog(ImportConflictNotice notice) {
    final lines = <String>[];
    for (final item in notice.newerLocalGrenades.take(6)) {
      lines.add('本地较新，将跳过更新：${item.mapName} / ${item.title}');
    }
    for (final item in notice.newerLocalDeleteConflicts.take(6)) {
      lines.add('本地较新，将跳过删除：${item.mapName} / ${item.title}');
    }
    for (final item in notice.newerLocalFavoriteFolderDeletes.take(6)) {
      lines.add('本地较新，将跳过收藏夹删除：$item');
    }
    final hiddenCount = notice.newerLocalGrenades.length +
        notice.newerLocalDeleteConflicts.length +
        notice.newerLocalFavoriteFolderDeletes.length -
        lines.length;
    if (hiddenCount > 0) {
      lines.add('还有 $hiddenCount 条冲突未展开');
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('发现同步冲突'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下内容会在导入时被保留为本地版本，不会被对端覆盖或删除：'),
            const SizedBox(height: 8),
            ...lines.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
  }

  Future<_ConflictDialogResult<ImportTagConflictResolution>?>
      _showTagConflictDialog(
    TagConflictItem conflict, {
    required int index,
    required int total,
  }) async {
    final reason = conflict.type == TagConflictType.uuidMismatch
        ? '同 UUID 标签属性不一致'
        : '本地已存在同地图同维度同名标签（UUID 不同）';
    final shared = conflict.sharedTag;
    final local = conflict.localTag;
    var applyToRemaining = false;

    return showDialog<_ConflictDialogResult<ImportTagConflictResolution>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('标签冲突 $index/$total'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason),
              const SizedBox(height: 8),
              Text('地图：${shared.mapName}'),
              Text('维度：${TagDimension.getName(shared.dimension)}'),
              const SizedBox(height: 8),
              Text(
                  '本地：${local.name} | 颜色: 0x${local.colorValue.toRadixString(16).toUpperCase()}'),
              Text(
                  '分享：${shared.name} | 颜色: 0x${shared.colorValue.toRadixString(16).toUpperCase()}'),
              const SizedBox(height: 8),
              const Text('请选择保留哪一侧标签数据：'),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: applyToRemaining,
                onChanged: (value) {
                  setDialogState(() {
                    applyToRemaining = value ?? false;
                  });
                },
                title: const Text('接下来的冲突也一样操作'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消导入'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(
                ctx,
                _ConflictDialogResult<ImportTagConflictResolution>(
                  resolution: ImportTagConflictResolution.local,
                  applyToRemaining: applyToRemaining,
                ),
              ),
              child: const Text('用本地'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _ConflictDialogResult<ImportTagConflictResolution>(
                  resolution: ImportTagConflictResolution.shared,
                  applyToRemaining: applyToRemaining,
                ),
              ),
              child: const Text('用分享'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_ConflictDialogResult<ImportAreaConflictResolution>?>
      _showAreaConflictDialog(
    AreaConflictGroup conflict, {
    required int index,
    required int total,
  }) async {
    final layersText = conflict.layers.join('、');
    var applyToRemaining = false;
    return showDialog<_ConflictDialogResult<ImportAreaConflictResolution>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('区域冲突 $index/$total'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('标签：${conflict.tagName}'),
              Text('地图：${conflict.mapName}'),
              Text('冲突楼层：$layersText'),
              const SizedBox(height: 8),
              const Text('请选择该标签的区域导入策略：'),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: applyToRemaining,
                onChanged: (value) {
                  setDialogState(() {
                    applyToRemaining = value ?? false;
                  });
                },
                title: const Text('接下来的冲突也一样操作'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消导入'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(
                ctx,
                _ConflictDialogResult<ImportAreaConflictResolution>(
                  resolution: ImportAreaConflictResolution.keepLocal,
                  applyToRemaining: applyToRemaining,
                ),
              ),
              child: const Text('本地保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _ConflictDialogResult<ImportAreaConflictResolution>(
                  resolution: ImportAreaConflictResolution.overwriteShared,
                  applyToRemaining: applyToRemaining,
                ),
              ),
              child: const Text('分享覆盖'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("加载中...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("导入预览")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("返回"),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.importMode == ImportPackageMode.lanSync &&
        _preview!.canApplyTombstones &&
        _preview!.totalCount == 0 &&
        (_preview!.grenadeTombstones.isNotEmpty ||
            _preview!.entityTombstones.isNotEmpty)) {
      return _buildTombstoneOnlyScreen();
    }

    // 多地图列表
    if (_preview!.isMultiMap && _selectedMap == null) {
      return _buildMapSelectionScreen();
    }

    // 道具列表
    return _buildGrenadeListScreen();
  }

  Widget _buildTombstoneOnlyScreen() {
    final tombstones = _getCurrentTombstones();
    final entityTombstones = _getCurrentEntityTombstones();
    return Scaffold(
      appBar: AppBar(title: const Text("删除同步预览")),
      body: Column(
        children: [
          _buildLegacyPackageNotice(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ...tombstones.map(_buildTombstoneItem),
                ...entityTombstones.map(_buildEntityTombstoneItem),
              ],
            ),
          ),
          _buildImportButton(),
        ],
      ),
    );
  }

  Widget _buildMapSelectionScreen() {
    final isar = ref.read(isarProvider);
    final preview = _preview!;
    return Scaffold(
      appBar: AppBar(title: const Text("选择地图")),
      body: Column(
        children: [
          _buildLegacyPackageNotice(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: preview.mapNames.length,
              itemBuilder: (context, index) {
                final mapName = preview.mapNames[index];
                final count = preview.grenadesByMap[mapName]?.length ?? 0;
                final tombstoneCount = preview.grenadeTombstones
                    .where((item) => item.mapName.trim() == mapName.trim())
                    .length;
                final entityTombstoneCount = preview.entityTombstones
                    .where((item) => item.mapName.trim() == mapName.trim())
                    .length;
                final gameMap =
                    isar.gameMaps.filter().nameEqualTo(mapName).findFirstSync();

                final subtitleParts = <String>['$count 个道具'];
                if (tombstoneCount > 0) {
                  subtitleParts.add('删除 $tombstoneCount 条');
                }
                if (entityTombstoneCount > 0) {
                  subtitleParts.add('其他删除 $entityTombstoneCount 条');
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: gameMap != null
                        ? SvgPicture.asset(
                            gameMap.iconPath,
                            width: 40,
                            height: 40,
                          )
                        : const Icon(Icons.map, color: Colors.orange, size: 40),
                    title: Text(
                      mapName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(subtitleParts.join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _selectedMap = mapName),
                  ),
                );
              },
            ),
          ),
          _buildImportButton(),
        ],
      ),
    );
  }

  Widget _buildGrenadeListScreen() {
    final grenades = _getCurrentGrenades();
    final tombstones = _getCurrentTombstones();
    final entityTombstones = _getCurrentEntityTombstones();
    final currentIds = grenades.map((g) => g.uniqueId).toSet();
    final selectedInCurrent =
        currentIds.where((id) => _selectedIds.contains(id)).length;
    final hasVisibleItems = grenades.isNotEmpty ||
        _metadataChangeCount() > 0 ||
        tombstones.isNotEmpty ||
        entityTombstones.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMap ?? "道具列表"),
        leading: _preview!.isMultiMap
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedMap = null),
              )
            : null,
      ),
      body: Column(
        children: [
          _buildLegacyPackageNotice(),
          // 类型筛选
          if (grenades.isNotEmpty) _buildTypeFilter(),
          // 全选栏
          if (grenades.isNotEmpty)
            _buildSelectAllBar(selectedInCurrent, grenades.length),
          // 列表
          Expanded(
            child: !hasVisibleItems
                ? const Center(
                    child: Text("无匹配的道具", style: TextStyle(color: Colors.grey)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      if (grenades.isEmpty && _metadataChangeCount() > 0)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.sync_alt),
                            title: const Text('元数据变更'),
                            subtitle: Text(
                              '标签 ${_preview!.tagsByUuid.length} · 区域 ${_preview!.areas.length} · 收藏夹 ${_preview!.favoriteFolders.length} · 爆点分组 ${_preview!.impactGroups.length}',
                            ),
                          ),
                        ),
                      ...grenades.map(_buildGrenadeItem),
                      if (tombstones.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '删除记录',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...tombstones.map(_buildTombstoneItem),
                      ],
                      if (entityTombstones.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '其他删除记录',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...entityTombstones.map(_buildEntityTombstoneItem),
                      ],
                    ],
                  ),
          ),
          // 底部按钮
          _buildImportButton(),
        ],
      ),
    );
  }

  Widget _buildEntityTombstoneItem(PackageEntityTombstoneData item) {
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(item.deletedAt);
    final deletedAtText =
        '${deletedAt.year}-${deletedAt.month.toString().padLeft(2, '0')}-${deletedAt.day.toString().padLeft(2, '0')} '
        '${deletedAt.hour.toString().padLeft(2, '0')}:${deletedAt.minute.toString().padLeft(2, '0')}';
    final (icon, title, subtitle) = switch (item.entityType) {
      LanSyncEntityTombstoneType.tag => (
          Icons.sell_outlined,
          '标签：${(item.payload['tagName'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} · ${TagDimension.getName(item.payload['dimension'] as int? ?? TagDimension.custom)} · $deletedAtText',
        ),
      LanSyncEntityTombstoneType.area => (
          Icons.polyline_outlined,
          '区域：${(item.payload['tagName'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} / ${(item.payload['layerName'] as String? ?? 'Default').trim()} · $deletedAtText',
        ),
      LanSyncEntityTombstoneType.favoriteFolder => (
          Icons.folder_delete_outlined,
          '收藏夹：${(item.payload['name'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} · $deletedAtText',
        ),
      LanSyncEntityTombstoneType.impactGroup => (
          Icons.scatter_plot_outlined,
          '爆点分组：${(item.payload['name'] as String? ?? item.entityKey).trim()}',
          '${item.mapName} / ${(item.payload['layerName'] as String? ?? '-').trim()} · $deletedAtText',
        ),
      _ => (
          Icons.delete_outline,
          item.entityKey,
          '${item.mapName} · $deletedAtText',
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.redAccent),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _buildTombstoneItem(PackageGrenadeTombstoneData item) {
    final localGrenade = _localTombstoneItems[item.uniqueId];
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(item.deletedAt);
    final deletedAtText =
        '${deletedAt.year}-${deletedAt.month.toString().padLeft(2, '0')}-${deletedAt.day.toString().padLeft(2, '0')} '
        '${deletedAt.hour.toString().padLeft(2, '0')}:${deletedAt.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(
          localGrenade != null ? _getTypeIcon(localGrenade.type) : '🗑️',
          style: const TextStyle(fontSize: 18),
        ),
        title: Text(localGrenade?.title ?? item.uniqueId),
        subtitle: Text(
          localGrenade != null
              ? '${localGrenade.mapName} - ${localGrenade.layerName} · $deletedAtText'
              : '${item.mapName} · $deletedAtText',
        ),
        trailing: localGrenade == null
            ? null
            : IconButton(
                icon: const Icon(Icons.visibility, color: Colors.blueAccent),
                tooltip: '预览本地道具',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GrenadePreviewScreen(
                        grenade: localGrenade,
                        memoryImages: const {},
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildLegacyPackageNotice() {
    if (_preview == null || !_preview!.isLegacyPackage) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '这是旧版道具包，未包含新版完整性校验。建议仅在信任来源下导入。',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    const types = [
      (null, "全部", Icons.apps),
      (GrenadeType.smoke, "烟雾", Icons.cloud),
      (GrenadeType.flash, "闪光", Icons.flash_on),
      (GrenadeType.molotov, "燃烧", Icons.local_fire_department),
      (GrenadeType.he, "手雷", Icons.trip_origin),
      (GrenadeType.wallbang, "穿点", Icons.grid_4x4),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types.map((t) {
            final isSelected = _filterType == t.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.$3,
                        size: 16,
                        color: isSelected ? Colors.white : Colors.grey),
                    const SizedBox(width: 4),
                    Text(t.$2),
                  ],
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _filterType = t.$1),
                selectedColor: Colors.orange,
                checkmarkColor: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSelectAllBar(int selected, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Checkbox(
            value: total > 0 && selected == total,
            tristate: selected > 0 && selected < total,
            onChanged: (_) => _toggleSelectAll(),
            activeColor: Colors.orange,
          ),
          Text(
            "全选 ($selected/$total)",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            "已选 ${_selectedIds.length} 个",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildGrenadeItem(GrenadePreviewItem grenade) {
    final isSelected = _selectedIds.contains(grenade.uniqueId);
    final typeIcon = _getTypeIcon(grenade.type);
    final statusBadge = _getStatusBadge(grenade.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedIds.add(grenade.uniqueId);
              } else {
                _selectedIds.remove(grenade.uniqueId);
              }
            });
          },
          activeColor: Colors.orange,
        ),
        title: Row(
          children: [
            Text(typeIcon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                grenade.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            statusBadge,
          ],
        ),
        subtitle: grenade.author != null
            ? Text("by: ${grenade.author}",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.visibility, color: Colors.blueAccent),
          tooltip: "预览道具",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GrenadePreviewScreen(
                  grenade: grenade,
                  memoryImages: _preview!.memoryImages,
                  packageFilePath: _preview!.filePath,
                  packageFileHashes: _preview!.packageFileHashes,
                  packageFileSizes: _preview!.packageFileSizes,
                ),
              ),
            );
          },
        ),
        dense: true,
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(grenade.uniqueId);
            } else {
              _selectedIds.add(grenade.uniqueId);
            }
          });
        },
      ),
    );
  }

  String _getTypeIcon(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return "☁️";
      case GrenadeType.flash:
        return "⚡";
      case GrenadeType.molotov:
        return "🔥";
      case GrenadeType.he:
        return "💣";
      case GrenadeType.wallbang:
        return "🧱";
      default:
        return "❓";
    }
  }

  Widget _getStatusBadge(ImportStatus status) {
    switch (status) {
      case ImportStatus.newItem:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text("新增",
              style: TextStyle(fontSize: 10, color: Colors.green)),
        );
      case ImportStatus.update:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text("更新",
              style: TextStyle(fontSize: 10, color: Colors.orange)),
        );
      case ImportStatus.skip:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text("跳过",
              style: TextStyle(fontSize: 10, color: Colors.grey)),
        );
    }
  }

  Widget _buildImportButton() {
    final grenadeCount = _selectedIds.length;
    final metadataCount = _metadataChangeCount();
    final tombstoneCount = widget.importMode == ImportPackageMode.lanSync &&
            _preview!.canApplyTombstones
        ? (_preview?.grenadeTombstones.length ?? 0) +
            (_preview?.entityTombstones.length ?? 0)
        : 0;
    final canImport =
        grenadeCount > 0 || metadataCount > 0 || tombstoneCount > 0;
    final labelParts = <String>[
      if (grenadeCount > 0) '$grenadeCount 个道具',
      if (metadataCount > 0) '元数据 $metadataCount 项',
      if (tombstoneCount > 0) '删除 $tombstoneCount 条',
    ];
    final label =
        labelParts.isEmpty ? '确认导入' : '确认导入 (${labelParts.join(' + ')})';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: !canImport || _isImporting ? null : _doImport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            disabledBackgroundColor: Colors.grey,
          ),
          child: _isImporting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
