import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/lan_sync/lan_sync_discovery_service.dart';
import '../services/lan_sync/lan_sync_local_store.dart';
import '../services/lan_sync/lan_sync_receive_controller.dart';
import '../services/lan_sync/lan_sync_transfer_client.dart';
import 'import_preview_screen.dart';

enum _LanSendScope { all, map, grenades }

enum _LanSyncMode { full, incremental }

class LanSyncScreen extends ConsumerStatefulWidget {
  const LanSyncScreen({super.key});

  @override
  ConsumerState<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends ConsumerState<LanSyncScreen> {
  late final LanSyncReceiveController _receiveController;
  late final LanSyncDiscoveryService _discoveryService;
  late final LanSyncLocalStore _localStore;
  late final TextEditingController _targetHostController;
  late final TextEditingController _targetPortController;
  bool _isLoadingLocal = true;
  bool _isScanningDevices = false;
  bool _isSendingAll = false;
  bool _isWaitingForApproval = false;
  double? _sendProgress;
  String _sendProgressLabel = '';
  _LanSyncMode _sendMode = _LanSyncMode.full;
  _LanSendScope _sendScope = _LanSendScope.all;
  GameMap? _selectedMapForSend;
  List<Grenade> _selectedGrenadesForSend = const [];
  List<LanDiscoveryDevice> _discoveredDevices = const [];
  final Set<String> _seenReceivedTaskIds = <String>{};
  final Set<String> _handledIncomingRequestDialogs = <String>{};
  final Set<String> _autoOpenedImportTaskIds = <String>{};
  bool _isAutoOpeningImportPreview = false;

  @override
  void initState() {
    super.initState();
    _receiveController = LanSyncReceiveController();
    _receiveController.setLocalDeviceName(_buildEphemeralDeviceName());
    _receiveController.addListener(_onReceiveControllerChanged);
    _discoveryService = LanSyncDiscoveryService();
    _localStore = LanSyncLocalStore();
    _targetHostController = TextEditingController();
    _targetPortController = TextEditingController(text: '39527');
    unawaited(_receiveController.refreshLocalIps());
    unawaited(_loadLocalState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scanDevices());
    });
  }

  @override
  void dispose() {
    _receiveController.removeListener(_onReceiveControllerChanged);
    _targetHostController.dispose();
    _targetPortController.dispose();
    _receiveController.dispose();
    super.dispose();
  }

  void _onReceiveControllerChanged() {
    for (final task in _receiveController.tasks) {
      if (_seenReceivedTaskIds.add(task.id)) {
        unawaited(_appendHistory(
          category: 'receive',
          title: '收到同步包',
          detail:
              '${task.fileName} · ${_formatBytes(task.sizeBytes)}${task.remoteAddress == null ? '' : ' · ${task.remoteAddress}'}',
          success: true,
        ));
      }
    }
    for (final req in _receiveController.incomingRequests) {
      if (req.status == LanIncomingTransferRequestStatus.pending &&
          _handledIncomingRequestDialogs.add(req.id)) {
        unawaited(_showIncomingTransferApprovalDialog(req.id));
      }
    }
    if (!mounted) return;
    setState(() {});
    _maybeAutoOpenImportPreview();
  }

  void _maybeAutoOpenImportPreview() {
    if (!mounted || _isAutoOpeningImportPreview) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    LanReceivedPackageTask? task;
    for (final item in _receiveController.tasks) {
      if (item.status != LanReceiveTaskStatus.pending) continue;
      if (_autoOpenedImportTaskIds.contains(item.id)) continue;
      task = item;
      break;
    }
    if (task == null) return;

    _autoOpenedImportTaskIds.add(task.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isAutoOpeningImportPreview) return;
      final currentRoute = ModalRoute.of(context);
      if (currentRoute != null && !currentRoute.isCurrent) return;

      _isAutoOpeningImportPreview = true;
      unawaited(() async {
        try {
          await _openImportPreview(task!);
        } finally {
          _isAutoOpeningImportPreview = false;
          if (mounted) {
            _maybeAutoOpenImportPreview();
          }
        }
      }());
    });
  }

  Future<void> _showIncomingTransferApprovalDialog(String requestId) async {
    if (!mounted) return;
    final req = _receiveController.incomingRequests
        .where((e) => e.id == requestId)
        .cast<LanIncomingTransferRequest?>()
        .firstWhere((e) => e != null, orElse: () => null);
    if (req == null || req.status != LanIncomingTransferRequestStatus.pending) {
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('收到传输请求'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件：${req.fileName}'),
            Text('大小：${_formatBytes(req.sizeBytes)}'),
            if (req.senderName.isNotEmpty) Text('发送方：${req.senderName}'),
            Text('模式：${req.syncMode == "delta" ? "增量" : "全量"}'),
            if (req.scopeSummary.isNotEmpty) Text('范围：${req.scopeSummary}'),
            if (req.scopeMapKeys.isNotEmpty)
              Text('地图：${req.scopeMapKeys.join("、")}'),
            if (req.remoteAddress != null) Text('来源IP：${req.remoteAddress}'),
            const SizedBox(height: 8),
            const Text('是否允许对方开始传输？'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('同意'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await _receiveController.approveIncomingRequest(requestId);
      await _appendHistory(
        category: 'system',
        title: '同意传输请求',
        detail: '${req.fileName} · ${_formatBytes(req.sizeBytes)}',
        success: true,
      );
    } else {
      await _receiveController.rejectIncomingRequest(requestId,
          message: '接收方拒绝');
      await _appendHistory(
        category: 'system',
        title: '拒绝传输请求',
        detail: req.fileName,
        success: true,
      );
    }
  }

  Future<void> _loadLocalState() async {
    final nodeId = await _localStore.loadOrCreateStableNodeId();
    _receiveController.setLocalNodeId(nodeId);
    if (!mounted) return;
    setState(() {
      _isLoadingLocal = false;
    });
  }

  Future<void> _appendHistory({
    required String category,
    required String title,
    required String detail,
    required bool success,
  }) async {
    final entry = LanSyncHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      category: category,
      title: title,
      detail: detail,
      success: success,
      createdAt: DateTime.now(),
    );
    await _localStore.appendHistory(entry);
  }

  Future<void> _scanDevices() async {
    await _scanDevicesBySubnet();
  }

  Future<void> _scanDevicesBySubnet() async {
    if (_isScanningDevices) return;
    setState(() => _isScanningDevices = true);
    try {
      if (_receiveController.localIps.isEmpty) {
        await _receiveController.refreshLocalIps();
      }
      final localIps = _receiveController.localIps;
      if (localIps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获取到本机局域网 IP，无法进行网段探测')),
        );
        return;
      }

      final results = (await _discoveryService.scan(
        localIps: localIps,
        port: 39527,
      ))
          .where((d) => !_isSelfDiscoveredDevice(
                host: d.host,
                deviceId: d.deviceId,
                localIps: localIps,
              ))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _discoveredDevices = results;
      });
      await _appendHistory(
        category: 'system',
        title: '网段探测完成',
        detail: '发现 ${results.length} 台设备（默认端口 39527）',
        success: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('网段探测完成：发现 ${results.length} 台设备')),
      );
    } catch (e) {
      await _appendHistory(
        category: 'system',
        title: '网段探测失败',
        detail: '$e',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('网段探测失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanningDevices = false);
      }
    }
  }

  bool _isSelfDiscoveredDevice({
    required String host,
    required String deviceId,
    required List<String> localIps,
  }) {
    final localId = _receiveController.localDeviceId.trim();
    if (localId.isNotEmpty && deviceId.trim() == localId) {
      return true;
    }
    final trimmedHost = host.trim();
    return trimmedHost.isNotEmpty && localIps.contains(trimmedHost);
  }

  String _buildEphemeralDeviceName() {
    const adjectives = <String>[
      '敏捷',
      '冷静',
      '清晨',
      '明亮',
      '安静',
      '迅捷',
      '稳健',
      '轻盈',
      '灵巧',
      '坚实',
    ];
    const nouns = <String>[
      '海豚',
      '狐狸',
      '猎鹰',
      '熊猫',
      '北极星',
      '山猫',
      '燕子',
      '鲸鱼',
      '松鼠',
      '猫头鹰',
    ];
    final rnd = math.Random();
    final suffix = 100 + rnd.nextInt(900);
    return '${adjectives[rnd.nextInt(adjectives.length)]}'
        '${nouns[rnd.nextInt(nouns.length)]}-$suffix';
  }

  int? get _parsedTargetPort => int.tryParse(_targetPortController.text.trim());

  Future<void> _sendToHostPort(String host, int port) async {
    _targetHostController.text = host;
    _targetPortController.text = port.toString();
    if (mounted) setState(() {});
    await _sendAllToTarget();
  }

  Future<void> _showManualSendDialog() async {
    final hostController =
        TextEditingController(text: _targetHostController.text);
    final portController = TextEditingController(
      text: _targetPortController.text.isEmpty
          ? '39527'
          : _targetPortController.text,
    );
    try {
      final result = await showDialog<(String, int)>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('手动输入IP地址和端口'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostController,
                decoration: const InputDecoration(labelText: 'IP / 主机'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '端口'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final host = hostController.text.trim();
                final port = int.tryParse(portController.text.trim());
                if (host.isEmpty || port == null || port <= 0 || port > 65535) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入有效的 IP 和端口')),
                  );
                  return;
                }
                Navigator.pop(ctx, (host, port));
              },
              child: const Text('连接并发送'),
            ),
          ],
        ),
      );
      if (result == null) return;
      await _sendToHostPort(result.$1, result.$2);
    } finally {
      hostController.dispose();
      portController.dispose();
    }
  }

  Future<void> _pickMapForSend() async {
    final isar = ref.read(isarProvider);
    final maps = isar.gameMaps.where().findAllSync();
    if (maps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有地图数据')));
      return;
    }
    final selected = await showDialog<GameMap>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择地图'),
        children: maps
            .map(
              (m) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, m),
                child: Text(m.name),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedMapForSend = selected;
      _sendScope = _LanSendScope.map;
    });
  }

  Future<void> _pickGrenadesForSend() async {
    final isar = ref.read(isarProvider);
    final allGrenades = isar.grenades.where().findAllSync();
    if (allGrenades.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有道具数据')));
      return;
    }

    final selectedIds = _selectedGrenadesForSend.map((e) => e.id).toSet();
    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('选择道具'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setLocalState(() {
                        selectedIds
                          ..clear()
                          ..addAll(allGrenades.map((e) => e.id));
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setLocalState(selectedIds.clear),
                      child: const Text('清空'),
                    ),
                    const Spacer(),
                    Text('已选 ${selectedIds.length} 个'),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: allGrenades.length,
                    itemBuilder: (ctx2, index) {
                      final g = allGrenades[index];
                      g.layer.loadSync();
                      g.layer.value?.map.loadSync();
                      final mapName = g.layer.value?.map.value?.name ?? '-';
                      final layerName = g.layer.value?.name ?? '-';
                      return CheckboxListTile(
                        dense: true,
                        value: selectedIds.contains(g.id),
                        title: Text(
                          g.title.isEmpty ? '(未命名道具)' : g.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('$mapName / $layerName'),
                        onChanged: (v) => setLocalState(() {
                          if (v == true) {
                            selectedIds.add(g.id);
                          } else {
                            selectedIds.remove(g.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedIds.toList()),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    final idSet = result.toSet();
    setState(() {
      _selectedGrenadesForSend = allGrenades
          .where((e) => idSet.contains(e.id))
          .toList(growable: false);
      _sendScope = _LanSendScope.grenades;
    });
  }

  String _currentScopeSummary() {
    switch (_sendScope) {
      case _LanSendScope.all:
        return '全部数据';
      case _LanSendScope.map:
        return _selectedMapForSend == null
            ? '按地图（未选择）'
            : '地图：${_selectedMapForSend!.name}';
      case _LanSendScope.grenades:
        return '按道具（${_selectedGrenadesForSend.length} 个）';
    }
  }

  Set<String> _resolveScopeMapKeys(Isar isar) {
    switch (_sendScope) {
      case _LanSendScope.all:
        return isar.gameMaps
            .where()
            .findAllSync()
            .map((e) => e.name.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
      case _LanSendScope.map:
        final name = _selectedMapForSend?.name.trim() ?? '';
        return name.isEmpty ? <String>{} : {name};
      case _LanSendScope.grenades:
        final mapKeys = <String>{};
        for (final grenade in _selectedGrenadesForSend) {
          grenade.layer.loadSync();
          final layer = grenade.layer.value;
          if (layer == null) continue;
          layer.map.loadSync();
          final map = layer.map.value;
          if (map == null) continue;
          final mapName = map.name.trim();
          if (mapName.isNotEmpty) {
            mapKeys.add(mapName);
          }
        }
        return mapKeys;
    }
  }

  String _resolvePeerNodeId(String host, int port) {
    for (final d in _discoveredDevices) {
      if (d.host.trim() == host.trim() && d.port == port) {
        final nodeId = d.nodeId.trim();
        if (nodeId.isNotEmpty) return nodeId;
      }
    }
    return '$host:$port';
  }

  Future<String> _resolveConnectableHost(String host, int port) async {
    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) {
      throw const SocketException('目标地址为空');
    }
    if (InternetAddress.tryParse(trimmedHost) != null) {
      return trimmedHost;
    }

    try {
      final resolved = await InternetAddress.lookup(trimmedHost);
      for (final address in resolved) {
        if (address.type == InternetAddressType.IPv4) {
          return address.address;
        }
      }
      if (resolved.isNotEmpty) {
        return resolved.first.address;
      }
    } catch (_) {}

    if (_receiveController.localIps.isEmpty) {
      await _receiveController.refreshLocalIps();
    }
    throw SocketException('无法解析设备地址：$trimmedHost');
  }

  Future<void> _sendAllToTarget() async {
    final originalHost = _targetHostController.text.trim();
    final port = _parsedTargetPort;
    if (originalHost.isEmpty || port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效的目标 IP/主机和端口'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_sendScope == _LanSendScope.map && _selectedMapForSend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择地图'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_sendScope == _LanSendScope.grenades &&
        _selectedGrenadesForSend.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择道具'), backgroundColor: Colors.orange),
      );
      return;
    }

    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);
    final scopeMapKeys = _resolveScopeMapKeys(isar);
    final scopeMapList = scopeMapKeys.toList(growable: false);
    final peerNodeId = _resolvePeerNodeId(originalHost, port);
    Map<String, String> baseMapBaselineIds = const {};
    Map<String, Map<String, String>> currentMapDigests = const {};
    List<Grenade>? incrementalGrenades;
    List<PackageGrenadeTombstoneData> incrementalTombstones = const [];
    if (_sendMode == _LanSyncMode.incremental) {
      if (_sendScope == _LanSendScope.grenades) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('增量模式第一版暂不支持按道具发送'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (scopeMapList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法识别当前范围对应的地图，请先检查范围选择'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      baseMapBaselineIds = await _localStore.loadAckedMapBaselineIds(
        peerNodeId: peerNodeId,
        mapKeys: scopeMapList,
      );
      if (baseMapBaselineIds.length != scopeMapList.length) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该设备尚未建立完整增量基线，请先完成一次全量同步'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final baselineSnapshots = await _localStore.loadMapBaselineSnapshots(
        peerNodeId: peerNodeId,
        mapKeys: scopeMapList,
        expectedBaselineIds: baseMapBaselineIds,
      );
      if (baselineSnapshots.length != scopeMapList.length) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('增量快照缺失或过期，请先完成一次全量同步'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      currentMapDigests =
          await dataService.buildGrenadeDigestByMap(mapKeys: scopeMapKeys);
      final changedUniqueIds = <String>{};
      final deletedUniqueIds = <String>{};
      for (final mapKey in scopeMapList) {
        final baselineDigest = baselineSnapshots[mapKey] ?? const {};
        final currentDigest = currentMapDigests[mapKey] ?? const {};
        for (final entry in currentDigest.entries) {
          if (baselineDigest[entry.key] != entry.value) {
            changedUniqueIds.add(entry.key);
          }
        }
        for (final uniqueId in baselineDigest.keys) {
          if (!currentDigest.containsKey(uniqueId)) {
            deletedUniqueIds.add(uniqueId);
          }
        }
      }
      final tombstonesByUniqueId = await _localStore.loadGrenadeTombstones(
        uniqueIds: deletedUniqueIds,
        mapKeys: scopeMapList,
      );
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      incrementalTombstones = deletedUniqueIds
          .map((uniqueId) {
            final existing = tombstonesByUniqueId[uniqueId];
            if (existing != null) {
              return PackageGrenadeTombstoneData(
                uniqueId: existing.uniqueId,
                mapName: existing.mapName,
                deletedAt: existing.deletedAt,
              );
            }
            final mapName = scopeMapList.firstWhere(
              (mapKey) =>
                  (baselineSnapshots[mapKey] ?? const {}).containsKey(uniqueId),
              orElse: () => '',
            );
            if (mapName.isEmpty) return null;
            return PackageGrenadeTombstoneData(
              uniqueId: uniqueId,
              mapName: mapName,
              deletedAt: nowMs,
            );
          })
          .whereType<PackageGrenadeTombstoneData>()
          .toList(growable: false);
      if (changedUniqueIds.isEmpty && incrementalTombstones.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前范围没有可同步的增量变更')),
        );
        return;
      }
      incrementalGrenades =
          await dataService.loadGrenadesByUniqueIds(changedUniqueIds);
      if (changedUniqueIds.isNotEmpty && incrementalGrenades.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到可发送的增量道具，请重试')),
        );
        return;
      }
    }

    setState(() {
      _isSendingAll = true;
      _isWaitingForApproval = false;
      _sendProgress = null;
      _sendProgressLabel = '';
    });
    String? packagePath;
    try {
      final host = await _resolveConnectableHost(originalHost, port);
      switch (_sendScope) {
        case _LanSendScope.all:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: 2,
            explicitGrenades: _sendMode == _LanSyncMode.incremental
                ? incrementalGrenades
                : null,
            grenadeTombstones: incrementalTombstones,
          );
          break;
        case _LanSendScope.map:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: _sendMode == _LanSyncMode.incremental ? 2 : 1,
            singleMap: _sendMode == _LanSyncMode.incremental
                ? null
                : _selectedMapForSend!,
            explicitGrenades: _sendMode == _LanSyncMode.incremental
                ? incrementalGrenades
                : null,
            grenadeTombstones: incrementalTombstones,
          );
          break;
        case _LanSendScope.grenades:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: 2,
            explicitGrenades: _selectedGrenadesForSend,
            grenadeTombstones: const [],
          );
          break;
      }

      final pkgFile = File(packagePath);
      final fileName = pkgFile.uri.pathSegments.isEmpty
          ? 'lan_sync_data.cs2pkg'
          : pkgFile.uri.pathSegments.last;
      final fileSize = await pkgFile.length();
      final syncEnvelopeId = 'env_${DateTime.now().microsecondsSinceEpoch}';
      if (mounted) {
        setState(() {
          _isWaitingForApproval = true;
          _sendProgress = 0;
          _sendProgressLabel = '等待接收方确认...';
        });
      }

      final reqResp = await LanSyncTransferClient.requestTransfer(
        host: host,
        port: port,
        fileName: fileName,
        sizeBytes: fileSize,
        senderName: _receiveController.localDeviceName,
        scopeSummary: _currentScopeSummary(),
        syncMode: _sendMode == _LanSyncMode.incremental ? 'delta' : 'full',
        scopeType: switch (_sendScope) {
          _LanSendScope.map => 'map',
          _LanSendScope.grenades => 'grenades',
          _LanSendScope.all => 'all',
        },
        scopeMapKeys: scopeMapList,
        syncEnvelopeId: syncEnvelopeId,
        senderNodeId: _receiveController.localNodeId,
        receiverNodeId: peerNodeId.contains(':') ? '' : peerNodeId,
        packageSchemaVersion: 4,
        baseMapBaselineIds: baseMapBaselineIds,
      );
      if (!reqResp.ok || reqResp.requestId.trim().isEmpty) {
        throw StateError(
          '发送请求失败（HTTP ${reqResp.statusCode}）: ${_friendlySendErrorBody(reqResp.body)}',
        );
      }

      final requestId = reqResp.requestId.trim();
      var approved = false;
      var rejectedMessage = '';
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final statusResp = await LanSyncTransferClient.getTransferRequestStatus(
          host: host,
          port: port,
          requestId: requestId,
        );
        if (!statusResp.ok) {
          continue;
        }
        if (statusResp.status ==
            LanIncomingTransferRequestStatus.approved.name) {
          approved = true;
          break;
        }
        if (statusResp.status ==
            LanIncomingTransferRequestStatus.rejected.name) {
          rejectedMessage = (statusResp.message ?? '').trim();
          break;
        }
      }
      if (!approved) {
        throw StateError(
            rejectedMessage.isNotEmpty ? rejectedMessage : '接收方未同意传输');
      }

      if (mounted) {
        setState(() {
          _isWaitingForApproval = false;
          _sendProgress = 0;
          _sendProgressLabel = '开始传输...';
        });
      }

      final response = await LanSyncTransferClient.sendPackage(
        host: host,
        port: port,
        filePath: packagePath,
        transferRequestId: requestId,
        onSendProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _sendProgress = total <= 0 ? null : (sent / total).clamp(0.0, 1.0);
            _sendProgressLabel =
                '传输中 ${_formatBytes(sent)} / ${_formatBytes(total)}';
          });
        },
      );

      if (!response.isSuccess) {
        throw StateError(
          '发送失败（HTTP ${response.statusCode}）: ${_friendlySendErrorBody(response.body)}',
        );
      }

      if (mounted) {
        setState(() {
          _sendProgress = 1;
          _sendProgressLabel = '上传完成，等待对方导入...';
        });
      }

      final importDeadline = DateTime.now().add(const Duration(minutes: 5));
      var importSucceeded = false;
      String? importFailedMessage;
      LanSyncTransferRequestResponse? finalImportStatus;
      while (DateTime.now().isBefore(importDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final statusResp = await LanSyncTransferClient.getTransferRequestStatus(
          host: host,
          port: port,
          requestId: requestId,
        );
        if (!statusResp.ok) continue;
        finalImportStatus = statusResp;
        if (statusResp.status ==
            LanIncomingTransferRequestStatus.imported.name) {
          importSucceeded = true;
          break;
        }
        if (statusResp.status ==
                LanIncomingTransferRequestStatus.importFailed.name ||
            statusResp.status ==
                LanIncomingTransferRequestStatus.importCancelled.name ||
            statusResp.status ==
                LanIncomingTransferRequestStatus.rejected.name ||
            statusResp.status ==
                LanIncomingTransferRequestStatus.expired.name) {
          importFailedMessage = (statusResp.message ?? '').trim();
          break;
        }
      }
      if (!importSucceeded) {
        throw StateError(importFailedMessage?.isNotEmpty == true
            ? importFailedMessage!
            : '对方尚未完成导入确认，请稍后重试');
      }

      if (scopeMapList.isNotEmpty) {
        final nextBaselineId =
            finalImportStatus?.syncEnvelopeId.trim().isNotEmpty == true
                ? finalImportStatus!.syncEnvelopeId
                : syncEnvelopeId;
        await _localStore.upsertAckedMapBaselines(
          peerNodeId: peerNodeId,
          mapKeys: scopeMapList,
          baselineId: nextBaselineId,
        );
        final mapDigestsForStore = _sendMode == _LanSyncMode.incremental
            ? currentMapDigests
            : await dataService.buildGrenadeDigestByMap(mapKeys: scopeMapKeys);
        final scopedDigests = <String, Map<String, String>>{
          for (final mapKey in scopeMapList)
            mapKey: mapDigestsForStore[mapKey] ?? const {},
        };
        await _localStore.upsertMapBaselineSnapshots(
          peerNodeId: peerNodeId,
          mapDigests: scopedDigests,
          baselineId: nextBaselineId,
        );
      }

      await _appendHistory(
        category: 'send',
        title: '发送成功',
        detail:
            '$originalHost -> $host:$port · ${_currentScopeSummary()} · ${_sendMode == _LanSyncMode.incremental ? "增量" : "全量"}',
        success: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sendMode == _LanSyncMode.incremental
                ? '增量同步完成（已收到导入确认）'
                : '全量同步完成（已收到导入确认）',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      await _appendHistory(
        category: 'send',
        title: '发送失败',
        detail: '$originalHost:$port · ${_currentScopeSummary()} · $e',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (packagePath != null) {
        final file = File(packagePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (mounted) {
        setState(() {
          _isSendingAll = false;
          _isWaitingForApproval = false;
          _sendProgress = null;
          _sendProgressLabel = '';
        });
      }
    }
  }

  Future<void> _toggleReceiveMode(bool enabled) async {
    if (enabled) {
      await _receiveController.start();
      if (!mounted) return;
      final error = _receiveController.lastError;
      if (error != null && !_receiveController.isRunning) {
        await _appendHistory(
          category: 'system',
          title: '接收模式启动失败',
          detail: error,
          success: false,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      } else if (_receiveController.isRunning) {
        await _appendHistory(
          category: 'system',
          title: '接收模式已开启',
          detail: '端口 ${_receiveController.port}',
          success: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('接收模式已开启（端口 ${_receiveController.port}）'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    await _receiveController.stop();
    await _appendHistory(
      category: 'system',
      title: '接收模式已关闭',
      detail: '用户手动关闭',
      success: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('接收模式已关闭')),
    );
  }

  Future<void> _openImportPreview(LanReceivedPackageTask task) async {
    final transferRequestId = (task.transferRequestId ?? '').trim();
    final file = File(task.filePath);
    if (!await file.exists()) {
      await _receiveController.markTaskStatus(
        task.id,
        LanReceiveTaskStatus.failed,
        message: '文件不存在，可能已被系统清理',
      );
      if (transferRequestId.isNotEmpty) {
        await _receiveController.markIncomingRequestStatus(
          transferRequestId,
          LanIncomingTransferRequestStatus.importFailed,
          message: '导入失败：接收文件不存在',
        );
      }
      await _appendHistory(
        category: 'import',
        title: '导入失败',
        detail: '${task.fileName} · 文件不存在',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('文件不存在，无法导入'), backgroundColor: Colors.red),
      );
      return;
    }

    await _receiveController.markTaskStatus(
      task.id,
      LanReceiveTaskStatus.importing,
      clearMessage: true,
    );
    if (transferRequestId.isNotEmpty) {
      await _receiveController.markIncomingRequestStatus(
        transferRequestId,
        LanIncomingTransferRequestStatus.importing,
        clearMessage: true,
      );
    }

    try {
      if (!mounted) return;
      final importResult = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => ImportPreviewScreen(filePath: task.filePath),
        ),
      );

      if (importResult == null) {
        await _receiveController.markTaskStatus(
          task.id,
          LanReceiveTaskStatus.pending,
          message: '未导入（用户返回）',
        );
        if (transferRequestId.isNotEmpty) {
          await _receiveController.markIncomingRequestStatus(
            transferRequestId,
            LanIncomingTransferRequestStatus.importCancelled,
            message: '接收方取消导入',
          );
        }
        await _appendHistory(
          category: 'import',
          title: '取消导入',
          detail: task.fileName,
          success: true,
        );
        return;
      }

      await _receiveController.markTaskStatus(
        task.id,
        LanReceiveTaskStatus.imported,
        message: importResult,
      );
      if (transferRequestId.isNotEmpty) {
        await _receiveController.markIncomingRequestStatus(
          transferRequestId,
          LanIncomingTransferRequestStatus.imported,
          message: importResult,
          importSummary: {
            'result': importResult,
            'taskId': task.id,
            'importedAtMs': DateTime.now().millisecondsSinceEpoch,
          },
        );
      }
      await _appendHistory(
        category: 'import',
        title: '导入完成',
        detail: '${task.fileName} · $importResult',
        success: importResult.contains('成功'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(importResult),
          backgroundColor:
              importResult.contains('成功') ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      await _receiveController.markTaskStatus(
        task.id,
        LanReceiveTaskStatus.failed,
        message: '导入预览失败: $e',
      );
      if (transferRequestId.isNotEmpty) {
        await _receiveController.markIncomingRequestStatus(
          transferRequestId,
          LanIncomingTransferRequestStatus.importFailed,
          message: '导入预览失败: $e',
        );
      }
      await _appendHistory(
        category: 'import',
        title: '导入失败',
        detail: '${task.fileName} · $e',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开导入预览失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  String _formatTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _friendlySendErrorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = (decoded['error'] as String? ?? '').trim();
        if (error == 'unknown_peer') {
          return '请重新配对设备';
        }
      }
    } catch (_) {}
    return body;
  }

  Widget _buildReceiveEndpointPanel(ColorScheme colorScheme) {
    final running = _receiveController.isRunning;
    final port = _receiveController.port;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            running ? '接收服务已启动' : '接收服务未启动',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: running ? Colors.green : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (running && port != null) ...[
            Text(
              '本机名称：${_receiveController.localDeviceName}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '本机节点ID：${_receiveController.localNodeId}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '本机地址：',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            if (_receiveController.localIps.isEmpty)
              Text(
                '未获取到局域网 IP（可点击右上角刷新）',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _receiveController.localIps
                    .map((ip) => Chip(label: Text('http://$ip:$port')))
                    .toList(),
              ),
          ] else
            Text(
              '开启接收模式后，本页会显示本机端口与可访问地址。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          if (_receiveController.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              _receiveController.lastError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiveTasks(ColorScheme colorScheme) {
    final tasks = _receiveController.tasks;
    if (tasks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('暂无待导入任务。'),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _receiveController.clearImportedTasks(),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('清理已导入'),
          ),
        ),
        ...tasks.map((task) {
          final canImport = task.status != LanReceiveTaskStatus.importing;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TaskStatusChip(status: task.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '时间：${_formatTime(task.receivedAt)}  大小：${_formatBytes(task.sizeBytes)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (task.status == LanReceiveTaskStatus.receiving ||
                      task.progress != null) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: task.progress),
                    const SizedBox(height: 4),
                    Text(
                      task.expectedBytes != null && task.expectedBytes! > 0
                          ? '接收进度：${_formatBytes(task.bytesReceived)} / ${_formatBytes(task.expectedBytes!)}'
                          : '接收进度：${_formatBytes(task.bytesReceived)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (task.remoteAddress != null)
                    Text(
                      '来源：${task.remoteAddress}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  if (task.message != null &&
                      task.message!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.message!,
                      style: TextStyle(
                        fontSize: 12,
                        color: task.status == LanReceiveTaskStatus.failed
                            ? Colors.red
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed:
                            canImport ? () => _openImportPreview(task) : null,
                        icon: const Icon(Icons.visibility),
                        label: const Text('预览导入'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _receiveController.removeTask(task.id),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('移除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.filePath,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pendingIncomingRequests = _receiveController.incomingRequests
        .where((e) => e.status == LanIncomingTransferRequestStatus.pending)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网同步'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.wifi,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '该功能仅支持同一网络环境（同一 Wi-Fi / 同一局域网）下的设备互传。',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.upload_file,
            title: '发送',
            action: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _isScanningDevices ? null : _scanDevices,
                  icon: _isScanningDevices
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_outlined),
                  label: Text(_isScanningDevices ? '扫描中' : '扫描'),
                ),
                TextButton.icon(
                  onPressed: _isSendingAll ? null : _showManualSendDialog,
                  icon: const Icon(Icons.link),
                  label: const Text('手动输入'),
                ),
              ],
            ),
            child: _isLoadingLocal
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('全量'),
                            selected: _sendMode == _LanSyncMode.full,
                            onSelected: (_) =>
                                setState(() => _sendMode = _LanSyncMode.full),
                          ),
                          ChoiceChip(
                            label: const Text('增量'),
                            selected: _sendMode == _LanSyncMode.incremental,
                            onSelected: (_) => setState(() {
                              _sendMode = _LanSyncMode.incremental;
                              if (_sendScope == _LanSendScope.grenades) {
                                _sendScope = _LanSendScope.all;
                              }
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('全部'),
                            selected: _sendScope == _LanSendScope.all,
                            onSelected: (_) =>
                                setState(() => _sendScope = _LanSendScope.all),
                          ),
                          ChoiceChip(
                            label: const Text('按地图'),
                            selected: _sendScope == _LanSendScope.map,
                            onSelected: (_) =>
                                setState(() => _sendScope = _LanSendScope.map),
                          ),
                          ChoiceChip(
                            label: const Text('按道具'),
                            selected: _sendScope == _LanSendScope.grenades,
                            onSelected: _sendMode == _LanSyncMode.incremental
                                ? null
                                : (_) => setState(
                                    () => _sendScope = _LanSendScope.grenades),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickMapForSend,
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('选择地图'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickGrenadesForSend,
                            icon: const Icon(Icons.list_alt),
                            label: Text(_selectedGrenadesForSend.isEmpty
                                ? '选择道具'
                                : '已选 ${_selectedGrenadesForSend.length} 个道具'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('当前发送范围：${_currentScopeSummary()}'),
                      ),
                      if (_isSendingAll) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _isWaitingForApproval ? null : _sendProgress,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _sendProgressLabel.isEmpty
                              ? (_isWaitingForApproval
                                  ? '等待接收方确认...'
                                  : '准备传输...')
                              : _sendProgressLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                      Text(
                        '扫描结果',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_discoveredDevices.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('暂无结果，点击“扫描”开始探测。'),
                        )
                      else
                        ..._discoveredDevices.map((d) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.wifi_tethering),
                              title: Text(
                                d.deviceName.isEmpty ? d.host : d.deviceName,
                              ),
                              subtitle: Text('${d.host}:${d.port}'),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: '发送到此设备',
                                    onPressed: _isSendingAll
                                        ? null
                                        : () => _sendToHostPort(d.host, d.port),
                                    icon: const Icon(Icons.send),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.download,
            title: '接收',
            action: TextButton.icon(
              onPressed: _receiveController.isStarting
                  ? null
                  : () => _receiveController.refreshLocalIps(),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新地址'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  value: _receiveController.isRunning,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('接收模式'),
                  subtitle: _receiveController.isStarting
                      ? const Text('正在启动...')
                      : null,
                  onChanged:
                      _receiveController.isStarting ? null : _toggleReceiveMode,
                ),
                if (pendingIncomingRequests.isNotEmpty) ...[
                  Text(
                    '待确认请求（${pendingIncomingRequests.length}）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  ...pendingIncomingRequests.take(4).map(
                        (req) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatBytes(req.sizeBytes)}'
                                  ' · ${req.syncMode == "delta" ? "增量" : "全量"}'
                                  '${req.scopeSummary.isEmpty ? '' : ' · ${req.scopeSummary}'}'
                                  '${req.senderName.isEmpty ? '' : ' · ${req.senderName}'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _receiveController
                                          .rejectIncomingRequest(req.id,
                                              message: '接收方拒绝'),
                                      child: const Text('拒绝'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.tonal(
                                      onPressed: () => _receiveController
                                          .approveIncomingRequest(req.id),
                                      child: const Text('同意'),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                ],
                _buildReceiveEndpointPanel(colorScheme),
                const SizedBox(height: 10),
                Text(
                  '待导入任务',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _buildReceiveTasks(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskStatusChip extends StatelessWidget {
  final LanReceiveTaskStatus status;

  const _TaskStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    switch (status) {
      case LanReceiveTaskStatus.receiving:
        text = '接收中';
        color = Colors.cyan;
        break;
      case LanReceiveTaskStatus.pending:
        text = '待导入';
        color = Colors.orange;
        break;
      case LanReceiveTaskStatus.importing:
        text = '导入中';
        color = Colors.blue;
        break;
      case LanReceiveTaskStatus.imported:
        text = '已导入';
        color = Colors.green;
        break;
      case LanReceiveTaskStatus.failed:
        text = '失败';
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: action!,
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
