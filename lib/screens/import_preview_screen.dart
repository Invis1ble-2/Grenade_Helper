import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import 'grenade_preview_screen.dart';

/// 导入预览界面
class ImportPreviewScreen extends ConsumerStatefulWidget {
  final String filePath;

  const ImportPreviewScreen({super.key, required this.filePath});

  @override
  ConsumerState<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  PackagePreviewResult? _preview;
  bool _isLoading = true;
  String? _error;

  // 当前选中的地图（多地图模式下使用）
  String? _selectedMap;

  // 勾选的道具 uniqueId
  Set<String> _selectedIds = {};

  // 类型筛选
  int? _filterType;

  // 是否正在导入
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
      final preview = await dataService.previewPackage(widget.filePath);

      if (preview == null) {
        setState(() {
          _error = "无法解析道具包";
          _isLoading = false;
        });
        return;
      }

      // 如果是单地图，直接选中
      if (!preview.isMultiMap && preview.mapNames.isNotEmpty) {
        _selectedMap = preview.mapNames.first;
      }

      // 默认全选所有非跳过的道具
      final allIds = <String>{};
      for (var grenades in preview.grenadesByMap.values) {
        for (var g in grenades) {
          if (g.status != ImportStatus.skip) {
            allIds.add(g.uniqueId);
          }
        }
      }

      setState(() {
        _preview = preview;
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

  /// 获取当前显示的道具列表
  List<GrenadePreviewItem> _getCurrentGrenades() {
    if (_preview == null || _selectedMap == null) return [];
    var grenades = _preview!.grenadesByMap[_selectedMap] ?? [];

    // 应用类型筛选
    if (_filterType != null) {
      grenades = grenades.where((g) => g.type == _filterType).toList();
    }

    return grenades;
  }

  /// 切换全选状态
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
    if (_preview == null || _selectedIds.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final result = await dataService.importFromPreview(_preview!, _selectedIds);

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("导入失败: $e"), backgroundColor: Colors.red),
        );
        setState(() => _isImporting = false);
      }
    }
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

    // 多地图模式：显示地图列表
    if (_preview!.isMultiMap && _selectedMap == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("选择地图")),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _preview!.mapNames.length,
          itemBuilder: (context, index) {
            final mapName = _preview!.mapNames[index];
            final count = _preview!.grenadesByMap[mapName]?.length ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.map, color: Colors.orange, size: 40),
                title: Text(mapName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("$count 个道具"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _selectedMap = mapName),
              ),
            );
          },
        ),
      );
    }

    // 道具列表界面
    return _buildGrenadeListScreen();
  }

  Widget _buildGrenadeListScreen() {
    final grenades = _getCurrentGrenades();
    final currentIds = grenades.map((g) => g.uniqueId).toSet();
    final selectedInCurrent = currentIds.where((id) => _selectedIds.contains(id)).length;

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
          // 类型筛选栏
          _buildTypeFilter(),
          // 全选栏
          _buildSelectAllBar(selectedInCurrent, grenades.length),
          // 道具列表
          Expanded(
            child: grenades.isEmpty
                ? const Center(child: Text("无匹配的道具", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: grenades.length,
                    itemBuilder: (context, index) => _buildGrenadeItem(grenades[index]),
                  ),
          ),
          // 底部导入按钮
          _buildImportButton(),
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
      (GrenadeType.he, "手雷", Icons.sports_handball),
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
                    Icon(t.$3, size: 16, color: isSelected ? Colors.white : Colors.grey),
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
            ? Text("by: ${grenade.author}", style: TextStyle(fontSize: 12, color: Colors.grey[600]))
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
          child: const Text("新增", style: TextStyle(fontSize: 10, color: Colors.green)),
        );
      case ImportStatus.update:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text("更新", style: TextStyle(fontSize: 10, color: Colors.orange)),
        );
      case ImportStatus.skip:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text("跳过", style: TextStyle(fontSize: 10, color: Colors.grey)),
        );
    }
  }

  Widget _buildImportButton() {
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
          onPressed: _selectedIds.isEmpty || _isImporting ? null : _doImport,
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
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  "确认导入 (${_selectedIds.length} 个道具)",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}
