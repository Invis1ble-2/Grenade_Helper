import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LanSyncPeerEntry {
  final String id;
  final String name;
  final String host;
  final int port;
  final String peerId;
  final String sharedSecret;
  final bool isPaired;
  final String remoteDeviceName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final String note;

  const LanSyncPeerEntry({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.peerId = '',
    this.sharedSecret = '',
    this.isPaired = false,
    this.remoteDeviceName = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.note = '',
  });

  LanSyncPeerEntry copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? peerId,
    String? sharedSecret,
    bool? isPaired,
    String? remoteDeviceName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool clearLastUsedAt = false,
    String? note,
  }) {
    return LanSyncPeerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      peerId: peerId ?? this.peerId,
      sharedSecret: sharedSecret ?? this.sharedSecret,
      isPaired: isPaired ?? this.isPaired,
      remoteDeviceName: remoteDeviceName ?? this.remoteDeviceName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'peerId': peerId,
        'sharedSecret': sharedSecret,
        'isPaired': isPaired,
        'remoteDeviceName': remoteDeviceName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'note': note,
      };

  factory LanSyncPeerEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? raw, {DateTime? fallback}) {
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed;
      }
      return fallback ?? DateTime.now();
    }

    return LanSyncPeerEntry(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      host: (json['host'] as String? ?? '').trim(),
      port: json['port'] as int? ?? 39527,
      peerId: (json['peerId'] as String? ?? '').trim(),
      sharedSecret: (json['sharedSecret'] as String? ?? '').trim(),
      isPaired: json['isPaired'] as bool? ?? false,
      remoteDeviceName: (json['remoteDeviceName'] as String? ?? '').trim(),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      lastUsedAt: (json['lastUsedAt'] as String?) != null
          ? DateTime.tryParse(json['lastUsedAt'] as String)
          : null,
      note: (json['note'] as String? ?? '').trim(),
    );
  }
}

class LanSyncHistoryEntry {
  final String id;
  final String category; // send / receive / import / system
  final String title;
  final String detail;
  final bool success;
  final DateTime createdAt;

