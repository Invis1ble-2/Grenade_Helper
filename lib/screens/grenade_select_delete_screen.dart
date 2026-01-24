import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import 'grenade_detail_screen.dart';

/// 道具批量选择删除页面
class GrenadeSelectDeleteScreen extends ConsumerStatefulWidget {
  const GrenadeSelectDeleteScreen({super.key});

  @override
  ConsumerState<GrenadeSelectDeleteScreen> createState() => _GrenadeSelectDeleteScreenState();
}

class _GrenadeSelectDeleteScreenState extends ConsumerState<GrenadeSelectDeleteScreen> {
  GameMap? _selectedMap;
  List<GameMap> _maps = [];
  List<Grenade> _grenades = [];
  final Set<int> _selectedIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMaps();
  }

  Future<void> _loadMaps() async {
    final isar = ref.read(isarProvider);
    final maps = await isar.gameMaps.where().findAll();
    if (mounted) setState(() => _maps = maps);
  }

  Future<void> _loadGrenades() async {
    if (_selectedMap == null) return;
    setState(() => _isLoading = true);

    await _selectedMap!.layers.load();
    final grenades = <Grenade>[];
    for (final layer in _selectedMap!.layers) {
      await layer.grenades.load();
      grenades.addAll(layer.grenades);
    }
    grenades.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (mounted) {
      setState(() {
        _grenades = grenades;
        _selectedIds.clear();
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _grenades.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_grenades.map((g) => g.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个道具吗？\n\n此操作不可撤销！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在删除...'),
          ],
        ),
      ),
    );

    try {
      final isar = ref.read(isarProvider);
      int deletedCount = 0;
      
      await isar.writeTxn(() async {
        for (final id in _selectedIds) {
          final grenade = await isar.grenades.get(id);
          if (grenade == null) continue;
          
          await grenade.steps.load();
          for (final step in grenade.steps) {
            await step.medias.load();
            for (final media in step.medias) {
              await DataService.deleteMediaFile(media.localPath);
              await isar.stepMedias.delete(media.id);
            }
            await isar.grenadeSteps.delete(step.id);
          }
          await isar.grenades.delete(id);
          deletedCount++;
        }
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $deletedCount 个道具'), backgroundColor: Colors.green),
        );
        await _loadGrenades();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _previewGrenade(Grenade grenade) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GrenadeDetailScreen(grenadeId: grenade.id, isEditing: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择删除道具'),
        actions: [
          if (_grenades.isNotEmpty)
            TextButton.icon(
              onPressed: _selectAll,
              icon: Icon(
                _selectedIds.length == _grenades.length ? Icons.deselect : Icons.select_all,
                size: 20,
              ),
              label: Text(_selectedIds.length == _grenades.length ? '取消全选' : '全选'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 地图选择
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: DropdownButtonFormField<GameMap>(
              decoration: const InputDecoration(
                labelText: '选择地图',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              initialValue: _selectedMap,
              items: _maps.map((map) {
                return DropdownMenuItem(value: map, child: Text(map.name));
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedMap = value);
                _loadGrenades();
              },
            ),
          ),
          // 内容
          Expanded(child: _buildContent()),
        ],
      ),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? Container(
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
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete),
                  label: Text('删除选中 (${_selectedIds.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildContent() {
    if (_selectedMap == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('请先选择一个地图', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_grenades.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('该地图暂无道具', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _grenades.length,
      itemBuilder: (context, index) {
        final grenade = _grenades[index];
        final isSelected = _selectedIds.contains(grenade.id);
        return _buildGrenadeItem(grenade, isSelected);
      },
    );
  }

  Widget _buildGrenadeItem(Grenade grenade, bool isSelected) {
    final typeIcon = _getTypeIcon(grenade.type);
    grenade.layer.loadSync();
    final layerName = grenade.layer.value?.name ?? '';
    final hasImpact = grenade.impactXRatio != null && grenade.impactYRatio != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: isSelected 
          ? Colors.red.withValues(alpha: 0.15) 
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected 
            ? const BorderSide(color: Colors.red, width: 1.5) 
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _toggleSelection(grenade.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 选择框
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelection(grenade.id),
                activeColor: Colors.red,
              ),
              // 类型图标
              Text(typeIcon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            grenade.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasImpact)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.my_location, size: 10, color: Colors.green),
                                SizedBox(width: 2),
                                Text('爆点', style: TextStyle(fontSize: 10, color: Colors.green)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.layers, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          layerName,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        if (grenade.author != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.person, size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              grenade.author!,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 预览按钮
              IconButton(
                onPressed: () => _previewGrenade(grenade),
                icon: const Icon(Icons.visibility, color: Colors.orange),
                tooltip: '预览',
              ),
            ],
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
