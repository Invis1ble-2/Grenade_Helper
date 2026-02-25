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

  const LanSyncTransferRequestResponse({
    required this.ok,
    required this.statusCode,
    required this.body,
    this.requestId = '',
    this.status = '',
    this.message,
  });
}

class LanSyncTransferClient {
  static const String pairPath = '/v1/pair/request';
  static const String transferRequestPath = '/v1/transfer/request';
  static const String transferRequestStatusPath = '/v1/transfer/request_status';

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
    String path = transferRequestPath,
  }) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'senderName': senderName,
        'scopeSummary': scopeSummary,
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
