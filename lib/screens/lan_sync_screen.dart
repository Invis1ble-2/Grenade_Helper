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
import '../services/lan_sync/lan_sync_mdns_service.dart';
import '../services/lan_sync/lan_sync_receive_controller.dart';
import '../services/lan_sync/lan_sync_transfer_client.dart';
import 'import_preview_screen.dart';

enum _LanSendScope { all, map, grenades }

class LanSyncScreen extends ConsumerStatefulWidget {
  const LanSyncScreen({super.key});

  @override
  ConsumerState<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends ConsumerState<LanSyncScreen> {
  late final LanSyncReceiveController _receiveController;
  late final LanSyncDiscoveryService _discoveryService;
  late final LanSyncMdnsService _mdnsService;
  late final LanSyncLocalStore _localStore;
  late final TextEditingController _targetHostController;
  late final TextEditingController _targetPortController;
  bool _isLoadingLocal = true;
  bool _isScanningDevices = false;
  bool _isSendingAll = false;
  bool _isWaitingForApproval = false;
  double? _sendProgress;
  String _sendProgressLabel = '';
  _LanSendScope _sendScope = _LanSendScope.all;
  GameMap? _selectedMapForSend;
  List<Grenade> _selectedGrenadesForSend = const [];
  List<LanDiscoveryDevice> _discoveredDevices = const [];
  List<LanSyncMdnsDevice> _mdnsDiscoveredDevices = const [];
  final Set<String> _seenReceivedTaskIds = <String>{};
  final Set<String> _handledIncomingRequestDialogs = <String>{};

  @override
  void initState() {
    super.initState();
    _receiveController = LanSyncReceiveController();
    _receiveController.setLocalDeviceName(_buildEphemeralDeviceName());
    _receiveController.addListener(_onReceiveControllerChanged);
    _discoveryService = LanSyncDiscoveryService();
    _mdnsService = LanSyncMdnsService();
    _localStore = LanSyncLocalStore();
    _targetHostController = TextEditingController();
    _targetPortController = TextEditingController(text: '39527');
    unawaited(_receiveController.refreshLocalIps());
    unawaited(_loadLocalState());
  }

  @override
  void dispose() {
    _receiveController.removeListener(_onReceiveControllerChanged);
    _targetHostController.dispose();
    _targetPortController.dispose();
    _receiveController.dispose();
    unawaited(_mdnsService.dispose());
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
            if (req.scopeSummary.isNotEmpty) Text('范围：${req.scopeSummary}'),
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
    if (_isScanningDevices) return;
    setState(() => _isScanningDevices = true);
    try {
      if (_receiveController.localIps.isEmpty) {
        await _receiveController.refreshLocalIps();
      }
      final localIps = _receiveController.localIps;
      final mdnsResults = (await _mdnsService.discoverOnce())
          .where((d) => !_isSelfDiscoveredDevice(
                host: d.host,
                deviceId: d.deviceId,
                localIps: localIps,
              ))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _mdnsDiscoveredDevices = mdnsResults;
      });
      await _appendHistory(
        category: 'system',
        title: 'mDNS 扫描完成',
        detail: '发现 ${mdnsResults.length} 台设备',
        success: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mDNS 扫描完成：发现 ${mdnsResults.length} 台设备')),
      );
    } catch (e) {
      await _appendHistory(
        category: 'system',
        title: 'mDNS 扫描失败',
        detail: '$e',
        success: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mDNS 扫描失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanningDevices = false);
      }
    }
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

  Future<void> _sendAllToTarget() async {
    final host = _targetHostController.text.trim();
    final port = _parsedTargetPort;
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
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

    setState(() {
      _isSendingAll = true;
      _isWaitingForApproval = false;
      _sendProgress = null;
      _sendProgressLabel = '';
    });
    String? packagePath;
    try {
      final isar = ref.read(isarProvider);
      final dataService = DataService(isar);
      switch (_sendScope) {
        case _LanSendScope.all:
          packagePath =
              await dataService.buildLanSyncPackageToTemp(scopeType: 2);
          break;
        case _LanSendScope.map:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: 1,
            singleMap: _selectedMapForSend!,
          );
          break;
        case _LanSendScope.grenades:
          packagePath = await dataService.buildLanSyncPackageToTemp(
            scopeType: 2,
            explicitGrenades: _selectedGrenadesForSend,
          );
          break;
      }

      final pkgFile = File(packagePath);
      final fileName = pkgFile.uri.pathSegments.isEmpty
          ? 'lan_sync_data.cs2pkg'
          : pkgFile.uri.pathSegments.last;
      final fileSize = await pkgFile.length();
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

      await _appendHistory(
        category: 'send',
        title: response.isSuccess ? '发送成功' : '发送失败',
        detail:
            '$host:$port · ${_currentScopeSummary()} · HTTP ${response.statusCode}',
        success: response.isSuccess,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.isSuccess
              ? '发送成功（HTTP ${response.statusCode}）'
              : '发送失败（HTTP ${response.statusCode}）: ${_friendlySendErrorBody(response.body)}'),
          backgroundColor: response.isSuccess ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      await _appendHistory(
        category: 'send',
        title: '发送失败',
        detail: '$host:$port · ${_currentScopeSummary()} · $e',
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
        final p = _receiveController.port;
        if (p != null) {
          try {
            await _mdnsService.startBroadcast(
              deviceName: _receiveController.localDeviceName,
              port: p,
              deviceId: _receiveController.localDeviceId,
            );
          } catch (e) {
            await _appendHistory(
              category: 'system',
              title: 'mDNS 广播启动失败',
              detail: '$e',
              success: false,
            );
          }
        }
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
    await _mdnsService.stopBroadcast();
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
    final file = File(task.filePath);
    if (!await file.exists()) {
      await _receiveController.markTaskStatus(
        task.id,
        LanReceiveTaskStatus.failed,
        message: '文件不存在，可能已被系统清理',
      );
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
                  onPressed: _isScanningDevices ? null : _scanDevicesBySubnet,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('备用扫描方式'),
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
                      if (_mdnsDiscoveredDevices.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('暂无 mDNS 结果，点击“mDNS扫描”开始发现。'),
                        )
                      else
                        ..._mdnsDiscoveredDevices.map((d) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.travel_explore),
                              title: Text(
                                d.deviceName.isEmpty ? d.host : d.deviceName,
                              ),
                              subtitle: Text('${d.host}:${d.port}'),
                              onTap: _isSendingAll
                                  ? null
                                  : () => _sendToHostPort(d.host, d.port),
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
                      const SizedBox(height: 8),
                      Text(
                        '备用扫描结果',
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
                          child: const Text('暂无结果。需要时点击“网段备用”进行探测。'),
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
