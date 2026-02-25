import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lan_sync_auth.dart';

enum LanReceiveTaskStatus { receiving, pending, importing, imported, failed }

enum LanIncomingTransferRequestStatus { pending, approved, rejected, expired }

class LanIncomingTransferRequest {
  final String id;
  final String fileName;
  final int sizeBytes;
  final DateTime requestedAt;
  final String? remoteAddress;
  final String senderName;
  final String scopeSummary;
  final LanIncomingTransferRequestStatus status;
  final String? message;

  const LanIncomingTransferRequest({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.requestedAt,
    required this.status,
    this.remoteAddress,
    this.senderName = '',
    this.scopeSummary = '',
    this.message,
  });

  LanIncomingTransferRequest copyWith({
    LanIncomingTransferRequestStatus? status,
    String? message,
    bool clearMessage = false,
  }) {
    return LanIncomingTransferRequest(
      id: id,
      fileName: fileName,
      sizeBytes: sizeBytes,
      requestedAt: requestedAt,
      remoteAddress: remoteAddress,
      senderName: senderName,
      scopeSummary: scopeSummary,
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class LanReceivedPackageTask {
  final String id;
  final String filePath;
  final String fileName;
  final int sizeBytes;
  final int bytesReceived;
  final int? expectedBytes;
  final DateTime receivedAt;
  final String? remoteAddress;
  final LanReceiveTaskStatus status;
  final String? message;

  const LanReceivedPackageTask({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    this.bytesReceived = 0,
    this.expectedBytes,
    required this.receivedAt,
    required this.status,
    this.remoteAddress,
    this.message,
  });

  LanReceivedPackageTask copyWith({
    LanReceiveTaskStatus? status,
    String? message,
    bool clearMessage = false,
    int? sizeBytes,
    int? bytesReceived,
    int? expectedBytes,
    bool clearExpectedBytes = false,
  }) {
    return LanReceivedPackageTask(
      id: id,
      filePath: filePath,
      fileName: fileName,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      expectedBytes:
          clearExpectedBytes ? null : (expectedBytes ?? this.expectedBytes),
      receivedAt: receivedAt,
      remoteAddress: remoteAddress,
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  double? get progress {
    final total = expectedBytes;
    if (total == null || total <= 0) return null;
    final p = bytesReceived / total;
    if (p.isNaN) return null;
    return p.clamp(0.0, 1.0);
  }
}

class LanSyncReceiveController extends ChangeNotifier {
  final String _localDeviceId = 'dev_${LanSyncAuth.generateSecret(bytes: 9)}';
  HttpServer? _server;
  bool _disposed = false;
  bool _isStarting = false;
  String? _lastError;
  final List<String> _localIps = [];
  final List<LanReceivedPackageTask> _tasks = [];
  final List<LanIncomingTransferRequest> _incomingRequests = [];
  final Map<String, String> _trustedPeerSecrets = <String, String>{};
  final Map<String, int> _nonceSeenAt = <String, int>{};
  String _localDeviceName = Platform.localHostname;
  bool _requireAuthForUpload = false;
  String? _activePairCode;
  int? _activePairCodeExpireAtMs;

  bool get isStarting => _isStarting;
  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get lastError => _lastError;
  String get localDeviceId => _localDeviceId;
  String get localDeviceName => _localDeviceName;
  bool get requireAuthForUpload => _requireAuthForUpload;
  String? get activePairCode => _activePairCode;
  DateTime? get activePairCodeExpireAt => _activePairCodeExpireAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_activePairCodeExpireAtMs!);
  List<String> get localIps => List.unmodifiable(_localIps);
  List<LanReceivedPackageTask> get tasks => List.unmodifiable(_tasks);
  List<LanIncomingTransferRequest> get incomingRequests =>
      List.unmodifiable(_incomingRequests);
  int get trustedPeerCount => _trustedPeerSecrets.length;

  String get healthPath => '/v1/health';
  String get pairPath => '/v1/pair/request';
  String get transferRequestPath => '/v1/transfer/request';
  String get transferRequestStatusPath => '/v1/transfer/request_status';
  String get uploadPath => '/v1/transfer/package';

  void setLocalDeviceName(String name) {
    final next = name.trim();
    if (next.isEmpty || next == _localDeviceName) return;
    _localDeviceName = next;
    notifyListeners();
  }

  void setRequireAuthForUpload(bool value) {
    if (_requireAuthForUpload == value) return;
    _requireAuthForUpload = value;
    notifyListeners();
  }

  void setTrustedPeerSecrets(Map<String, String> peerSecretByPeerId) {
    _trustedPeerSecrets
      ..clear()
      ..addEntries(peerSecretByPeerId.entries.where(
        (e) => e.key.trim().isNotEmpty && e.value.trim().isNotEmpty,
      ));
    notifyListeners();
  }

  String issuePairCode({Duration ttl = const Duration(minutes: 5)}) {
    _activePairCode = LanSyncAuth.generatePairCode();
    _activePairCodeExpireAtMs = DateTime.now().add(ttl).millisecondsSinceEpoch;
    notifyListeners();
    return _activePairCode!;
  }

  void clearPairCode() {
    _activePairCode = null;
    _activePairCodeExpireAtMs = null;
    notifyListeners();
  }

  Future<void> refreshLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final next = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          if (addr.type != InternetAddressType.IPv4) continue;
          next.add(addr.address);
        }
      }
      _localIps
        ..clear()
        ..addAll(next.toList()..sort());
      notifyListeners();
    } catch (e) {
      _lastError = '读取本机地址失败: $e';
      notifyListeners();
    }
  }

