import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../providers.dart';
import 'export_select_screen.dart';

class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key});

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  // 缓存数据，避免在 build 中使用同步查询
  List<GameMap> _maps = [];
  List<Grenade> _grenades = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // 加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final isar = ref.read(isarProvider);
    setState(() {
      _maps = isar.gameMaps.where().findAllSync();
      _grenades = isar.grenades.where().findAllSync();
      _isInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 如果还未初始化完成，显示加载指示器
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text("分享")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 不再在 build 中使用 findAllSync()，使用缓存的数据
    final body = TabBarView(
      children: [
        _buildSingleGrenadeTab(context),
        _buildMapTab(context),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("分享"),
          bottom: const TabBar(
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: "选择道具"),
              Tab(text: "选择地图"),
            ],
          ),
        ),
        body: body,
      ),
    );
  }

  Widget _buildSingleGrenadeTab(BuildContext context) {
    if (_grenades.isEmpty) {
      return const Center(
        child: Text("暂无道具数据", style: TextStyle(color: Colors.grey)),
      );
    }

    // 按地图分组统计
    final mapStats = <String, int>{};
    for (final g in _grenades) {
      g.layer.loadSync();
      g.layer.value?.map.loadSync();
      final mapName = g.layer.value?.map.value?.name ?? "未知";
      mapStats[mapName] = (mapStats[mapName] ?? 0) + 1;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.checklist, size: 80, color: Colors.blueAccent),
          const SizedBox(height: 20),
          Text("数据库中共有 ${_grenades.length} 个道具", style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text("分布在 ${mapStats.length} 张地图中", style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ExportSelectScreen(mode: 0),
                ),
              );
            },
            icon: const Icon(Icons.check_box),
            label: const Text("选择要分享的道具", style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "可以按地图筛选，选择具体要分享的道具",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTab(BuildContext context) {
    // 统计有道具的地图数量
    int mapsWithDataCount = 0;
    for (final map in _maps) {
      map.layers.loadSync();
      for (final layer in map.layers) {
        layer.grenades.loadSync();
        if (layer.grenades.isNotEmpty) {
          mapsWithDataCount++;
          break;
        }
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map, size: 80, color: Colors.orange),
          const SizedBox(height: 20),
          Text("共有 $mapsWithDataCount 张地图包含道具", style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text("总计 ${_grenades.length} 个道具", style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ExportSelectScreen(mode: 1),
                ),
              );
            },
            icon: const Icon(Icons.check_box),
            label: const Text("选择要分享的地图", style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "选择地图后，将导出所选地图的全部道具",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
