import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import 'grenade_detail_screen.dart';

/// 导入历史详情页面 - 显示某次导入的所有道具
class ImportHistoryDetailScreen extends ConsumerStatefulWidget {
  final int historyId;

  const ImportHistoryDetailScreen({super.key, required this.historyId});

  @override
  ConsumerState<ImportHistoryDetailScreen> createState() =>
      _ImportHistoryDetailScreenState();
}

class _ImportHistoryDetailScreenState
    extends ConsumerState<ImportHistoryDetailScreen> {
  ImportHistory? _history;
  List<Grenade> _grenades = [];
  List<GrenadePreviewItem> _fallbackGrenades = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isar = ref.read(isarProvider);
    final history = await isar.importHistorys.get(widget.historyId);

    if (history != null) {
      await history.grenades.load();
      final linkedGrenades = history.grenades.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final fallbackGrenades = linkedGrenades.isEmpty
          ? await _loadGrenadesFromOriginalPackage(history.fileName)
          : const <GrenadePreviewItem>[];
      setState(() {
        _history = history;
        _grenades = linkedGrenades;
        _fallbackGrenades = fallbackGrenades;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<List<GrenadePreviewItem>> _loadGrenadesFromOriginalPackage(
      String fileName) async {
    final packageFile = await _locateOriginalPackage(fileName);
    if (packageFile == null) return const [];

    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final preview = await dataService.previewPackage(packageFile.path);
      if (preview == null) return const [];
      final items = preview.grenadesByMap.values
          .expand((e) => e)
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<File?> _locateOriginalPackage(String fileName) async {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) return null;

    final tempDir = await getTemporaryDirectory();
    final candidates = <String>[
      p.join(tempDir.path, trimmed),
      p.join(tempDir.path, 'lan_sync_inbox', trimmed),
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file;
      }
    }
    return null;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getGrenadeTypeIcon(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return '💨';
      case GrenadeType.flash:
        return '💡';
      case GrenadeType.molotov:
        return '🔥';
      case GrenadeType.he:
        return '💥';
      case GrenadeType.wallbang:
        return '🧱';
      default:
        return '❓';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("导入详情")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_history == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("导入详情")),
        body: const Center(child: Text("记录不存在")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_history!.fileName),
      ),
      body: Column(
        children: [
          // 导入信息卡片
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(_history!.importedAt),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatChip("新增", _history!.newCount, Colors.green),
                    _buildStatChip("更新", _history!.updatedCount, Colors.orange),
                    _buildStatChip("跳过", _history!.skippedCount, Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          if (_grenades.isEmpty && _fallbackGrenades.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '历史关联记录缺失，当前列表已从原始同步包回读。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          // 道具列表
          Expanded(
            child: _grenades.isEmpty && _fallbackGrenades.isEmpty
                ? const Center(child: Text("没有导入的道具记录"))
                : _grenades.isNotEmpty
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _grenades.length,
                        itemBuilder: (context, index) {
                          final grenade = _grenades[index];
                          grenade.layer.loadSync();
                          grenade.layer.value?.map.loadSync();
                          final mapName =
                              grenade.layer.value?.map.value?.name ?? "未知地图";

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Text(
                                _getGrenadeTypeIcon(grenade.type),
                                style: const TextStyle(fontSize: 24),
                              ),
                              title: Text(grenade.title),
                              subtitle: Text(mapName),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GrenadeDetailScreen(
                                      grenadeId: grenade.id,
                                      isEditing: false,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _fallbackGrenades.length,
                        itemBuilder: (context, index) {
                          final grenade = _fallbackGrenades[index];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Text(
                                _getGrenadeTypeIcon(grenade.type),
                                style: const TextStyle(fontSize: 24),
                              ),
                              title: Text(grenade.title),
                              subtitle: Text(
                                  '${grenade.mapName} / ${grenade.layerName}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openFallbackGrenadeDetail(grenade),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFallbackGrenadeDetail(
      GrenadePreviewItem previewItem) async {
    final isar = ref.read(isarProvider);
    final uniqueId = previewItem.uniqueId.trim();
    if (uniqueId.isEmpty) return;
    final allGrenades = await isar.grenades.where().findAll();
    final grenade = allGrenades
        .where((item) => (item.uniqueId ?? '').trim() == uniqueId)
        .firstOrNull;
    if (!mounted || grenade == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GrenadeDetailScreen(
          grenadeId: grenade.id,
          isEditing: false,
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
