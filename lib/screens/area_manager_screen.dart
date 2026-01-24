import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/map_area.dart';
import '../models.dart';
import '../providers.dart';
import '../services/area_service.dart';
import 'area_draw_screen.dart';

/// 区域管理界面
class AreaManagerScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  
  const AreaManagerScreen({super.key, required this.gameMap});
  
  @override
  ConsumerState<AreaManagerScreen> createState() => _AreaManagerScreenState();
}

class _AreaManagerScreenState extends ConsumerState<AreaManagerScreen> {
  List<MapArea> _areas = [];
  bool _isLoading = true;
  
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
    setState(() { _areas = areas; _isLoading = false; });
  }
  
  Future<void> _createArea() async {
    widget.gameMap.layers.loadSync();
    final layers = widget.gameMap.layers.toList();
    if (layers.isEmpty) return;
    
    // 选择楼层
    final layer = layers.length == 1 ? layers.first : await _selectLayer(layers);
    if (layer == null) return;
    
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AreaDrawScreen(gameMap: widget.gameMap, layer: layer)),
    );
    if (result == true) _loadAreas();
  }
  
  Future<MapLayer?> _selectLayer(List<MapLayer> layers) async {
    return showDialog<MapLayer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择楼层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: layers.map((l) => ListTile(
            title: Text(l.name),
            onTap: () => Navigator.pop(ctx, l),
          )).toList(),
        ),
      ),
    );
  }
  
  Future<void> _deleteArea(MapArea area) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除区域'),
        content: Text('确定删除区域 "${area.name}"？\n关联的标签也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;
    
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    await areaService.deleteArea(area);
    _loadAreas();
  }

  Future<void> _editArea(MapArea area) async {
    if (area.layerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该区域未关联楼层，无法编辑'), backgroundColor: Colors.red)
      );
      return;
    }

    final isar = ref.read(isarProvider);
    final layer = await isar.mapLayers.get(area.layerId!);
    
    if (layer == null) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('关联楼层不存在'), backgroundColor: Colors.red)
      );
      return;
    }

    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AreaDrawScreen(gameMap: widget.gameMap, layer: layer, area: area)),
    );
    if (result == true) _loadAreas();
  }
  
  Future<void> _autoTagAll() async {
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    final count = await areaService.autoTagAllGrenades(widget.gameMap.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已为 $count 个道具自动添加区域标签'), backgroundColor: Colors.green),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.gameMap.name} 区域管理'),
        actions: [
          if (_areas.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.auto_fix_high),
              tooltip: '自动为所有道具添加区域标签',
              onPressed: _autoTagAll,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createArea,
        icon: const Icon(Icons.add),
        label: const Text('新建区域'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _areas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text('暂无自定义区域', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('点击下方按钮创建区域', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _areas.length,
                  itemBuilder: (ctx, index) {
                    final area = _areas[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Color(area.colorValue).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Color(area.colorValue)),
                          ),
                          child: Icon(Icons.map, color: Color(area.colorValue)),
                        ),
                        title: Text(area.name),
                        subtitle: Text('创建于 ${area.createdAt.toString().substring(0, 16)}', style: const TextStyle(fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                  },
                ),
    );
  }
}
