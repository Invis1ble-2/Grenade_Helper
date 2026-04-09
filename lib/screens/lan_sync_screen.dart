import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../models/tag.dart';
import '../providers.dart';
import '../services/data_service.dart';
import '../services/lan_sync/lan_sync_discovery_service.dart';
import '../services/lan_sync/lan_sync_local_store.dart';
import '../services/lan_sync/lan_sync_receive_controller.dart';
import '../services/lan_sync/lan_sync_transfer_client.dart';
import '../widgets/map_icon.dart';
import '../widgets/selectable_grenade_list_item.dart';
import 'grenade_detail_screen.dart';
import 'import_preview_screen.dart';

enum _LanSendScope { all, map, grenades }

enum _LanSyncMode { full, incremental }

class _LanImportConflictDialogResult<T> {
  final T resolution;
  final bool applyToRemaining;

  const _LanImportConflictDialogResult({
    required this.resolution,
    required this.applyToRemaining,
  });
}

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
  final Set<String> _handledImportTaskIds = <String>{};
  bool _isAutoOpeningImportPreview = false;
  bool _isLoadingSyncDebug = false;
  bool _silentImportEnabled = false;

  @override
  void initState() {
    super.initState();
    _receiveController = LanSyncReceiveController(isar: ref.read(isarProvider));
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
    _maybeOpenImportPreviewDirectly();
  }

  void _maybeOpenImportPreviewDirectly() {
    if (!mounted || _isAutoOpeningImportPreview) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    LanReceivedPackageTask? task;
    for (final item in _receiveController.tasks) {
      if (item.status != LanReceiveTaskStatus.pending) continue;
      if (_handledImportTaskIds.contains(item.id)) continue;
      task = item;
      break;
    }
    if (task == null) return;

    _handledImportTaskIds.add(task.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isAutoOpeningImportPreview) return;
      final currentRoute = ModalRoute.of(context);
      if (currentRoute != null && !currentRoute.isCurrent) return;

      _isAutoOpeningImportPreview = true;
      unawaited(() async {
        try {
          if (_silentImportEnabled) {
            await _importTaskSilently(task!);
          } else {
            await _openImportPreview(task!);
          }
        } finally {
          _isAutoOpeningImportPreview = false;
          if (mounted) {
            _maybeOpenImportPreviewDirectly();
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
    await _localStore.cleanupLegacySyncState();
    final nodeId = await _localStore.loadOrCreateStableNodeId();
    final silentImportEnabled =
        await _localStore.loadReceiveSilentImportEnabled();
    _receiveController.setLocalNodeId(nodeId);
    await _refreshSyncDebugInfo();
    if (!mounted) return;
    setState(() {
      _silentImportEnabled = silentImportEnabled;
      _isLoadingLocal = false;
    });
  }

  Future<void> _refreshSyncDebugInfo() async {
    if (_isLoadingSyncDebug) return;
    _isLoadingSyncDebug = true;
    try {
      await _localStore.cleanupSyncTombstones();
      await _localStore.loadTombstoneStats();
      if (!mounted) return;
      setState(() {});
    } finally {
      _isLoadingSyncDebug = false;
    }
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

  Future<void> _setSilentImportEnabled(bool enabled) async {
    if (_silentImportEnabled == enabled) return;
    setState(() {
      _silentImportEnabled = enabled;
    });
    await _localStore.saveReceiveSilentImportEnabled(enabled);
    await _appendHistory(
      category: 'system',
      title: enabled ? '已开启静默导入' : '已关闭静默导入',
      detail: enabled ? '接收后自动后台导入' : '接收后打开导入预览',
      success: true,
    );
    if (enabled) {
      _maybeOpenImportPreviewDirectly();
    }
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
          const SnackBar(
              content: Text('未获取到本机局域网 IP，无法进行网段探测'),
              duration: Duration(seconds: 1)),
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
        SnackBar(
            content: Text('发现 ${results.length} 台设备'),
            duration: Duration(seconds: 1)),
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
        SnackBar(
            content: Text('网段探测失败: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1)),
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

  Future<void> _showSendModeHelpDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('同步模式说明'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '全量模式',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('发送当前范围内的完整数据，适合首次同步或大范围更新。'),
            SizedBox(height: 12),
            Text(
              '增量模式',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text('发送前会先获取接收端当前状态，再只传输本次真正缺失或较新的内容。'),
            SizedBox(height: 12),
            Text('注意：增量模式暂不支持按道具发送，且要求接收端支持新的 manifest 协议。'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickGrenadesForSend() async {
    final isar = ref.read(isarProvider);
    final allGrenades = isar.grenades.where().findAllSync()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (allGrenades.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有道具数据')));
      return;
    }

    final result = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => _LanSyncGrenadePickerScreen(
          grenades: allGrenades,
          initialSelectedIds: _selectedGrenadesForSend.map((e) => e.id).toSet(),
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

  bool _shouldSendIncrementalItem(
    LanSyncManifestItem local,
    LanSyncRemoteManifestItem? remote,
  ) {
    if (remote == null) return true;
    if (local.digest == remote.digest) return false;
    return local.updatedAtMs >= remote.updatedAtMs;
  }

  Future<
      ({
        List<Map<String, dynamic>> grenadePayloads,
        List<Map<String, dynamic>> tagPayloads,
        List<Map<String, dynamic>> areaPayloads,
        List<Map<String, dynamic>> favoriteFolderPayloads,
        List<Map<String, dynamic>> impactGroupPayloads,
        Set<String> filesToZip,
        List<PackageGrenadeTombstoneData> grenadeTombstones,
        List<PackageEntityTombstoneData> entityTombstones,
      })> _prepareIncrementalSyncPayload({
    required DataService dataService,
    required String host,
    required int port,
    required Set<String> scopeMapKeys,
    required List<String> scopeMapList,
    required String peerNodeId,
  }) async {
    final manifestResp = await LanSyncTransferClient.fetchRemoteManifest(
      host: host,
      port: port,
      scopeType: switch (_sendScope) {
        _LanSendScope.map => 'map',
        _LanSendScope.grenades => 'grenades',
        _LanSendScope.all => 'all',
      },
      scopeMapKeys: scopeMapList,
      senderNodeId: _receiveController.localNodeId,
      receiverNodeId: peerNodeId.contains(':') ? '' : peerNodeId,
      manifestSchemaVersion: 1,
    );
    if (!manifestResp.ok || manifestResp.manifestSchemaVersion != 1) {
      throw StateError(
        '对方版本不支持新的增量协议，请改用全量同步（HTTP ${manifestResp.statusCode}）',
      );
    }

    final localManifest =
        await dataService.buildLanSyncManifest(mapKeys: scopeMapKeys);

    final grenadePayloads = <Map<String, dynamic>>[];
    final tagPayloads = <Map<String, dynamic>>[];
    final areaPayloads = <Map<String, dynamic>>[];
    final favoriteFolderPayloads = <Map<String, dynamic>>[];
    final impactGroupPayloads = <Map<String, dynamic>>[];
    final filesToZip = <String>{};

    for (final entry in localManifest.grenades.entries) {
      if (!_shouldSendIncrementalItem(
          entry.value, manifestResp.grenades[entry.key])) {
        continue;
      }
      grenadePayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      filesToZip.addAll(entry.value.filesToZip);
    }
    for (final entry in localManifest.tags.entries) {
      if (_shouldSendIncrementalItem(
          entry.value, manifestResp.tags[entry.key])) {
        tagPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }
    for (final entry in localManifest.areas.entries) {
      if (_shouldSendIncrementalItem(
          entry.value, manifestResp.areas[entry.key])) {
        areaPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }
    for (final entry in localManifest.favoriteFolders.entries) {
      if (_shouldSendIncrementalItem(
          entry.value, manifestResp.favoriteFolders[entry.key])) {
        favoriteFolderPayloads
            .add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }
    for (final entry in localManifest.impactGroups.entries) {
      if (_shouldSendIncrementalItem(
          entry.value, manifestResp.impactGroups[entry.key])) {
        impactGroupPayloads.add(Map<String, dynamic>.from(entry.value.rawData));
      }
    }

    final remoteOnlyGrenadeIds = manifestResp.grenades.keys
        .where((key) => !localManifest.grenades.containsKey(key))
        .toSet();
    final grenadeTombstonesById = await _localStore.loadGrenadeTombstones(
      uniqueIds: remoteOnlyGrenadeIds,
      mapKeys: scopeMapList,
    );
    final grenadeTombstones = remoteOnlyGrenadeIds
        .map((uniqueId) {
          final tombstone = grenadeTombstonesById[uniqueId];
          final remote = manifestResp.grenades[uniqueId];
          if (tombstone == null || remote == null) return null;
          if (tombstone.deletedAt <= remote.updatedAtMs) return null;
          return PackageGrenadeTombstoneData(
            uniqueId: tombstone.uniqueId,
            mapName: tombstone.mapName,
            deletedAt: tombstone.deletedAt,
          );
        })
        .whereType<PackageGrenadeTombstoneData>()
        .toList(growable: false);

    final localEntityCompositeKeys = <String>{
      ...localManifest.tags.keys.map((e) => dataService.entityTombstoneKey(
            entityType: LanSyncEntityTombstoneType.tag,
            entityKey: e,
          )),
      ...localManifest.areas.keys.map((e) => dataService.entityTombstoneKey(
            entityType: LanSyncEntityTombstoneType.area,
            entityKey: e,
          )),
      ...localManifest.favoriteFolders.keys
          .map((e) => dataService.entityTombstoneKey(
                entityType: LanSyncEntityTombstoneType.favoriteFolder,
                entityKey: e,
              )),
      ...localManifest.impactGroups.keys
          .map((e) => dataService.entityTombstoneKey(
                entityType: LanSyncEntityTombstoneType.impactGroup,
                entityKey: e,
              )),
    };
    final remoteEntityItems = <String, LanSyncRemoteManifestItem>{
      for (final entry in manifestResp.tags.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.tag,
          entityKey: entry.key,
        ): entry.value,
      for (final entry in manifestResp.areas.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.area,
          entityKey: entry.key,
        ): entry.value,
      for (final entry in manifestResp.favoriteFolders.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.favoriteFolder,
          entityKey: entry.key,
        ): entry.value,
      for (final entry in manifestResp.impactGroups.entries)
        dataService.entityTombstoneKey(
          entityType: LanSyncEntityTombstoneType.impactGroup,
          entityKey: entry.key,
        ): entry.value,
    };
    final remoteOnlyEntityKeys = remoteEntityItems.keys
        .where((key) => !localEntityCompositeKeys.contains(key))
        .toSet();
    final entityTombstoneEntries = await _localStore.loadEntityTombstones(
      mapKeys: scopeMapList,
    );
    final entityTombstones = remoteOnlyEntityKeys
        .map((compositeKey) {
          final tombstone = entityTombstoneEntries[compositeKey];
          final remote = remoteEntityItems[compositeKey];
          if (tombstone == null || remote == null) return null;
          if (tombstone.deletedAt <= remote.updatedAtMs) return null;
          return PackageEntityTombstoneData(
            entityType: tombstone.entityType,
            entityKey: tombstone.entityKey,
            mapName: tombstone.mapName,
            deletedAt: tombstone.deletedAt,
            payload: tombstone.payload,
          );
        })
        .whereType<PackageEntityTombstoneData>()
        .toList(growable: false);

    return (
      grenadePayloads: grenadePayloads,
      tagPayloads: tagPayloads,
      areaPayloads: areaPayloads,
      favoriteFolderPayloads: favoriteFolderPayloads,
      impactGroupPayloads: impactGroupPayloads,
      filesToZip: filesToZip,
      grenadeTombstones: grenadeTombstones,
      entityTombstones: entityTombstones,
    );
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
        const SnackBar(
            content: Text('请先选择地图'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1)),
      );
      return;
    }
    if (_sendScope == _LanSendScope.grenades &&
        _selectedGrenadesForSend.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先选择道具'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1)),
      );
      return;
    }

    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);
    final scopeMapKeys = _resolveScopeMapKeys(isar);
    final scopeMapList = scopeMapKeys.toList(growable: false);
    final peerNodeId = _resolvePeerNodeId(originalHost, port);
    List<Map<String, dynamic>> incrementalGrenadePayloads = const [];
    List<Map<String, dynamic>> incrementalTagPayloads = const [];
    List<Map<String, dynamic>> incrementalAreaPayloads = const [];
    List<Map<String, dynamic>> incrementalFavoriteFolderPayloads = const [];
    List<Map<String, dynamic>> incrementalImpactGroupPayloads = const [];
    Set<String> incrementalFilesToZip = const <String>{};
    List<PackageGrenadeTombstoneData> incrementalTombstones = const [];
    List<PackageEntityTombstoneData> incrementalEntityTombstones = const [];
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
      final host = await _resolveConnectableHost(originalHost, port);
      final incremental = await _prepareIncrementalSyncPayload(
        dataService: dataService,
        host: host,
        port: port,
        scopeMapKeys: scopeMapKeys,
        scopeMapList: scopeMapList,
        peerNodeId: peerNodeId,
      );
      incrementalGrenadePayloads = incremental.grenadePayloads;
      incrementalTagPayloads = incremental.tagPayloads;
      incrementalAreaPayloads = incremental.areaPayloads;
      incrementalFavoriteFolderPayloads = incremental.favoriteFolderPayloads;
      incrementalImpactGroupPayloads = incremental.impactGroupPayloads;
      incrementalFilesToZip = incremental.filesToZip;
      incrementalTombstones = incremental.grenadeTombstones;
      incrementalEntityTombstones = incremental.entityTombstones;
      if (incrementalGrenadePayloads.isEmpty &&
          incrementalTagPayloads.isEmpty &&
          incrementalAreaPayloads.isEmpty &&
          incrementalFavoriteFolderPayloads.isEmpty &&
          incrementalImpactGroupPayloads.isEmpty &&
          incrementalTombstones.isEmpty &&
          incrementalEntityTombstones.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前范围没有可同步的增量变更')),
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
      final fullManifest =
          _sendMode == _LanSyncMode.full && _sendScope != _LanSendScope.grenades
              ? await dataService.buildLanSyncManifest(mapKeys: scopeMapKeys)
              : null;
      switch (_sendScope) {
        case _LanSendScope.all:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: 2,
            explicitGrenadePayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalGrenadePayloads
                : fullManifest?.grenades.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitTagPayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalTagPayloads
                : fullManifest?.tags.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitAreaPayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalAreaPayloads
                : fullManifest?.areas.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitFavoriteFolderPayloads: _sendMode ==
                    _LanSyncMode.incremental
                ? incrementalFavoriteFolderPayloads
                : fullManifest?.favoriteFolders.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitImpactGroupPayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalImpactGroupPayloads
                : fullManifest?.impactGroups.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitFilesToZip: _sendMode == _LanSyncMode.incremental
                ? incrementalFilesToZip
                : fullManifest?.grenades.values
                        .expand((item) => item.filesToZip)
                        .toSet() ??
                    const <String>{},
            grenadeTombstones: incrementalTombstones,
            entityTombstones: incrementalEntityTombstones,
          );
          break;
        case _LanSendScope.map:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: _sendMode == _LanSyncMode.incremental ? 2 : 1,
            singleMap: _sendMode == _LanSyncMode.incremental
                ? null
                : _selectedMapForSend!,
            explicitGrenadePayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalGrenadePayloads
                : fullManifest?.grenades.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitTagPayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalTagPayloads
                : fullManifest?.tags.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitAreaPayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalAreaPayloads
                : fullManifest?.areas.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitFavoriteFolderPayloads: _sendMode ==
                    _LanSyncMode.incremental
                ? incrementalFavoriteFolderPayloads
                : fullManifest?.favoriteFolders.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitImpactGroupPayloads: _sendMode == _LanSyncMode.incremental
                ? incrementalImpactGroupPayloads
                : fullManifest?.impactGroups.values
                        .map((item) => Map<String, dynamic>.from(item.rawData))
                        .toList(growable: false) ??
                    const [],
            explicitFilesToZip: _sendMode == _LanSyncMode.incremental
                ? incrementalFilesToZip
                : fullManifest?.grenades.values
                        .expand((item) => item.filesToZip)
                        .toSet() ??
                    const <String>{},
            grenadeTombstones: incrementalTombstones,
            entityTombstones: incrementalEntityTombstones,
          );
          break;
        case _LanSendScope.grenades:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: 2,
            explicitGrenades: _selectedGrenadesForSend,
            grenadeTombstones: const [],
            entityTombstones: const [],
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
        packageSchemaVersion: 6,
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
      while (DateTime.now().isBefore(importDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final statusResp = await LanSyncTransferClient.getTransferRequestStatus(
          host: host,
          port: port,
          requestId: requestId,
        );
        if (!statusResp.ok) continue;
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

      await _refreshSyncDebugInfo();

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
            duration: Duration(seconds: 1)),
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
        SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1)),
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
          SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1)),
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
      const SnackBar(content: Text('接收模式已关闭'), duration: Duration(seconds: 1)),
    );
  }

  Set<String> _buildSilentImportSelectedIds(PackagePreviewResult preview) {
    final selected = <String>{};
    for (final mapGrenades in preview.grenadesByMap.values) {
      for (final item in mapGrenades) {
        if (item.status != ImportStatus.skip) {
          selected.add(item.uniqueId);
        }
      }
    }
    return selected;
  }

  Future<bool?> _showImportConflictNoticeDialog(ImportConflictNotice notice) {
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

  Future<_LanImportConflictDialogResult<ImportTagConflictResolution>?>
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

    return showDialog<
        _LanImportConflictDialogResult<ImportTagConflictResolution>>(
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
                _LanImportConflictDialogResult<ImportTagConflictResolution>(
                  resolution: ImportTagConflictResolution.local,
                  applyToRemaining: applyToRemaining,
                ),
              ),
              child: const Text('用本地'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _LanImportConflictDialogResult<ImportTagConflictResolution>(
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

  Future<_LanImportConflictDialogResult<ImportAreaConflictResolution>?>
      _showAreaConflictDialog(
    AreaConflictGroup conflict, {
    required int index,
    required int total,
  }) async {
    final layersText = conflict.layers.join('、');
    var applyToRemaining = false;
    return showDialog<
        _LanImportConflictDialogResult<ImportAreaConflictResolution>>(
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
                _LanImportConflictDialogResult<ImportAreaConflictResolution>(
                  resolution: ImportAreaConflictResolution.keepLocal,
                  applyToRemaining: applyToRemaining,
                ),
              ),
              child: const Text('本地保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _LanImportConflictDialogResult<ImportAreaConflictResolution>(
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

  Future<void> _importTaskSilently(LanReceivedPackageTask task) async {
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
        title: '静默导入失败',
        detail: '${task.fileName} · 文件不存在',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('文件不存在，无法导入'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1)),
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
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      final preview = await dataService.previewPackage(
        task.filePath,
        mode: ImportPackageMode.lanSync,
      );
      if (preview == null) {
        throw StateError('文件格式错误或无数据');
      }

      final selectedIds = _buildSilentImportSelectedIds(preview);
      final conflictNotice = await dataService.collectImportConflictNotice(
        preview,
        selectedIds,
        mode: ImportPackageMode.lanSync,
      );
      if (conflictNotice.hasConflicts) {
        if (!mounted) return;
        final continueImport =
            await _showImportConflictNoticeDialog(conflictNotice);
        if (continueImport != true) {
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
            detail: '${task.fileName} · 冲突处理已取消',
            success: true,
          );
          await _receiveController.removeTask(task.id);
          return;
        }
      }

      final tagResolutions = <String, ImportTagConflictResolution>{};
      final areaResolutions = <String, ImportAreaConflictResolution>{};
      ImportTagConflictResolution? tagResolutionForRemaining;
      ImportAreaConflictResolution? areaResolutionForRemaining;

      final tagConflictBundle =
          await dataService.collectTagConflicts(preview, selectedIds);
      final tagConflicts = tagConflictBundle.tagConflicts;
      for (var i = 0; i < tagConflicts.length; i++) {
        if (!mounted) return;
        final conflict = tagConflicts[i];
        final dialogResult = tagResolutionForRemaining != null
            ? _LanImportConflictDialogResult<ImportTagConflictResolution>(
                resolution: tagResolutionForRemaining,
                applyToRemaining: true,
              )
            : await _showTagConflictDialog(
                conflict,
                index: i + 1,
                total: tagConflicts.length,
              );
        if (dialogResult == null) {
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
            detail: '${task.fileName} · 标签冲突处理已取消',
            success: true,
          );
          await _receiveController.removeTask(task.id);
          return;
        }
        tagResolutions[conflict.sharedTag.tagUuid] = dialogResult.resolution;
        if (dialogResult.applyToRemaining) {
          tagResolutionForRemaining = dialogResult.resolution;
        }
      }

      final areaConflicts = await dataService.collectAreaConflicts(
        preview,
        selectedIds,
        tagResolutions: tagResolutions,
      );
      for (var i = 0; i < areaConflicts.length; i++) {
        if (!mounted) return;
        final conflict = areaConflicts[i];
        final dialogResult = areaResolutionForRemaining != null
            ? _LanImportConflictDialogResult<ImportAreaConflictResolution>(
                resolution: areaResolutionForRemaining,
                applyToRemaining: true,
              )
            : await _showAreaConflictDialog(
                conflict,
                index: i + 1,
                total: areaConflicts.length,
              );
        if (dialogResult == null) {
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
            detail: '${task.fileName} · 区域冲突处理已取消',
            success: true,
          );
          await _receiveController.removeTask(task.id);
          return;
        }
        areaResolutions[conflict.tagUuid] = dialogResult.resolution;
        if (dialogResult.applyToRemaining) {
          areaResolutionForRemaining = dialogResult.resolution;
        }
      }

      final importResult = await dataService.importFromPreview(
        preview,
        selectedIds,
        tagResolutions: tagResolutions,
        areaResolutions: areaResolutions,
        mode: ImportPackageMode.lanSync,
      );

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
            'silentImport': true,
          },
        );
      }
      await _appendHistory(
        category: 'import',
        title: '静默导入完成',
        detail: '${task.fileName} · $importResult',
        success: importResult.contains('成功'),
      );
      await _receiveController.removeTask(task.id, deleteFile: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('静默导入完成：$importResult'),
          backgroundColor:
              importResult.contains('成功') ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      await _receiveController.markTaskStatus(
        task.id,
        LanReceiveTaskStatus.failed,
        message: '静默导入失败: $e',
      );
      if (transferRequestId.isNotEmpty) {
        await _receiveController.markIncomingRequestStatus(
          transferRequestId,
          LanIncomingTransferRequestStatus.importFailed,
          message: '静默导入失败: $e',
        );
      }
      await _appendHistory(
        category: 'import',
        title: '静默导入失败',
        detail: '${task.fileName} · $e',
        success: false,
      );
      await _receiveController.removeTask(task.id, deleteFile: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('静默导入失败: $e'), backgroundColor: Colors.red),
      );
    }
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
          builder: (_) => ImportPreviewScreen(
            filePath: task.filePath,
            importMode: ImportPackageMode.lanSync,
          ),
        ),
      );

      if (importResult == null) {
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
        await _receiveController.removeTask(task.id);
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
      await _receiveController.removeTask(task.id, deleteFile: false);
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
      await _receiveController.removeTask(task.id, deleteFile: false);
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
                    '该功能仅支持同一网络环境（同一 Wi-Fi / 同一局域网）下的设备互传。请确保双方设备已连接到同一网络，并且网络环境允许设备间通信（部分公共 Wi-Fi 可能有限制）。',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sync_problem_outlined,
                  size: 18,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '若你是从旧版本升级到当前版本，建议先在设备间执行一次全量同步，统一旧版本遗留的数据状态；完成后再使用增量同步会更稳定。',
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer,
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
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('全量'),
                                  selected: _sendMode == _LanSyncMode.full,
                                  onSelected: (_) => setState(
                                      () => _sendMode = _LanSyncMode.full),
                                ),
                                ChoiceChip(
                                  label: const Text('增量'),
                                  selected:
                                      _sendMode == _LanSyncMode.incremental,
                                  onSelected: (_) => setState(() {
                                    _sendMode = _LanSyncMode.incremental;
                                    if (_sendScope == _LanSendScope.grenades) {
                                      _sendScope = _LanSendScope.all;
                                    }
                                  }),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _showSendModeHelpDialog,
                            tooltip: '同步模式说明',
                            icon: const Icon(Icons.help_outline),
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
                          if (_sendMode != _LanSyncMode.incremental)
                            ChoiceChip(
                              label: const Text('按道具'),
                              selected: _sendScope == _LanSendScope.grenades,
                              onSelected: (_) => setState(
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
                          if (_sendMode != _LanSyncMode.incremental)
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
                SwitchListTile(
                  value: _silentImportEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('静默导入'),
                  subtitle: const Text('接收后跳过预览自动导入，发生冲突时会弹窗确认'),
                  onChanged: _setSilentImportEnabled,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanSyncGrenadePickerScreen extends StatefulWidget {
  final List<Grenade> grenades;
  final Set<int> initialSelectedIds;

  const _LanSyncGrenadePickerScreen({
    required this.grenades,
    required this.initialSelectedIds,
  });

  @override
  State<_LanSyncGrenadePickerScreen> createState() =>
      _LanSyncGrenadePickerScreenState();
}

class _LanSyncGrenadePickerScreenState
    extends State<_LanSyncGrenadePickerScreen> {
  late final Set<int> _selectedIds;
  int? _filterType;
  String? _filterMapName;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initialSelectedIds};
  }

  List<Grenade> get _visibleGrenades {
    return widget.grenades.where((grenade) {
      if (_filterType != null && grenade.type != _filterType) {
        return false;
      }
      if (_filterMapName == null) return true;
      grenade.layer.loadSync();
      final layer = grenade.layer.value;
      layer?.map.loadSync();
      final mapName = layer?.map.value?.name.trim() ?? '';
      return mapName == _filterMapName;
    }).toList(growable: false);
  }

  List<_LanSyncMapFilterOption> get _availableMaps {
    final optionsByName = <String, _LanSyncMapFilterOption>{};
    for (final grenade in widget.grenades) {
      grenade.layer.loadSync();
      final layer = grenade.layer.value;
      layer?.map.loadSync();
      final map = layer?.map.value;
      final mapName = map?.name.trim() ?? '';
      if (mapName.isEmpty || optionsByName.containsKey(mapName)) continue;
      optionsByName[mapName] = _LanSyncMapFilterOption(
        name: mapName,
        iconPath: map?.iconPath.trim() ?? '',
      );
    }

    final options = optionsByName.values.toList(growable: false);
    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
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

  void _toggleSelectAllVisible() {
    final visibleIds = _visibleGrenades.map((e) => e.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleGrenades = _visibleGrenades;
    final selectedInVisible =
        visibleGrenades.where((e) => _selectedIds.contains(e.id)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择道具'),
        actions: [
          if (widget.grenades.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectAllVisible,
              icon: Icon(
                visibleGrenades.isNotEmpty &&
                        selectedInVisible == visibleGrenades.length
                    ? Icons.deselect
                    : Icons.select_all,
                size: 18,
              ),
              label: Text(
                visibleGrenades.isNotEmpty &&
                        selectedInVisible == visibleGrenades.length
                    ? '取消全选'
                    : '全选',
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildMapDropdown(),
          _buildTypeFilter(),
          _buildSelectionBar(selectedInVisible, visibleGrenades.length),
          Expanded(
            child: visibleGrenades.isEmpty
                ? const Center(
                    child: Text(
                      '当前筛选下没有道具',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: visibleGrenades.length,
                    itemBuilder: (context, index) {
                      final grenade = visibleGrenades[index];
                      final isSelected = _selectedIds.contains(grenade.id);
                      return SelectableGrenadeListItem(
                        grenade: grenade,
                        selected: isSelected,
                        onChanged: (_) => _toggleSelection(grenade.id),
                        onTap: () => _toggleSelection(grenade.id),
                        onPreview: () {
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
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _selectedIds.toList()),
            icon: const Icon(Icons.check),
            label: Text('确认选择 (${_selectedIds.length})'),
          ),
        ),
      ),
    );
  }

  Widget _buildMapDropdown() {
    final maps = _availableMaps;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DropdownButtonFormField<String?>(
        initialValue: _filterMapName,
        decoration: const InputDecoration(
          labelText: '选择地图',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: _LanSyncMapDropdownLabel(
              icon: Icon(Icons.public, size: 20, color: Colors.orange),
              text: '全部地图',
            ),
          ),
          ...maps.map(
            (map) => DropdownMenuItem<String?>(
              value: map.name,
              child: _LanSyncMapDropdownLabel(
                icon: _LanSyncMapIcon(iconPath: map.iconPath, size: 20),
                text: map.name,
              ),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _filterMapName = value),
      ),
    );
  }

  Widget _buildTypeFilter() {
    const types = [
      (null, '全部', Icons.apps),
      (GrenadeType.smoke, '烟雾', Icons.cloud_outlined),
      (GrenadeType.flash, '闪光', Icons.flash_on_outlined),
      (GrenadeType.molotov, '燃烧', Icons.local_fire_department_outlined),
      (GrenadeType.he, '手雷', Icons.trip_origin),
      (GrenadeType.wallbang, '穿点', Icons.grid_4x4),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types.map((item) {
            final isSelected = _filterType == item.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                onSelected: (_) => setState(() => _filterType = item.$1),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.$3,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(item.$2),
                  ],
                ),
                selectedColor: Colors.orange,
                checkmarkColor: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSelectionBar(int selected, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Checkbox(
            value: total > 0 && selected == total,
            tristate: selected > 0 && selected < total,
            onChanged: (_) => _toggleSelectAllVisible(),
            activeColor: Colors.orange,
          ),
          Text(
            '当前筛选全选 ($selected/$total)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '总计已选 ${_selectedIds.length} 个',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
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

class _LanSyncMapFilterOption {
  final String name;
  final String iconPath;

  const _LanSyncMapFilterOption({
    required this.name,
    required this.iconPath,
  });
}

class _LanSyncMapIcon extends StatelessWidget {
  final String iconPath;
  final double size;

  const _LanSyncMapIcon({
    required this.iconPath,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return MapIcon(path: iconPath, size: size);
  }
}

class _LanSyncMapDropdownLabel extends StatelessWidget {
  final Widget icon;
  final String text;

  const _LanSyncMapDropdownLabel({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
