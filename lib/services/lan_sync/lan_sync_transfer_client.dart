import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'lan_sync_auth.dart';

class LanSyncTransferResponse {
  final int statusCode;
  final String body;

  const LanSyncTransferResponse({
    required this.statusCode,
    required this.body,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class LanSyncPairResponse {
  final bool ok;
  final int statusCode;
  final String body;
  final String peerId;
  final String sharedSecret;
  final String remoteDeviceId;
  final String remoteDeviceName;

  const LanSyncPairResponse({
    required this.ok,
    required this.statusCode,
    required this.body,
    this.peerId = '',
    this.sharedSecret = '',
    this.remoteDeviceId = '',
    this.remoteDeviceName = '',
  });
}

class LanSyncTransferRequestResponse {
  final bool ok;
  final int statusCode;
  final String body;
  final String requestId;
  final String status;
  final String? message;
  final String syncMode;
  final String scopeType;
  final List<String> scopeMapKeys;
  final String syncEnvelopeId;
  final Map<String, dynamic>? importSummary;

  const LanSyncTransferRequestResponse({
    required this.ok,
    required this.statusCode,
    required this.body,
    this.requestId = '',
    this.status = '',
    this.message,
    this.syncMode = '',
    this.scopeType = '',
    this.scopeMapKeys = const [],
    this.syncEnvelopeId = '',
    this.importSummary,
  });
}

class LanSyncRemoteManifestItem {
  final String digest;
  final int updatedAtMs;
  final String mapName;

  const LanSyncRemoteManifestItem({
    required this.digest,
    required this.updatedAtMs,
    required this.mapName,
  });
}

class LanSyncRemoteManifestResponse {
  final bool ok;
  final int statusCode;
  final String body;
  final int manifestSchemaVersion;
  final int generatedAtMs;
  final Map<String, LanSyncRemoteManifestItem> grenades;
  final Map<String, LanSyncRemoteManifestItem> tags;
  final Map<String, LanSyncRemoteManifestItem> areas;
  final Map<String, LanSyncRemoteManifestItem> favoriteFolders;
  final Map<String, LanSyncRemoteManifestItem> impactGroups;

  const LanSyncRemoteManifestResponse({
    required this.ok,
    required this.statusCode,
    required this.body,
    this.manifestSchemaVersion = 0,
    this.generatedAtMs = 0,
    this.grenades = const {},
    this.tags = const {},
    this.areas = const {},
    this.favoriteFolders = const {},
    this.impactGroups = const {},
  });
}

class LanSyncTransferClient {
  static const String pairPath = '/v1/pair/request';
  static const String transferRequestPath = '/v1/transfer/request';
  static const String transferRequestStatusPath = '/v1/transfer/request_status';
  static const String transferManifestPath = '/v1/transfer/manifest';

  static Future<LanSyncPairResponse> pairRequest({
    required String host,
    required int port,
    required String pairCode,
    required String localPeerId,
    required String localDeviceName,
    String path = pairPath,
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: path,
    );
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final payload = {
        'pairCode': pairCode,
        'peerId': localPeerId,
        'deviceName': localDeviceName,
      };
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final isOk = response.statusCode >= 200 && response.statusCode < 300;
      if (!isOk) {
        return LanSyncPairResponse(
          ok: false,
          statusCode: response.statusCode,
          body: body,
        );
      }
      try {
        final map = jsonDecode(body);
        if (map is Map) {
          return LanSyncPairResponse(
            ok: true,
            statusCode: response.statusCode,
            body: body,
            peerId: (map['peerId'] as String? ?? '').trim(),
            sharedSecret: (map['sharedSecret'] as String? ?? '').trim(),
            remoteDeviceId: (map['remoteDeviceId'] as String? ?? '').trim(),
            remoteDeviceName: (map['remoteDeviceName'] as String? ?? '').trim(),
          );
        }
      } catch (_) {}
      return LanSyncPairResponse(
        ok: false,
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<LanSyncTransferResponse> sendPackage({
    required String host,
    required int port,
    required String filePath,
    String path = '/v1/transfer/package',
    String? peerId,
    String? sharedSecret,
    String? transferRequestId,
    void Function(int sentBytes, int totalBytes)? onSendProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('同步包不存在: $filePath');
    }

    final fileName = p.basename(filePath);
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: path,
      queryParameters: {'filename': fileName},
    );

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.binary;
      request.headers.set('x-file-name', fileName);
      request.headers.set('x-sync-schema', '3');
      if (transferRequestId != null && transferRequestId.trim().isNotEmpty) {
        request.headers.set('x-transfer-request-id', transferRequestId.trim());
      }
      final signed = (peerId != null && peerId.trim().isNotEmpty) &&
          (sharedSecret != null && sharedSecret.trim().isNotEmpty);
      if (signed) {
        final ts = DateTime.now().millisecondsSinceEpoch.toString();
        final nonce = LanSyncAuth.generateNonce();
        final bodySha = await LanSyncAuth.sha256FileHex(filePath);
        final payload = LanSyncAuth.buildSigningPayload(
          method: 'POST',
          path: uri.path,
          timestampMs: ts,
          nonce: nonce,
          bodySha256: bodySha,
          peerId: peerId.trim(),
        );
        final sign = LanSyncAuth.hmacSha256Hex(
          secret: sharedSecret.trim(),
          payload: payload,
        );
        request.headers
          ..set('x-lan-peer-id', peerId.trim())
          ..set('x-lan-ts', ts)
          ..set('x-lan-nonce', nonce)
          ..set('x-lan-body-sha256', bodySha)
          ..set('x-lan-sign', sign);
      }
      final totalBytes = await file.length();
      var sentBytes = 0;
      await for (final chunk in file.openRead()) {
        request.add(chunk);
        sentBytes += chunk.length;
        onSendProgress?.call(sentBytes, totalBytes);
      }

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return LanSyncTransferResponse(
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<LanSyncTransferRequestResponse> requestTransfer({
    required String host,
    required int port,
    required String fileName,
    required int sizeBytes,
    String senderName = '',
    String scopeSummary = '',
    String syncMode = 'full',
    String scopeType = 'all',
    List<String> scopeMapKeys = const [],
    String? syncEnvelopeId,
    String? senderNodeId,
    String? receiverNodeId,
    int packageSchemaVersion = 3,
    String path = transferRequestPath,
  }) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final normalizedMapKeys = scopeMapKeys
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      request.write(jsonEncode({
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'senderName': senderName,
        'scopeSummary': scopeSummary,
        'syncMode': syncMode,
        'scopeType': scopeType,
        'scopeMapKeys': normalizedMapKeys,
        'syncEnvelopeId': (syncEnvelopeId ?? '').trim(),
        'senderNodeId': (senderNodeId ?? '').trim(),
        'receiverNodeId': (receiverNodeId ?? '').trim(),
        'packageSchemaVersion': packageSchemaVersion,
      }));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          return LanSyncTransferRequestResponse(
            ok: (decoded['ok'] == true) &&
                response.statusCode >= 200 &&
                response.statusCode < 300,
            statusCode: response.statusCode,
            body: body,
            requestId: (decoded['requestId'] as String? ?? '').trim(),
            status: (decoded['status'] as String? ?? '').trim(),
            message: decoded['message'] as String?,
            syncMode: (decoded['syncMode'] as String? ?? '').trim(),
            scopeType: (decoded['scopeType'] as String? ?? '').trim(),
            scopeMapKeys: ((decoded['scopeMapKeys'] as List?) ?? const [])
                .map((e) => '$e'.trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false),
            syncEnvelopeId: (decoded['syncEnvelopeId'] as String? ?? '').trim(),
            importSummary: decoded['importSummary'] is Map
                ? Map<String, dynamic>.from(
                    decoded['importSummary'] as Map<dynamic, dynamic>)
                : null,
          );
        }
      } catch (_) {}
      return LanSyncTransferRequestResponse(
        ok: false,
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, LanSyncRemoteManifestItem> _decodeManifestItemMap(
    Object? raw, {
    String? defaultMapName,
  }) {
    if (raw is! Map) return const {};
    final result = <String, LanSyncRemoteManifestItem>{};
    for (final entry in Map<String, dynamic>.from(raw).entries) {
      final key = entry.key.trim();
      if (key.isEmpty || entry.value is! Map) continue;
      final value = Map<String, dynamic>.from(entry.value as Map);
      final digest = (value['digest'] as String? ?? '').trim();
      final updatedAtMs = value['updatedAtMs'] as int? ?? 0;
      final mapName =
          (value['mapName'] as String? ?? defaultMapName ?? '').trim();
      if (digest.isEmpty) continue;
      result[key] = LanSyncRemoteManifestItem(
        digest: digest,
        updatedAtMs: updatedAtMs,
        mapName: mapName,
      );
    }
    return result;
  }

  static Future<LanSyncRemoteManifestResponse> fetchRemoteManifest({
    required String host,
    required int port,
    required String scopeType,
    List<String> scopeMapKeys = const [],
    String? senderNodeId,
    String? receiverNodeId,
    int manifestSchemaVersion = 1,
    String path = transferManifestPath,
  }) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'scopeType': scopeType.trim(),
        'scopeMapKeys': scopeMapKeys
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false),
        'senderNodeId': (senderNodeId ?? '').trim(),
        'receiverNodeId': (receiverNodeId ?? '').trim(),
        'manifestSchemaVersion': manifestSchemaVersion,
      }));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final isOk = response.statusCode >= 200 && response.statusCode < 300;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final grenades = <String, LanSyncRemoteManifestItem>{};
          final grenadesByMap = decoded['grenadesByMap'];
          if (grenadesByMap is Map) {
            for (final mapEntry
                in Map<String, dynamic>.from(grenadesByMap).entries) {
              final mapName = mapEntry.key.trim();
              grenades.addAll(_decodeManifestItemMap(
                mapEntry.value,
                defaultMapName: mapName,
              ));
            }
          }
          final entitiesByType = decoded['entitiesByType'];
          final entities = entitiesByType is Map
              ? Map<String, dynamic>.from(entitiesByType)
              : const <String, dynamic>{};
          return LanSyncRemoteManifestResponse(
            ok: (decoded['ok'] == true) && isOk,
            statusCode: response.statusCode,
            body: body,
            manifestSchemaVersion:
                decoded['manifestSchemaVersion'] as int? ?? 0,
            generatedAtMs: decoded['generatedAtMs'] as int? ?? 0,
            grenades: grenades,
            tags: _decodeManifestItemMap(
              entities['tag'],
            ),
            areas: _decodeManifestItemMap(
              entities['area'],
            ),
            favoriteFolders: _decodeManifestItemMap(
              entities['favoriteFolder'],
            ),
            impactGroups: _decodeManifestItemMap(
              entities['impactGroup'],
            ),
          );
        }
      } catch (_) {}
      return LanSyncRemoteManifestResponse(
        ok: false,
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<LanSyncTransferRequestResponse> getTransferRequestStatus({
    required String host,
    required int port,
    required String requestId,
    String path = transferRequestStatusPath,
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: path,
      queryParameters: {'id': requestId},
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          return LanSyncTransferRequestResponse(
            ok: (decoded['ok'] == true) &&
                response.statusCode >= 200 &&
                response.statusCode < 300,
            statusCode: response.statusCode,
            body: body,
            requestId: (decoded['requestId'] as String? ?? '').trim(),
            status: (decoded['status'] as String? ?? '').trim(),
            message: decoded['message'] as String?,
            syncMode: (decoded['syncMode'] as String? ?? '').trim(),
            scopeType: (decoded['scopeType'] as String? ?? '').trim(),
            scopeMapKeys: ((decoded['scopeMapKeys'] as List?) ?? const [])
                .map((e) => '$e'.trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false),
            syncEnvelopeId: (decoded['syncEnvelopeId'] as String? ?? '').trim(),
            importSummary: decoded['importSummary'] is Map
                ? Map<String, dynamic>.from(
                    decoded['importSummary'] as Map<dynamic, dynamic>)
                : null,
          );
        }
      } catch (_) {}
      return LanSyncTransferRequestResponse(
        ok: false,
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }
}
