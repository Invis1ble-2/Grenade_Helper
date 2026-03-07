import 'dart:convert';

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

class LanSyncLocalStore {
  static const _peersKey = 'lan_sync_peers_v1';
  static const _historyKey = 'lan_sync_history_v1';
  static const _stableNodeIdKey = 'lan_sync_stable_node_id_v1';
  static const _ackedMapBaselinesKey = 'lan_sync_acked_map_baselines_v1';
  static const _mapBaselineSnapshotsKey = 'lan_sync_map_baseline_snapshots_v1';
  static const _grenadeTombstonesKey = 'lan_sync_grenade_tombstones_v1';
  static const _historyLimit = 120;

  Future<String> loadOrCreateStableNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_stableNodeIdKey) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final created = 'node_${const Uuid().v4()}';
    await prefs.setString(_stableNodeIdKey, created);
    return created;
  }

  Future<Map<String, String>> loadAckedMapBaselineIds({
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
      final result = <String, String>{};
      for (final mapKey in keys) {
        final entry = peerMap[mapKey];
        if (entry is! Map) continue;
        final baselineId = (entry['baselineId'] as String? ?? '').trim();
        if (baselineId.isNotEmpty) {
          result[mapKey] = baselineId;
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
    final raw = prefs.getString(_grenadeTombstonesKey);
    final all = <String, dynamic>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          all.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    for (final entry in normalized.entries) {
      all[entry.key] = entry.value.toJson();
    }

    await prefs.setString(_grenadeTombstonesKey, jsonEncode(all));
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
    final raw = prefs.getString(_grenadeTombstonesKey);
    if (raw == null || raw.trim().isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final all = Map<String, dynamic>.from(decoded);
      final result = <String, LanSyncGrenadeTombstoneEntry>{};
      for (final rawEntry in all.entries) {
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
}
