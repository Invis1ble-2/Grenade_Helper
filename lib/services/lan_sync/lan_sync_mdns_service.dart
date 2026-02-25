import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

class LanSyncMdnsDevice {
  final String host;
  final int port;
  final String deviceId;
  final String deviceName;
  final String source; // mdns

  const LanSyncMdnsDevice({
    required this.host,
    required this.port,
    required this.deviceId,
    required this.deviceName,
    this.source = 'mdns',
  });
}

class LanSyncMdnsService {
  static const String serviceType = '_grenadehelper._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;

  Future<void> startBroadcast({
    required String deviceName,
    required int port,
    String deviceId = '',
  }) async {
    await stopBroadcast();
    final service = BonsoirService(
      name: deviceName.isEmpty ? 'Grenade Helper' : deviceName,
      type: serviceType,
      port: port,
      attributes: {
        'app': 'grenade_helper',
        'svc': 'lan_sync',
        'ver': '1',
        'did': deviceId,
      },
    );
    final broadcast = BonsoirBroadcast(service: service, printLogs: false);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> stopBroadcast() async {
    final b = _broadcast;
    _broadcast = null;
    if (b != null) {
      try {
        await b.stop();
      } catch (_) {}
    }
  }

  Future<List<LanSyncMdnsDevice>> discoverOnce({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    await stopDiscovery();
    final discovery = BonsoirDiscovery(
      type: serviceType,
      printLogs: false,
    );
    final found = <String, LanSyncMdnsDevice>{};
    try {
      await discovery.initialize();
      _discovery = discovery;

      final completer = Completer<void>();
      _discoverySub = discovery.eventStream?.listen((event) async {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            try {
              await event.service.resolve(discovery.serviceResolver);
            } catch (_) {}
            break;
          case BonsoirDiscoveryServiceResolvedEvent():
          case BonsoirDiscoveryServiceUpdatedEvent():
            final service = switch (event) {
              BonsoirDiscoveryServiceResolvedEvent() => event.service,
              BonsoirDiscoveryServiceUpdatedEvent() => event.service,
              _ => null,
            };
            if (service == null) return;
            final host = (service.host ?? '').trim();
            if (host.isEmpty || service.port <= 0) return;
            final attrs = service.attributes;
            if ((attrs['app'] ?? '') != 'grenade_helper' ||
                (attrs['svc'] ?? '') != 'lan_sync') {
              return;
            }
            final key = '$host:${service.port}';
            found[key] = LanSyncMdnsDevice(
              host: host,
              port: service.port,
              deviceId: (attrs['did'] ?? '').trim(),
              deviceName: service.name.trim(),
            );
            break;
          case BonsoirDiscoveryStoppedEvent():
            if (!completer.isCompleted) completer.complete();
            break;
          default:
            break;
        }
      });

      await discovery.start();
      await Future.any([
        Future<void>.delayed(timeout),
        completer.future,
      ]);
    } finally {
      await stopDiscovery();
    }

    final list = found.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
    return list;
  }

  Future<void> stopDiscovery() async {
    try {
      await _discoverySub?.cancel();
    } catch (_) {}
    _discoverySub = null;
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      try {
        await d.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stopDiscovery();
    await stopBroadcast();
  }
}