  Future<void> start({int preferredPort = 39527}) async {
    if (isRunning || _isStarting) return;

    _isStarting = true;
    _lastError = null;
    notifyListeners();

    try {
      HttpServer? server;
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          preferredPort,
          shared: true,
        );
      } on SocketException {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: true,
        );
      }

      _server = server;
      _server!.listen(
        (request) => unawaited(_handleRequest(request)),
        onError: (Object e, StackTrace st) {
          _lastError = '接收服务异常: $e';
          notifyListeners();
        },
      );

      await refreshLocalIps();
    } catch (e) {
      _lastError = '启动接收服务失败: $e';
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == healthPath) {
        _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'service': 'grenade_helper_lan_sync_receiver',
          'port': port,
          'deviceId': _localDeviceId,
          'deviceName': _localDeviceName,
          'requireAuthForUpload': _requireAuthForUpload,
          'trustedPeerCount': _trustedPeerSecrets.length,
          'time': DateTime.now().toIso8601String(),
        });
        return;
      }

      if (request.method == 'POST' && path == pairPath) {
        await _handlePairRequest(request);
        return;
      }

      if (request.method == 'POST' && path == transferRequestPath) {
        await _handleTransferRequest(request);
        return;
      }

      if (request.method == 'GET' && path == transferRequestStatusPath) {
        await _handleTransferRequestStatus(request);
        return;
      }

      if (request.method == 'POST' && path == uploadPath) {
        await _handlePackageUpload(request);
        return;
      }

      _writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'not_found',
      });
    } catch (e) {
      _lastError = '处理请求失败: $e';
      notifyListeners();
      try {
        _writeJson(request.response, HttpStatus.internalServerError, {
          'ok': false,
          'error': 'internal_error',
          'message': '$e',
        });
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  bool _hasValidPairCode(String code) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_activePairCode == null || _activePairCodeExpireAtMs == null) {
      return false;
    }
    if (now > _activePairCodeExpireAtMs!) {
      clearPairCode();
      return false;
    }
    return _activePairCode == code.trim();
  }

  Future<void> _handlePairRequest(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        throw const FormatException('bad_body');
      }
      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'bad_json',
      });
      return;
    }

    final pairCode = (body['pairCode'] as String? ?? '').trim();
    final peerId = (body['peerId'] as String? ?? '').trim();
    final deviceName = (body['deviceName'] as String? ?? '').trim();

    if (pairCode.isEmpty || peerId.isEmpty) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'missing_fields',
      });
      return;
    }
    if (!_hasValidPairCode(pairCode)) {
      _writeJson(request.response, HttpStatus.unauthorized, {
        'ok': false,
        'error': 'invalid_pair_code',
      });
      return;
    }

    final secret = LanSyncAuth.generateSecret(bytes: 24);
    _trustedPeerSecrets[peerId] = secret;
    notifyListeners();

    _writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'peerId': peerId,
      'sharedSecret': secret,
      'remoteDeviceId': _localDeviceId,
      'remoteDeviceName': _localDeviceName,
      'acceptedAt': DateTime.now().toIso8601String(),
      'clientDeviceName': deviceName,
    });
  }

  void _cleanupNonceCache() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiryBefore = now - const Duration(minutes: 10).inMilliseconds;
    _nonceSeenAt.removeWhere((_, ts) => ts < expiryBefore);
  }

  String? _verifyUploadSignature({
    required String method,
    required String path,
    required List<int> bodyBytes,
    required HttpHeaders headers,
  }) {
    final peerId = headers.value('x-lan-peer-id')?.trim() ?? '';
    final tsRaw = headers.value('x-lan-ts')?.trim() ?? '';
    final nonce = headers.value('x-lan-nonce')?.trim() ?? '';
    final bodyShaHeader = headers.value('x-lan-body-sha256')?.trim() ?? '';
    final sign = headers.value('x-lan-sign')?.trim() ?? '';

    if (peerId.isEmpty ||
        tsRaw.isEmpty ||
        nonce.isEmpty ||
        bodyShaHeader.isEmpty ||
        sign.isEmpty) {
      return 'missing_signature_headers';
    }

    final ts = int.tryParse(tsRaw);
    if (ts == null) return 'invalid_timestamp';
    final now = DateTime.now().millisecondsSinceEpoch;
    final skew = (now - ts).abs();
    if (skew > const Duration(minutes: 5).inMilliseconds) {
      return 'timestamp_out_of_range';
    }

    _cleanupNonceCache();
    final nonceKey = '$peerId|$nonce';
    if (_nonceSeenAt.containsKey(nonceKey)) {
      return 'replayed_nonce';
    }

    final secret = _trustedPeerSecrets[peerId];
    if (secret == null || secret.trim().isEmpty) {
      return 'unknown_peer';
    }

    final actualBodySha = LanSyncAuth.sha256Hex(bodyBytes);
    if (!LanSyncAuth.constantTimeEquals(bodyShaHeader, actualBodySha)) {
      return 'body_hash_mismatch';
    }

    final payload = LanSyncAuth.buildSigningPayload(
      method: method,
      path: path,
      timestampMs: tsRaw,
      nonce: nonce,
      bodySha256: bodyShaHeader,
      peerId: peerId,
    );
    final expectedSign =
        LanSyncAuth.hmacSha256Hex(secret: secret, payload: payload);
    if (!LanSyncAuth.constantTimeEquals(sign, expectedSign)) {
      return 'bad_signature';
    }

    _nonceSeenAt[nonceKey] = now;
    return null;
  }

  LanIncomingTransferRequest? _findIncomingRequest(String id) {
    for (final r in _incomingRequests) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> approveIncomingRequest(String requestId) async {
    final index = _incomingRequests.indexWhere((e) => e.id == requestId);
    if (index < 0) return;
    _incomingRequests[index] = _incomingRequests[index].copyWith(
      status: LanIncomingTransferRequestStatus.approved,
      clearMessage: true,
    );
    notifyListeners();
  }

  Future<void> rejectIncomingRequest(String requestId,
      {String? message}) async {
    final index = _incomingRequests.indexWhere((e) => e.id == requestId);
    if (index < 0) return;
    _incomingRequests[index] = _incomingRequests[index].copyWith(
      status: LanIncomingTransferRequestStatus.rejected,
      message: message ?? '接收方已拒绝',
    );
    notifyListeners();
  }

  Future<void> _handleTransferRequest(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) throw const FormatException('bad_body');
      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'bad_json',
      });
      return;
    }

    final fileName = _normalizePackageFileName(body['fileName'] as String?);
    final sizeBytes = body['sizeBytes'] as int? ?? 0;
    final senderName = (body['senderName'] as String? ?? '').trim();
    final scopeSummary = (body['scopeSummary'] as String? ?? '').trim();
    if (sizeBytes <= 0) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'invalid_size',
      });
      return;
    }

    final id = 'req_${DateTime.now().microsecondsSinceEpoch}';
    final incoming = LanIncomingTransferRequest(
      id: id,
      fileName: fileName,
      sizeBytes: sizeBytes,
      requestedAt: DateTime.now(),
      remoteAddress: request.connectionInfo?.remoteAddress.address,
      senderName: senderName,
      scopeSummary: scopeSummary,
      status: LanIncomingTransferRequestStatus.pending,
    );
    _incomingRequests.insert(0, incoming);
    if (_incomingRequests.length > 100) {
      _incomingRequests.removeRange(100, _incomingRequests.length);
    }
    notifyListeners();

    _writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'requestId': id,
      'status': 'pending',
    });
  }

  Future<void> _handleTransferRequestStatus(HttpRequest request) async {
    final id = (request.uri.queryParameters['id'] ?? '').trim();
    if (id.isEmpty) {
      _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'missing_id',
      });
      return;
    }
    final incoming = _findIncomingRequest(id);
    if (incoming == null) {
      _writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'request_not_found',
      });
      return;
    }
    _writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'requestId': incoming.id,
      'status': incoming.status.name,
      'message': incoming.message,
    });
  }

  Future<void> _handlePackageUpload(HttpRequest request) async {
    final incomingRequestId =
        (request.headers.value('x-transfer-request-id') ?? '').trim();
    if (incomingRequestId.isEmpty) {
      _writeJson(request.response, HttpStatus.preconditionFailed, {
        'ok': false,
        'error': 'missing_transfer_request_id',
      });
      return;
    }
    final incoming = _findIncomingRequest(incomingRequestId);
    if (incoming == null) {
      _writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'request_not_found',
      });
      return;
    }
    if (incoming.status == LanIncomingTransferRequestStatus.rejected) {
      _writeJson(request.response, HttpStatus.forbidden, {
        'ok': false,
        'error': 'request_rejected',
        'message': incoming.message,
      });
      return;
    }
    if (incoming.status != LanIncomingTransferRequestStatus.approved) {
      _writeJson(request.response, HttpStatus.preconditionFailed, {
        'ok': false,
        'error': 'request_not_approved',
      });
      return;
    }

    final fileNameParam = request.uri.queryParameters['filename'] ??
        request.headers.value('x-file-name');
    final fileName = _normalizePackageFileName(fileNameParam);

    final inboxDir = await _getInboxDir();
    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    final filePath = p.join(inboxDir.path, '${taskId}_$fileName');
    final file = File(filePath);
    final expectedBytes = incoming.sizeBytes > 0
        ? incoming.sizeBytes
        : int.tryParse(
            request.headers.value(HttpHeaders.contentLengthHeader) ?? '');
    final signedBodyMode = _requireAuthForUpload ||
        (request.headers.value('x-lan-sign')?.trim().isNotEmpty == true);
    final task = LanReceivedPackageTask(
      id: taskId,
      filePath: filePath,
      fileName: fileName,
      sizeBytes: 0,
      bytesReceived: 0,
      expectedBytes: expectedBytes,
      receivedAt: DateTime.now(),
      remoteAddress: request.connectionInfo?.remoteAddress.address,
      status: LanReceiveTaskStatus.receiving,
      message: '传输中...',
    );
    _tasks.insert(0, task);
    notifyListeners();

    var receivedBytes = 0;
    final sink = file.openWrite();
    List<int>? bufferedForSign;
    if (signedBodyMode) {
      bufferedForSign = <int>[];
    }
    try {
      await for (final chunk in request) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (bufferedForSign != null) {
          bufferedForSign.addAll(chunk);
        }
        final index = _tasks.indexWhere((e) => e.id == taskId);
        if (index >= 0) {
          _tasks[index] = _tasks[index].copyWith(
            bytesReceived: receivedBytes,
            sizeBytes: receivedBytes,
          );
          notifyListeners();
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (signedBodyMode) {
      final bytes = bufferedForSign ?? const <int>[];
      final verifyError = _verifyUploadSignature(
        method: request.method,
        path: request.uri.path,
        bodyBytes: bytes,
        headers: request.headers,
      );
      if (verifyError != null) {
        final index = _tasks.indexWhere((e) => e.id == taskId);
        if (index >= 0) {
          _tasks[index] = _tasks[index].copyWith(
            status: LanReceiveTaskStatus.failed,
            message: verifyError,
            sizeBytes: receivedBytes,
            bytesReceived: receivedBytes,
          );
          notifyListeners();
        }
        _writeJson(request.response, HttpStatus.unauthorized, {
          'ok': false,
          'error': verifyError,
        });
        return;
      }
    }

    final size = await file.length();
    if (size <= 0) {
      if (await file.exists()) {
        await file.delete();
      }
      final index = _tasks.indexWhere((e) => e.id == taskId);
      if (index >= 0) {
        _tasks[index] = _tasks[index].copyWith(
          status: LanReceiveTaskStatus.failed,
          message: '空文件',
        );
        notifyListeners();
      }
      _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'empty_file',
      });
      return;
    }

    final taskIndex = _tasks.indexWhere((e) => e.id == taskId);
    if (taskIndex >= 0) {
      _tasks[taskIndex] = _tasks[taskIndex].copyWith(
        status: LanReceiveTaskStatus.pending,
        message: '等待导入',
        sizeBytes: size,
        bytesReceived: size,
      );
      notifyListeners();
    }

    _writeJson(request.response, HttpStatus.ok, {
      'ok': true,
      'transferRequestId': incomingRequestId,
      'taskId': taskId,
      'fileName': fileName,
      'sizeBytes': size,
      'signed': signedBodyMode,
    });
  }

  Future<Directory> _getInboxDir() async {
    final tempDir = await getTemporaryDirectory();
    final inbox = Directory(p.join(tempDir.path, 'lan_sync_inbox'));
    if (!await inbox.exists()) {
      await inbox.create(recursive: true);
    }
    return inbox;
  }

  String _normalizePackageFileName(String? fileName) {
    final raw = (fileName ?? '').trim();
    final fallback = 'sync_package.cs2pkg';
    final base = raw.isEmpty ? fallback : p.basename(raw);
    final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (sanitized.toLowerCase().endsWith('.cs2pkg')) {
      return sanitized;
    }
    return '$sanitized.cs2pkg';
  }

  Future<void> markTaskStatus(
    String taskId,
    LanReceiveTaskStatus status, {
    String? message,
    bool clearMessage = false,
  }) async {
    final index = _tasks.indexWhere((e) => e.id == taskId);
    if (index < 0) return;
    _tasks[index] = _tasks[index].copyWith(
      status: status,
      message: message,
      clearMessage: clearMessage,
    );
    notifyListeners();
  }

  Future<void> removeTask(String taskId, {bool deleteFile = true}) async {
    final index = _tasks.indexWhere((e) => e.id == taskId);
    if (index < 0) return;
    final task = _tasks.removeAt(index);
    if (deleteFile) {
      final file = File(task.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    notifyListeners();
  }

  Future<void> clearImportedTasks() async {
    final imported = _tasks
        .where((e) => e.status == LanReceiveTaskStatus.imported)
        .map((e) => e.id)
        .toList(growable: false);
    for (final id in imported) {
      await removeTask(id);
    }
  }

  void _writeJson(
      HttpResponse response, int statusCode, Map<String, dynamic> body) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final server = _server;
    _server = null;
    if (server != null) {
      unawaited(server.close(force: true));
    }
    super.dispose();
  }
}
