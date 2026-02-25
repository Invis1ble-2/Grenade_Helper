import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LanDiscoveryDevice {
  final String host;
  final int port;
  final String deviceId;
  final String deviceName;
  final bool requireAuthForUpload;
  final int trustedPeerCount;

  const LanDiscoveryDevice({
    required this.host,
    required this.port,
    required this.deviceId,
    required this.deviceName,
    required this.requireAuthForUpload,
    required this.trustedPeerCount,
  });
}

class LanSyncDiscoveryService {
  static const String healthPath = '/v1/health';

  Future<List<LanDiscoveryDevice>> scan({
    required List<String> localIps,
    int port = 39527,
    Duration timeout = const Duration(milliseconds: 450),
    int concurrency = 48,
  }) async {
    final prefixes = <String>{};
    final localSet = localIps.toSet();
    for (final ip in localIps) {
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
    }
    if (prefixes.isEmpty) return const [];

    final candidates = <String>[];
    for (final prefix in prefixes) {
      for (var i = 1; i <= 254; i++) {
        final host = '$prefix$i';
        if (localSet.contains(host)) continue;
        candidates.add(host);
      }
    }

    final results = <LanDiscoveryDevice>[];
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      for (var i = 0; i < candidates.length; i += concurrency) {
        final batch = candidates.skip(i).take(concurrency);
        final found = await Future.wait(
          batch.map((host) => _probeHost(client, host, port, timeout)),
        );
        for (final item in found) {
          if (item != null) {
            results.add(item);
          }
        }
      }
    } finally {
      client.close(force: true);
    }

    results.sort((a, b) => a.host.compareTo(b.host));
    return results;
  }

  Future<LanDiscoveryDevice?> _probeHost(
    HttpClient client,
    String host,
    int port,
    Duration timeout,
  ) async {
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: healthPath,
      );
      final req = await client.getUrl(uri).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await utf8.decoder.bind(resp).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final ok = decoded['ok'] == true;
      if (!ok) return null;
      final service = (decoded['service'] as String? ?? '').trim();
      if (service != 'grenade_helper_lan_sync_receiver') return null;
      return LanDiscoveryDevice(
        host: host,
        port: (decoded['port'] as int?) ?? port,
        deviceId: (decoded['deviceId'] as String? ?? '').trim(),
        deviceName: (decoded['deviceName'] as String? ?? '').trim(),
        requireAuthForUpload: decoded['requireAuthForUpload'] as bool? ?? false,
        trustedPeerCount: decoded['trustedPeerCount'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
