import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';

import '../models.dart';
import '../models/overlay_snapshot.dart';
import 'settings_service.dart';

class OverlayIpcServer {
  final Isar isar;
  final SettingsService settingsService;
  final VoidCallback? onOverlayHidden;

  HttpServer? _server;
  WebSocket? _socket;
  Process? _process;
  String? _token;
  Completer<void>? _readyCompleter;
  Future<void>? _startingFuture;
  bool _disposed = false;
  int _nextRequestId = 0;
  final Map<int, Completer<void>> _pendingReleaseAcks = {};

  GameMap? _activeMap;
  MapLayer? _activeLayer;
  StreamSubscription<void>? _grenadeWatcher;
  Timer? _snapshotDebounce;

  OverlayIpcServer({
    required this.isar,
    required this.settingsService,
    this.onOverlayHidden,
  });

  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  void setActiveMap(GameMap map, MapLayer layer) {
    _activeMap = map;
    _activeLayer = layer;
    _rebindGrenadeWatcher();
    if (isConnected) {
      _pushCurrentMapSnapshot();
    }
  }

  void clearActiveMap() {
    _grenadeWatcher?.cancel();
    _grenadeWatcher = null;
    _snapshotDebounce?.cancel();
    _activeMap = null;
    _activeLayer = null;
    if (isConnected) {
      _sendRaw({'cmd': 'clear_map'});
    }
  }

  Future<void> ensureRunning() async {
    if (_disposed || isConnected) return;
    if (_startingFuture != null) {
      await _startingFuture;
      return;
    }

    final completer = Completer<void>();
    _startingFuture = completer.future;
    try {
      await _startServerIfNeeded();
      await _spawnOverlayProcess();
      completer.complete();
    } catch (e, stack) {
      debugPrint('[OverlayIpcServer] Failed to start overlay process: $e');
      if (!completer.isCompleted) {
        completer.completeError(e, stack);
      }
      rethrow;
    } finally {
      _startingFuture = null;
    }
  }

  Future<void> showOverlay() async {
    await ensureRunning();
    sendCommand('show_overlay');
  }

  void hideOverlay() {
    if (!isConnected) return;
    sendCommand('hide_overlay');
  }

  void sendCommand(String command, [Map<String, dynamic>? args]) {
    if (!isConnected) return;
    if (command == 'reload_data') {
      _pushCurrentMapSnapshot();
      return;
    }
    _sendRaw({
      'cmd': command,
      if (args != null) 'args': args,
    });
  }

  Future<void> releaseMediaFiles(List<String> paths) async {
    if (!isConnected || paths.isEmpty) return;
    final requestId = ++_nextRequestId;
    final completer = Completer<void>();
    _pendingReleaseAcks[requestId] = completer;
    _sendRaw({
      'cmd': 'release_media',
      'args': {
        'requestId': requestId,
        'paths': paths,
      },
    });
    try {
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } finally {
      _pendingReleaseAcks.remove(requestId);
    }
  }

