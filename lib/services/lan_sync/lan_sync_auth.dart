import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class LanSyncAuth {
  static final Random _random = Random.secure();

  static String generatePairCode() {
    final value = _random.nextInt(1000000);
    return value.toString().padLeft(6, '0');
  }

  static String generateSecret({int bytes = 24}) {
    final data = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(data).replaceAll('=', '');
  }

  static String generateNonce({int bytes = 12}) => generateSecret(bytes: bytes);

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static Future<String> sha256FileHex(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  static String buildSigningPayload({
    required String method,
    required String path,
    required String timestampMs,
    required String nonce,
    required String bodySha256,
    required String peerId,
  }) {
    return [
      method.toUpperCase(),
      path,
      timestampMs,
      nonce,
      bodySha256,
      peerId,
    ].join('\n');
  }

  static String hmacSha256Hex({
    required String secret,
    required String payload,
  }) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(payload)).toString();
  }

  static bool constantTimeEquals(String a, String b) {
    final aa = utf8.encode(a);
    final bb = utf8.encode(b);
    if (aa.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < aa.length; i++) {
      diff |= aa[i] ^ bb[i];
    }
    return diff == 0;
  }
}
