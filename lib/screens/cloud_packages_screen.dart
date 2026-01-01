import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/cloud_package.dart';
import '../services/cloud_package_service.dart';
import 'import_preview_screen.dart';

class CloudPackagesScreen extends ConsumerStatefulWidget {
  const CloudPackagesScreen({super.key});

  @override
  ConsumerState<CloudPackagesScreen> createState() =>
      _CloudPackagesScreenState();
}

class _CloudPackagesScreenState extends ConsumerState<CloudPackagesScreen> {
  List<CloudPackage>? _packages;
  bool _isLoading = true;
  String? _error;
  String _selectedMap = 'all'; // 'all' = 全部
  final Set<String> _downloadingIds = {};
  final Map<String, String?> _lastImportedDates = {};
  final Map<String, double> _downloadProgress = {}; // 下载进度 0.0 - 1.0
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 用于防止竞态条件：只有最新的请求才能更新 UI
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    // 递增请求 ID，使之前的请求失效
    final currentRequestId = ++_loadRequestId;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final index = await CloudPackageService.fetchIndex();

    // 检查此请求是否仍然是最新的请求
    // 如果用户已经切换到其他数据源，忽略此结果
    if (currentRequestId != _loadRequestId) {
      return;
    }

    if (index != null) {
      // 获取每个包的上次导入版本
      for (final pkg in index.packages) {
        _lastImportedDates[pkg.id] =
            await CloudPackageService.getLastImportedVersion(pkg.id);
      }

      // 再次检查请求是否仍然有效（在获取版本信息期间可能已切换）
      if (currentRequestId != _loadRequestId) {
        return;
      }

      setState(() {
        _packages = index.packages;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = '无法连接到云端仓库';
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndImport(CloudPackage pkg) async {
    setState(() {
      _downloadingIds.add(pkg.id);
      _downloadProgress[pkg.id] = 0.0;
    });

    try {
      // 下载文件（带进度）
      final filePath = await CloudPackageService.downloadPackage(
        pkg.url,
        onProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _downloadProgress[pkg.id] = received / total;
            });
          }
        },
      );
      if (filePath == null) {
        _showMessage('下载失败');
        return;
      }

      // 跳转到预览界面进行道具选择
      if (!mounted) return;
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => ImportPreviewScreen(filePath: filePath),
        ),
      );

      // 删除临时文件
      try {
        await File(filePath).delete();
      } catch (_) {}

      if (result != null) {
        // 标记已导入（保存版本号）
        await CloudPackageService.markPackageImported(pkg.id, pkg.version);
        _lastImportedDates[pkg.id] = pkg.version;
        _showMessage(result);
      }
    } catch (e) {
      _showMessage('导入失败: $e');
    } finally {
      setState(() {
        _downloadingIds.remove(pkg.id);
        _downloadProgress.remove(pkg.id);
      });
    }
  }

  void _cancelDownload(CloudPackage pkg) {
    CloudPackageService.cancelDownload(pkg.url);
    setState(() {
      _downloadingIds.remove(pkg.id);
      _downloadProgress.remove(pkg.id);
    });
    _showMessage('已取消下载');
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  List<CloudPackage> get _filteredPackages {
    if (_packages == null) return [];
    var result = CloudPackageService.filterByMap(_packages!, _selectedMap);
    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(query) ||
              p.description.toLowerCase().contains(query) ||
              p.author.toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  List<String> get _availableMaps {
    if (_packages == null) return [];
    return ['all', ...CloudPackageService.getAvailableMaps(_packages!)];
  }

  String _getMapDisplayName(String map) {
    if (map == 'all') return '全部地图';
    return map[0].toUpperCase() + map.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线道具库'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索道具包...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
        actions: [
          // 源切换按钮
          PopupMenuButton<bool>(
            icon: Icon(
              CloudPackageService.isUsingCDN
                  ? Icons.speed
                  : Icons.cloud_outlined,
            ),
            tooltip: '切换下载源',
            onSelected: (useCDN) {
              CloudPackageService.switchSource(useCDN);
              _loadPackages();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      color: !CloudPackageService.isUsingCDN
                          ? Colors.green
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    const Text('GitHub'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      color: CloudPackageService.isUsingCDN
                          ? Colors.green
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    const Text('CDN 加速 (国内推荐)'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadPackages,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildPackageList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadPackages,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageList() {
    final filtered = _filteredPackages;

    return Column(
      children: [
        // 地图筛选器
        if (_availableMaps.length > 1)
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _availableMaps.length,
              itemBuilder: (ctx, i) {
                final map = _availableMaps[i];
                final isSelected = _selectedMap == map;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FilterChip(
                    label: Text(_getMapDisplayName(map)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedMap = map),
                    selectedColor: Colors.orange.withValues(alpha: 0.3),
                    checkmarkColor: Colors.orange,
                  ),
                );
              },
            ),
          ),
        // 包列表
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('暂无道具包', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _buildPackageCard(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildPackageCard(CloudPackage pkg) {
    final isDownloading = _downloadingIds.contains(pkg.id);
    final lastImportedVersion = _lastImportedDates[pkg.id];
    // 使用版本号比较
    final isUpToDate = lastImportedVersion != null &&
        CloudPackageService.compareVersion(lastImportedVersion, pkg.version) >=
            0;
    final hasUpdate = lastImportedVersion != null && !isUpToDate;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 地图图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: pkg.map != null
                  ? Padding(
                      padding: const EdgeInsets.all(6),
                      child: SvgPicture.asset(
                        'assets/icons/${pkg.map}_icon.svg',
                        width: 36,
                        height: 36,
                      ),
                    )
                  : const Icon(Icons.public, color: Colors.orange),
            ),
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
                          pkg.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (hasUpdate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '有更新',
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pkg.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildTag(Icons.person, pkg.author),
                      const SizedBox(width: 8),
                      _buildTag(Icons.tag, 'v${pkg.version}'),
                      const SizedBox(width: 8),
                      _buildTag(Icons.update, pkg.updated),
                    ],
                  ),
                ],
              ),
            ),
            // 下载/重新下载按钮
            if (isDownloading)
              GestureDetector(
                onTap: () => _cancelDownload(pkg),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _downloadProgress[pkg.id] ?? 0,
                        strokeWidth: 3,
                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      ),
                      const Icon(Icons.close, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              )
            else ...[
              // 已下载时显示重新下载按钮
              if (lastImportedVersion != null)
                IconButton(
                  onPressed: () => _downloadAndImport(pkg),
                  icon: const Icon(Icons.refresh, color: Colors.grey),
                  tooltip: '重新下载',
                  iconSize: 20,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              // 主按钮：下载或已是最新
              IconButton(
                onPressed: isUpToDate ? null : () => _downloadAndImport(pkg),
                icon: Icon(
                  isUpToDate ? Icons.check_circle : Icons.download,
                  color: isUpToDate ? Colors.green : Colors.orange,
                ),
                tooltip: isUpToDate ? '已是最新' : '下载',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 2),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