  void _completePendingReleaseAcks() {
    for (final completer in _pendingReleaseAcks.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingReleaseAcks.clear();
  }

  Future<void> dispose() async {
    _disposed = true;
    _completePendingReleaseAcks();
    _grenadeWatcher?.cancel();
    _grenadeWatcher = null;
    _snapshotDebounce?.cancel();

    final process = _process;
    if (isConnected) {
      _sendRaw({'cmd': 'close'});
      if (process != null) {
        try {
          await process.exitCode.timeout(const Duration(milliseconds: 300));
        } catch (_) {}
      }
    }

    if (process != null) {
      process.kill();
      _process = null;
    }

    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;

    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  Future<void> _startServerIfNeeded() async {
    if (_server != null) return;

    _token = _generateToken();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleHttpRequest);
  }

  void _handleHttpRequest(HttpRequest request) async {
    final token = request.uri.queryParameters['token'];
    if (token != _token || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = socket;

    socket.listen(
      _handleClientMessage,
      onDone: () => _handleSocketClosed(socket),
      onError: (_) => _handleSocketClosed(socket),
      cancelOnError: true,
    );

    _sendRaw({
      'cmd': 'init',
      'args': _buildInitConfig().toJson(),
    });
  }

  Future<void> _spawnOverlayProcess() async {
    final ready = Completer<void>();
    _readyCompleter = ready;

    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--overlay',
        '--port',
        '${_server!.port}',
        '--token',
        _token!,
      ],
    );
    _process = process;

    if (!kReleaseMode) {
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[Overlay] $line'));
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[Overlay:err] $line'));
    }

    unawaited(process.exitCode.then((code) {
      if (_process == process) {
        _process = null;
      }
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('Overlay process exited early with code $code'),
        );
      }
      if (!_disposed) {
        _grenadeWatcher?.cancel();
        _grenadeWatcher = null;
        onOverlayHidden?.call();
      }
    }));

    await ready.future.timeout(const Duration(seconds: 10));
    _rebindGrenadeWatcher();
  }

  void _handleClientMessage(dynamic raw) {
    if (raw is! String) return;
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final event = decoded['event'] as String?;
    final args = decoded['args'] is Map
        ? Map<String, dynamic>.from(decoded['args'] as Map)
        : null;

    switch (event) {
      case 'ready':
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
        }
        break;
      case 'hidden':
        onOverlayHidden?.call();
        break;
      case 'bounds_changed':
        final x = (args?['x'] as num?)?.toDouble();
        final y = (args?['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          unawaited(settingsService.setOverlayPosition(x, y));
        }
        break;
      case 'nav_speed_changed':
        final speed = (args?['speed'] as num?)?.toInt();
        if (speed != null) {
          unawaited(settingsService.setOverlayNavSpeed(speed));
        }
        break;
      case 'media_released':
        final requestId = (args?['requestId'] as num?)?.toInt();
        if (requestId != null) {
          final completer = _pendingReleaseAcks.remove(requestId);
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
        break;
    }
  }

  void _handleSocketClosed(WebSocket closedSocket) {
    if (_socket != closedSocket) return;
    _socket = null;
    _completePendingReleaseAcks();
    _grenadeWatcher?.cancel();
    _grenadeWatcher = null;
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('Overlay socket closed'));
    }
  }

  void _rebindGrenadeWatcher() {
    _grenadeWatcher?.cancel();
    _grenadeWatcher = null;

    if (!isConnected || _activeLayer == null) return;

    final layerId = _activeLayer!.id;
    _grenadeWatcher = isar.grenades
        .filter()
        .layer((q) => q.idEqualTo(layerId))
        .watch(fireImmediately: false)
        .listen((_) {
      _snapshotDebounce?.cancel();
      _snapshotDebounce = Timer(const Duration(milliseconds: 50), () {
        _pushCurrentMapSnapshot();
      });
    });
  }

  void _pushCurrentMapSnapshot() {
    if (!isConnected) return;
    final snapshot = _buildCurrentMapSnapshot();
    if (snapshot == null) {
      _sendRaw({'cmd': 'clear_map'});
    } else {
      _sendRaw({'cmd': 'set_map_snapshot', 'args': snapshot.toJson()});
    }
  }

  OverlayMapSnapshot? _buildCurrentMapSnapshot() {
    final mapId = _activeMap?.id;
    final layerId = _activeLayer?.id;
    if (mapId == null || layerId == null || !isar.isOpen) return null;

    final map = isar.gameMaps.getSync(mapId);
    final layer = isar.mapLayers.getSync(layerId);
    if (map == null || layer == null) return null;

    return OverlayMapSnapshot.fromIsar(map, layer);
  }

  OverlayInitConfig _buildInitConfig() {
    final sizeIndex = settingsService.getOverlaySize();
    final size = SettingsService.calculateSizePixels(sizeIndex);
    final savedX = settingsService.getOverlayX();
    final savedY = settingsService.getOverlayY();
    final legacyParked = savedX != null &&
        savedY != null &&
        (savedX - (1.0 - size.$1)).abs() < 0.5 &&
        (savedY - (1.0 - size.$2)).abs() < 0.5;

    return OverlayInitConfig(
      x: legacyParked ? 100.0 : (savedX ?? 100.0),
      y: legacyParked ? 100.0 : (savedY ?? 100.0),
      sizeIndex: sizeIndex,
      opacity: settingsService.getOverlayOpacity(),
      navSpeedLevel: settingsService.getOverlayNavSpeed(),
      useLegacyIcons: settingsService.getMapMarkerUseEmoji(),
      hotkeys: settingsService.getHotkeys(),
      mapSnapshot: _buildCurrentMapSnapshot(),
    );
  }

  void _sendRaw(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(payload));
  }

  static String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
