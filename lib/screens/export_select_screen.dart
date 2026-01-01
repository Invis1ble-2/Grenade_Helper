import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import 'grenade_detail_screen.dart';

/// 导出选择界面 - 选择要分享的道具
class ExportSelectScreen extends ConsumerStatefulWidget {
  /// 0=选择道具(从所有道具), 1=选择地图, 2=从指定地图选择道具
  final int mode;
  final GameMap? singleMap;

  const ExportSelectScreen({
    super.key,
    required this.mode,
    this.singleMap,
  });

  @override
  ConsumerState<ExportSelectScreen> createState() => _ExportSelectScreenState();
}

class _ExportSelectScreenState extends ConsumerState<ExportSelectScreen> {
  bool _isLoading = true;
  bool _isExporting = false;

  // 所有地图
  List<GameMap> _maps = [];

  // 按地图分组的道具
  Map<String, List<Grenade>> _grenadesByMap = {};

  // 选中的地图名称（多地图模式）
  Set<String> _selectedMapNames = {};

  // 选中的道具ID（单道具模式）
  Set<int> _selectedGrenadeIds = {};

  // 当前查看的地图（用于从地图进入道具列表）
  String? _currentMapName;

  // 类型筛选
  int? _filterType;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final isar = ref.read(isarProvider);
    final maps = isar.gameMaps.where().findAllSync();
    final grenadesByMap = <String, List<Grenade>>{};

    for (final map in maps) {
      map.layers.loadSync();
      final grenades = <Grenade>[];
      for (final layer in map.layers) {
        layer.grenades.loadSync();
        for (final g in layer.grenades) {
          g.layer.loadSync();
          g.layer.value?.map.loadSync();
          grenades.add(g);
        }
      }
      if (grenades.isNotEmpty) {
        grenadesByMap[map.name] = grenades;
      }
    }

    // 根据模式设置初始选择
    if (widget.mode == 1) {
      // 多地图选择模式：默认全选有道具的地图
      _selectedMapNames = grenadesByMap.keys.toSet();
    } else if (widget.mode == 2 && widget.singleMap != null) {
      // 单地图道具选择：默认全选该地图的道具
      _currentMapName = widget.singleMap!.name;
      final mapGrenades = grenadesByMap[_currentMapName] ?? [];
      _selectedGrenadeIds = mapGrenades.map((g) => g.id).toSet();
    } else {
      // 全道具选择模式：默认全选
      for (final grenades in grenadesByMap.values) {
        _selectedGrenadeIds.addAll(grenades.map((g) => g.id));
      }
    }