  const LanSyncHistoryEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.detail,
    required this.success,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'detail': detail,
        'success': success,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LanSyncHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LanSyncHistoryEntry(
      id: (json['id'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? 'system').trim(),
      title: (json['title'] as String? ?? '').trim(),
      detail: (json['detail'] as String? ?? '').trim(),
      success: json['success'] as bool? ?? true,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class LanSyncGrenadeTombstoneEntry {
  final String uniqueId;
  final String mapName;
  final int deletedAt;

  const LanSyncGrenadeTombstoneEntry({
    required this.uniqueId,
    required this.mapName,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'uniqueId': uniqueId,
        'mapName': mapName,
        'deletedAt': deletedAt,
      };

  factory LanSyncGrenadeTombstoneEntry.fromJson(Map<String, dynamic> json) {
    return LanSyncGrenadeTombstoneEntry(
      uniqueId: (json['uniqueId'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class LanSyncEntityTombstoneType {
  static const String tag = 'tag';
  static const String area = 'area';
  static const String favoriteFolder = 'favoriteFolder';
  static const String impactGroup = 'impactGroup';

  static const Set<String> values = {
    tag,
    area,
    favoriteFolder,
    impactGroup,
  };
}

class LanSyncEntityTombstoneEntry {
  final String entityType;
  final String entityKey;
  final String mapName;
  final int deletedAt;
  final Map<String, dynamic> payload;

  const LanSyncEntityTombstoneEntry({
    required this.entityType,
    required this.entityKey,
    required this.mapName,
    required this.deletedAt,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'entityKey': entityKey,
        'mapName': mapName,
        'deletedAt': deletedAt,
        'payload': payload,
      };

  factory LanSyncEntityTombstoneEntry.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return LanSyncEntityTombstoneEntry(
      entityType: (json['entityType'] as String? ?? '').trim(),
      entityKey: (json['entityKey'] as String? ?? '').trim(),
      mapName: (json['mapName'] as String? ?? '').trim(),
      deletedAt:
          json['deletedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
    );
  }
}

class LanSyncAckedMapBaselineEntry {
  final String baselineId;
  final int updatedAtMs;

  const LanSyncAckedMapBaselineEntry({
    required this.baselineId,
    required this.updatedAtMs,
  });
}

class LanSyncBaselineDebugMapEntry {
  final String mapKey;
  final String baselineId;
  final int updatedAtMs;
  final int snapshotCount;

  const LanSyncBaselineDebugMapEntry({
    required this.mapKey,
    required this.baselineId,
    required this.updatedAtMs,
    required this.snapshotCount,
  });
}

class LanSyncBaselineDebugPeerInfo {
  final String peerNodeId;
  final List<LanSyncBaselineDebugMapEntry> maps;

  const LanSyncBaselineDebugPeerInfo({
    required this.peerNodeId,
    required this.maps,
  });
}

class LanSyncTombstoneStats {
  final int grenadeCount;
  final int entityCount;

  const LanSyncTombstoneStats({
    required this.grenadeCount,
    required this.entityCount,
  });
}

class LanSyncLocalStore {
  static const _peersKey = 'lan_sync_peers_v1';
  static const _historyKey = 'lan_sync_history_v1';
  static const _stableNodeIdKey = 'lan_sync_stable_node_id_v1';
  static const _receiveSilentImportEnabledKey =
      'lan_sync_receive_silent_import_enabled_v1';
  static const _ackedMapBaselinesKey = 'lan_sync_acked_map_baselines_v1';
  static const _mapBaselineSnapshotsKey = 'lan_sync_map_baseline_snapshots_v1';
  static const _grenadeTombstonesKey = 'lan_sync_grenade_tombstones_v1';
  static const _entityTombstonesKey = 'lan_sync_entity_tombstones_v1';
  static const _historyLimit = 120;
  static const _syncTombstoneRetentionDays = 90;
  static const _maxGrenadeTombstones = 4000;
  static const _maxEntityTombstones = 4000;

  String _entityTombstoneCompositeKey(String entityType, String entityKey) {
    return '${entityType.trim()}|${entityKey.trim()}';
  }

  int _tombstoneCutoffMs() {
    return DateTime.now()
        .subtract(const Duration(days: _syncTombstoneRetentionDays))
        .millisecondsSinceEpoch;
  }

  Map<String, dynamic> _decodeStoredMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Map<String, dynamic> _pruneRawTombstoneMap(
    Map<String, dynamic> source, {
    required int maxEntries,
  }) {
    final cutoffMs = _tombstoneCutoffMs();
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final rawEntry in source.entries) {
      if (rawEntry.value is! Map) continue;
      final value = Map<String, dynamic>.from(rawEntry.value as Map);
      final deletedAt = value['deletedAt'] as int?;
      if (deletedAt == null || deletedAt < cutoffMs) continue;
      entries.add(MapEntry(rawEntry.key, value));
    }
    entries.sort((a, b) =>
        (b.value['deletedAt'] as int).compareTo(a.value['deletedAt'] as int));
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    return {
      for (final entry in entries) entry.key: entry.value,
    };
  }

  Future<String> loadOrCreateStableNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_stableNodeIdKey) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final created = 'node_${const Uuid().v4()}';
    await prefs.setString(_stableNodeIdKey, created);
    return created;
  }

  Future<void> cleanupLegacySyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ackedMapBaselinesKey);
    await prefs.remove(_mapBaselineSnapshotsKey);
  }

  Future<Map<String, String>> loadAckedMapBaselineIds({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) async {
    final entries = await loadAckedMapBaselineEntries(
      peerNodeId: peerNodeId,
      mapKeys: mapKeys,
    );
    return {
      for (final entry in entries.entries) entry.key: entry.value.baselineId,
    };
  }

  Future<Map<String, LanSyncAckedMapBaselineEntry>>
      loadAckedMapBaselineEntries({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) async {
    final peerKey = peerNodeId.trim();
    if (peerKey.isEmpty) return const {};
    final keys =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (keys.isEmpty) return const {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ackedMapBaselinesKey);
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final all = Map<String, dynamic>.from(decoded);
      final peerRaw = all[peerKey];
      if (peerRaw is! Map) return const {};
      final peerMap = Map<String, dynamic>.from(peerRaw);
      final result = <String, LanSyncAckedMapBaselineEntry>{};
      for (final mapKey in keys) {
        final entry = peerMap[mapKey];
        if (entry is! Map) continue;
        final baselineId = (entry['baselineId'] as String? ?? '').trim();
        final updatedAtMs = entry['updatedAtMs'] as int? ?? 0;
        if (baselineId.isNotEmpty) {
          result[mapKey] = LanSyncAckedMapBaselineEntry(
            baselineId: baselineId,
            updatedAtMs: updatedAtMs,
          );
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<bool> hasAckedMapBaselines({
    required String peerNodeId,
    required Iterable<String> mapKeys,
  }) async {
    final keys =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (keys.isEmpty) return false;
    final map = await loadAckedMapBaselineIds(
      peerNodeId: peerNodeId,
      mapKeys: keys,
    );
    return map.length == keys.length;
  }

  Future<void> upsertAckedMapBaselines({
    required String peerNodeId,
    required Iterable<String> mapKeys,
    String? baselineId,
  }) async {
    final peerKey = peerNodeId.trim();
    if (peerKey.isEmpty) return;
    final keys =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (keys.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ackedMapBaselinesKey);
    final all = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          all.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    final peerRaw = all[peerKey];
    final peerMap = <String, dynamic>{};
    if (peerRaw is Map) {
      peerMap.addAll(Map<String, dynamic>.from(peerRaw));
    }

    final nextBaselineId =
        (baselineId ?? 'bl_${DateTime.now().microsecondsSinceEpoch}').trim();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final mapKey in keys) {
      peerMap[mapKey] = {
        'baselineId': nextBaselineId,
        'updatedAtMs': nowMs,
      };
    }

    all[peerKey] = peerMap;
    await prefs.setString(_ackedMapBaselinesKey, jsonEncode(all));
  }

  Future<Map<String, Map<String, String>>> loadMapBaselineSnapshots({
    required String peerNodeId,
    required Iterable<String> mapKeys,
    Map<String, String>? expectedBaselineIds,
  }) async {
    final peerKey = peerNodeId.trim();
    if (peerKey.isEmpty) return const {};
    final keys =
        mapKeys.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (keys.isEmpty) return const {};

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mapBaselineSnapshotsKey);
    if (raw == null || raw.trim().isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final all = Map<String, dynamic>.from(decoded);
      final peerRaw = all[peerKey];
      if (peerRaw is! Map) return const {};
      final peerMap = Map<String, dynamic>.from(peerRaw);

      final result = <String, Map<String, String>>{};
      for (final mapKey in keys) {
        final entryRaw = peerMap[mapKey];
        if (entryRaw is! Map) continue;
        final entry = Map<String, dynamic>.from(entryRaw);

        final expectedBaselineId = (expectedBaselineIds?[mapKey] ?? '').trim();
        if (expectedBaselineId.isNotEmpty) {
          final currentBaselineId =
              (entry['baselineId'] as String? ?? '').trim();
          if (currentBaselineId != expectedBaselineId) {
            continue;
          }
        }

        final digestsRaw = entry['grenadeDigests'];
        if (digestsRaw is! Map) continue;
        final digests = <String, String>{};
        for (final e in Map<String, dynamic>.from(digestsRaw).entries) {
          final key = e.key.trim();
          final value = (e.value as String? ?? '').trim();
          if (key.isEmpty || value.isEmpty) continue;
          digests[key] = value;
        }
        result[mapKey] = digests;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> upsertMapBaselineSnapshots({
    required String peerNodeId,
    required Map<String, Map<String, String>> mapDigests,
    required String baselineId,
  }) async {
    final peerKey = peerNodeId.trim();
    final nextBaselineId = baselineId.trim();
    if (peerKey.isEmpty || nextBaselineId.isEmpty || mapDigests.isEmpty) {
      return;
    }

    final normalized = <String, Map<String, String>>{};
    for (final entry in mapDigests.entries) {
      final mapKey = entry.key.trim();
      if (mapKey.isEmpty) continue;
      final digests = <String, String>{};
      for (final digestEntry in entry.value.entries) {
        final uid = digestEntry.key.trim();
        final digest = digestEntry.value.trim();
        if (uid.isEmpty || digest.isEmpty) continue;
        digests[uid] = digest;
      }
      normalized[mapKey] = digests;
    }
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mapBaselineSnapshotsKey);
    final all = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          all.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    final peerRaw = all[peerKey];
    final peerMap = <String, dynamic>{};
    if (peerRaw is Map) {
      peerMap.addAll(Map<String, dynamic>.from(peerRaw));
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final entry in normalized.entries) {
      peerMap[entry.key] = {
        'baselineId': nextBaselineId,
        'updatedAtMs': nowMs,
        'grenadeDigests': entry.value,
      };
    }

    all[peerKey] = peerMap;
    await prefs.setString(_mapBaselineSnapshotsKey, jsonEncode(all));
  }

  Future<void> upsertGrenadeTombstones(
    Iterable<LanSyncGrenadeTombstoneEntry> tombstones,
  ) async {
    final normalized = <String, LanSyncGrenadeTombstoneEntry>{};
    for (final entry in tombstones) {
      final uniqueId = entry.uniqueId.trim();
      final mapName = entry.mapName.trim();
      if (uniqueId.isEmpty || mapName.isEmpty) continue;
      normalized[uniqueId] = LanSyncGrenadeTombstoneEntry(
        uniqueId: uniqueId,
        mapName: mapName,
        deletedAt: entry.deletedAt,
      );
    }
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final all = _decodeStoredMap(prefs.getString(_grenadeTombstonesKey));

    for (final entry in normalized.entries) {
      all[entry.key] = entry.value.toJson();
    }

    final pruned = _pruneRawTombstoneMap(
      all,
      maxEntries: _maxGrenadeTombstones,
    );
    await prefs.setString(_grenadeTombstonesKey, jsonEncode(pruned));
  }

  Future<Map<String, LanSyncGrenadeTombstoneEntry>> loadGrenadeTombstones({
    Iterable<String>? uniqueIds,
    Iterable<String>? mapKeys,
  }) async {
    final targetIds =
        uniqueIds?.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final targetMaps =
        mapKeys?.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    final prefs = await SharedPreferences.getInstance();
    final all = _decodeStoredMap(prefs.getString(_grenadeTombstonesKey));
    if (all.isEmpty) return const {};

    final pruned = _pruneRawTombstoneMap(
      all,
      maxEntries: _maxGrenadeTombstones,
    );
    if (pruned.length != all.length) {
      await prefs.setString(_grenadeTombstonesKey, jsonEncode(pruned));
    }

    try {
      final result = <String, LanSyncGrenadeTombstoneEntry>{};
      for (final rawEntry in pruned.entries) {
        if (rawEntry.value is! Map) continue;
        final entry = LanSyncGrenadeTombstoneEntry.fromJson(
          Map<String, dynamic>.from(rawEntry.value as Map),
        );
        if (entry.uniqueId.isEmpty || entry.mapName.isEmpty) continue;
        if (targetIds != null && !targetIds.contains(entry.uniqueId)) continue;
        if (targetMaps != null && !targetMaps.contains(entry.mapName)) continue;
        result[entry.uniqueId] = entry;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> upsertEntityTombstones(
    Iterable<LanSyncEntityTombstoneEntry> tombstones,
  ) async {
    final normalized = <String, LanSyncEntityTombstoneEntry>{};
    for (final entry in tombstones) {
      final entityType = entry.entityType.trim();
      final entityKey = entry.entityKey.trim();
      final mapName = entry.mapName.trim();
      if (!LanSyncEntityTombstoneType.values.contains(entityType) ||
          entityKey.isEmpty ||
          mapName.isEmpty) {
        continue;
      }
      normalized[_entityTombstoneCompositeKey(entityType, entityKey)] =
          LanSyncEntityTombstoneEntry(
        entityType: entityType,
        entityKey: entityKey,
        mapName: mapName,
        deletedAt: entry.deletedAt,
        payload: Map<String, dynamic>.from(entry.payload),
      );
    }
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final all = _decodeStoredMap(prefs.getString(_entityTombstonesKey));
    for (final entry in normalized.entries) {
      all[entry.key] = entry.value.toJson();
    }

    final pruned = _pruneRawTombstoneMap(
      all,
      maxEntries: _maxEntityTombstones,
    );
    await prefs.setString(_entityTombstonesKey, jsonEncode(pruned));
  }

  Future<Map<String, LanSyncEntityTombstoneEntry>> loadEntityTombstones({
    Iterable<String>? entityTypes,
    Iterable<String>? entityKeys,
    Iterable<String>? mapKeys,
  }) async {
    final targetTypes = entityTypes
        ?.map((e) => e.trim())
        .where((e) => LanSyncEntityTombstoneType.values.contains(e))
        .toSet();
    final targetKeys =
        entityKeys?.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final targetMaps =
        mapKeys?.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    final prefs = await SharedPreferences.getInstance();
    final all = _decodeStoredMap(prefs.getString(_entityTombstonesKey));
    if (all.isEmpty) return const {};

    final pruned = _pruneRawTombstoneMap(
      all,
      maxEntries: _maxEntityTombstones,
    );
    if (pruned.length != all.length) {
      await prefs.setString(_entityTombstonesKey, jsonEncode(pruned));
    }

    final result = <String, LanSyncEntityTombstoneEntry>{};
    for (final rawEntry in pruned.entries) {
      if (rawEntry.value is! Map) continue;
      final entry = LanSyncEntityTombstoneEntry.fromJson(
        Map<String, dynamic>.from(rawEntry.value as Map),
      );
      if (!LanSyncEntityTombstoneType.values.contains(entry.entityType) ||
          entry.entityKey.isEmpty ||
          entry.mapName.isEmpty) {
        continue;
      }
      if (targetTypes != null && !targetTypes.contains(entry.entityType)) {
        continue;
      }
      if (targetKeys != null && !targetKeys.contains(entry.entityKey)) {
        continue;
      }
      if (targetMaps != null && !targetMaps.contains(entry.mapName)) {
        continue;
      }
      result[rawEntry.key] = entry;
    }
    return result;
  }

  Future<void> cleanupSyncTombstones() async {
    final prefs = await SharedPreferences.getInstance();
    final prunedGrenade = _pruneRawTombstoneMap(
      _decodeStoredMap(prefs.getString(_grenadeTombstonesKey)),
      maxEntries: _maxGrenadeTombstones,
    );
    final prunedEntity = _pruneRawTombstoneMap(
      _decodeStoredMap(prefs.getString(_entityTombstonesKey)),
      maxEntries: _maxEntityTombstones,
    );
    await prefs.setString(_grenadeTombstonesKey, jsonEncode(prunedGrenade));
    await prefs.setString(_entityTombstonesKey, jsonEncode(prunedEntity));
  }

  Future<LanSyncTombstoneStats> loadTombstoneStats() async {
    final prefs = await SharedPreferences.getInstance();
    final grenade = _pruneRawTombstoneMap(
      _decodeStoredMap(prefs.getString(_grenadeTombstonesKey)),
      maxEntries: _maxGrenadeTombstones,
    );
    final entity = _pruneRawTombstoneMap(
      _decodeStoredMap(prefs.getString(_entityTombstonesKey)),
      maxEntries: _maxEntityTombstones,
    );
    return LanSyncTombstoneStats(
      grenadeCount: grenade.length,
      entityCount: entity.length,
    );
  }

  Future<List<LanSyncBaselineDebugPeerInfo>> loadBaselineDebugPeers() async {
    final prefs = await SharedPreferences.getInstance();
    final ackAll = _decodeStoredMap(prefs.getString(_ackedMapBaselinesKey));
    final snapshotAll =
        _decodeStoredMap(prefs.getString(_mapBaselineSnapshotsKey));

    final peerIds = <String>{
      ...ackAll.keys.map((e) => e.trim()).where((e) => e.isNotEmpty),
      ...snapshotAll.keys.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }.toList()
      ..sort();

    final peers = <LanSyncBaselineDebugPeerInfo>[];
    for (final peerId in peerIds) {
      final ackPeerRaw = ackAll[peerId];
      final snapshotPeerRaw = snapshotAll[peerId];
      final ackPeer =
          ackPeerRaw is Map ? Map<String, dynamic>.from(ackPeerRaw) : const {};
      final snapshotPeer = snapshotPeerRaw is Map
          ? Map<String, dynamic>.from(snapshotPeerRaw)
          : const {};
      final mapKeys = <String>{
        ...ackPeer.keys.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ...snapshotPeer.keys.map((e) => e.trim()).where((e) => e.isNotEmpty),
      }.toList()
        ..sort();

      final maps = <LanSyncBaselineDebugMapEntry>[];
      for (final mapKey in mapKeys) {
        final ackEntryRaw = ackPeer[mapKey];
        final snapshotEntryRaw = snapshotPeer[mapKey];
        final ackEntry = ackEntryRaw is Map
            ? Map<String, dynamic>.from(ackEntryRaw)
            : const {};
        final snapshotEntry = snapshotEntryRaw is Map
            ? Map<String, dynamic>.from(snapshotEntryRaw)
            : const {};
        final baselineId = (ackEntry['baselineId'] as String? ??
                snapshotEntry['baselineId'] as String? ??
                '')
            .trim();
        final updatedAtMs = math.max(
          ackEntry['updatedAtMs'] as int? ?? 0,
          snapshotEntry['updatedAtMs'] as int? ?? 0,
        );
        final digestsRaw = snapshotEntry['grenadeDigests'];
        final snapshotCount = digestsRaw is Map ? digestsRaw.length : 0;
        maps.add(LanSyncBaselineDebugMapEntry(
          mapKey: mapKey,
          baselineId: baselineId,
          updatedAtMs: updatedAtMs,
          snapshotCount: snapshotCount,
        ));
      }
      if (maps.isNotEmpty) {
        peers.add(LanSyncBaselineDebugPeerInfo(peerNodeId: peerId, maps: maps));
      }
    }
    return peers;
  }

  Future<List<LanSyncPeerEntry>> loadPeers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_peersKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final peers = decoded
          .whereType<Map>()
          .map((e) => LanSyncPeerEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty && e.host.isNotEmpty)
          .toList();
      peers.sort((a, b) {
        final aUsed = a.lastUsedAt ?? a.updatedAt;
        final bUsed = b.lastUsedAt ?? b.updatedAt;
        return bUsed.compareTo(aUsed);
      });
      return peers;
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePeers(List<LanSyncPeerEntry> peers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _peersKey,
      jsonEncode(peers.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<List<LanSyncHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final logs = decoded
          .whereType<Map>()
          .map(
              (e) => LanSyncHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return logs;
    } catch (_) {
      return const [];
    }
  }

  Future<List<LanSyncHistoryEntry>> appendHistory(
    LanSyncHistoryEntry entry,
  ) async {
    final current = await loadHistory();
    final next = [entry, ...current];
    if (next.length > _historyLimit) {
      next.removeRange(_historyLimit, next.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(next.map((e) => e.toJson()).toList(growable: false)),
    );
    return next;
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<bool> loadReceiveSilentImportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_receiveSilentImportEnabledKey) ?? false;
  }

  Future<void> saveReceiveSilentImportEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_receiveSilentImportEnabledKey, enabled);
  }
}