    setState(() {
      _maps = maps;
      _grenadesByMap = grenadesByMap;
      _isLoading = false;
    });
  }

  List<Grenade> _getCurrentGrenades() {
    if (_currentMapName == null) return [];
    var grenades = _grenadesByMap[_currentMapName] ?? [];

    if (_filterType != null) {
      grenades = grenades.where((g) => g.type == _filterType).toList();
    }

    return grenades;
  }

  void _toggleSelectAllGrenades() {
    final currentGrenades = _getCurrentGrenades();
    final currentIds = currentGrenades.map((g) => g.id).toSet();
    final allSelected = currentIds.every((id) => _selectedGrenadeIds.contains(id));

    setState(() {
      if (allSelected) {
        _selectedGrenadeIds.removeAll(currentIds);
      } else {
        _selectedGrenadeIds.addAll(currentIds);
      }
    });
  }

  void _toggleSelectAllMaps() {
    final allMaps = _grenadesByMap.keys.toSet();
    final allSelected = allMaps.every((name) => _selectedMapNames.contains(name));

    setState(() {
      if (allSelected) {
        _selectedMapNames.clear();
      } else {
        _selectedMapNames = allMaps;
      }
    });
  }

  Future<void> _doExport() async {
    setState(() => _isExporting = true);

    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);

      List<Grenade> grenadesToExport = [];

      if (widget.mode == 1) {
        // 多地图模式：导出选中地图的所有道具
        for (final mapName in _selectedMapNames) {
          grenadesToExport.addAll(_grenadesByMap[mapName] ?? []);
        }
      } else {
        // 道具选择模式
        for (final grenades in _grenadesByMap.values) {
          grenadesToExport.addAll(
            grenades.where((g) => _selectedGrenadeIds.contains(g.id)),
          );
        }
      }

      if (grenadesToExport.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("未选择任何道具"), backgroundColor: Colors.orange),
          );
          setState(() => _isExporting = false);
        }
        return;
      }

      // 使用自定义道具列表导出
      await dataService.exportSelectedGrenades(context, grenadesToExport);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("导出失败: $e"), backgroundColor: Colors.red),
        );
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("选择要分享的内容")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 地图选择模式
    if (widget.mode == 1) {
      return _buildMapSelectScreen();
    }

    // 道具选择模式 - 如果没有选择地图，显示地图列表
    if (widget.mode == 0 && _currentMapName == null) {
      return _buildMapListForGrenadeSelect();
    }

    // 道具列表
    return _buildGrenadeListScreen();
  }

  Widget _buildMapSelectScreen() {
    final mapsWithGrenades = _maps.where((m) => _grenadesByMap.containsKey(m.name)).toList();
    final allSelected = mapsWithGrenades.every((m) => _selectedMapNames.contains(m.name));
    final selectedCount = _selectedMapNames.length;

    return Scaffold(
      appBar: AppBar(title: const Text("选择要分享的地图")),
      body: Column(
        children: [
          // 全选栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Checkbox(
                  value: mapsWithGrenades.isNotEmpty && allSelected,
                  tristate: selectedCount > 0 && !allSelected,
                  onChanged: (_) => _toggleSelectAllMaps(),
                  activeColor: Colors.orange,
                ),
                Text(
                  "全选 ($selectedCount/${mapsWithGrenades.length})",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // 地图列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mapsWithGrenades.length,
              itemBuilder: (context, index) {
                final map = mapsWithGrenades[index];
                final count = _grenadesByMap[map.name]?.length ?? 0;
                final isSelected = _selectedMapNames.contains(map.name);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedMapNames.add(map.name);
                          } else {
                            _selectedMapNames.remove(map.name);
                          }
                        });
                      },
                      activeColor: Colors.orange,
                    ),
                    title: Row(
                      children: [
                        SvgPicture.asset(map.iconPath, width: 32, height: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(map.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text("$count 个道具"),
                    ),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedMapNames.remove(map.name);
                        } else {
                          _selectedMapNames.add(map.name);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
          // 导出按钮
          _buildExportButton(_selectedMapNames.isNotEmpty),
        ],
      ),
    );
  }

  Widget _buildMapListForGrenadeSelect() {
    final mapsWithGrenades = _maps.where((m) => _grenadesByMap.containsKey(m.name)).toList();
    
    // 计算总数和已选数
    int totalGrenades = 0;
    for (final grenades in _grenadesByMap.values) {
      totalGrenades += grenades.length;
    }
    final allSelected = totalGrenades > 0 && _selectedGrenadeIds.length == totalGrenades;

    return Scaffold(
      appBar: AppBar(title: const Text("选择地图")),
      body: Column(
        children: [
          // 全选所有地图栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  tristate: _selectedGrenadeIds.isNotEmpty && !allSelected,
                  onChanged: (_) {
                    setState(() {
                      if (allSelected) {
                        _selectedGrenadeIds.clear();
                      } else {
                        for (final grenades in _grenadesByMap.values) {
                          _selectedGrenadeIds.addAll(grenades.map((g) => g.id));
                        }
                      }
                    });
                  },
                  activeColor: Colors.orange,
                ),
                Text(
                  "全选所有地图 (${_selectedGrenadeIds.length}/$totalGrenades)",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // 地图列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mapsWithGrenades.length,
              itemBuilder: (context, index) {
                final map = mapsWithGrenades[index];
                final grenades = _grenadesByMap[map.name] ?? [];
                final selectedInMap = grenades.where((g) => _selectedGrenadeIds.contains(g.id)).length;
                final allInMapSelected = grenades.isNotEmpty && selectedInMap == grenades.length;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Checkbox(
                      value: allInMapSelected,
                      tristate: selectedInMap > 0 && !allInMapSelected,
                      onChanged: (val) {
                        setState(() {
                          if (allInMapSelected) {
                            _selectedGrenadeIds.removeAll(grenades.map((g) => g.id));
                          } else {
                            _selectedGrenadeIds.addAll(grenades.map((g) => g.id));
                          }
                        });
                      },
                      activeColor: Colors.orange,
                    ),
                    title: Row(
                      children: [
                        SvgPicture.asset(map.iconPath, width: 32, height: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(map.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text("已选 $selectedInMap / ${grenades.length} 个道具"),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _currentMapName = map.name),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildExportButton(_selectedGrenadeIds.isNotEmpty),
    );
  }

  Widget _buildGrenadeListScreen() {
    final grenades = _getCurrentGrenades();
    final currentIds = grenades.map((g) => g.id).toSet();
    final selectedInCurrent = currentIds.where((id) => _selectedGrenadeIds.contains(id)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentMapName ?? "选择道具"),
        leading: widget.mode == 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentMapName = null),
              )
            : null,
      ),
      body: Column(
        children: [
          // 类型筛选栏
          _buildTypeFilter(),
          // 全选栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Checkbox(
                  value: grenades.isNotEmpty && selectedInCurrent == grenades.length,
                  tristate: selectedInCurrent > 0 && selectedInCurrent < grenades.length,
                  onChanged: (_) => _toggleSelectAllGrenades(),
                  activeColor: Colors.orange,
                ),
                Text(
                  "全选 ($selectedInCurrent/${grenades.length})",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  "共选 ${_selectedGrenadeIds.length} 个",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
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
          // 导出按钮
          _buildExportButton(_selectedGrenadeIds.isNotEmpty),
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

  Widget _buildGrenadeItem(Grenade grenade) {
    final isSelected = _selectedGrenadeIds.contains(grenade.id);
    final typeIcon = _getTypeIcon(grenade.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedGrenadeIds.add(grenade.id);
              } else {
                _selectedGrenadeIds.remove(grenade.id);
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
                builder: (_) => GrenadeDetailScreen(grenadeId: grenade.id, isEditing: false),
              ),
            );
          },
        ),
        dense: true,
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedGrenadeIds.remove(grenade.id);
            } else {
              _selectedGrenadeIds.add(grenade.id);
            }
          });
        },
      ),
    );
  }

  Widget _buildExportButton(bool enabled) {
    int count;
    if (widget.mode == 1) {
      count = _selectedMapNames.fold(0, (sum, name) => sum + (_grenadesByMap[name]?.length ?? 0));
    } else {
      count = _selectedGrenadeIds.length;
    }

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
          onPressed: !enabled || _isExporting ? null : _doExport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            disabledBackgroundColor: Colors.grey,
          ),
          child: _isExporting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  "分享 ($count 个道具)",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
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
}
