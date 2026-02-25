import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

class LanSyncLocalStore {
  static const _peersKey = 'lan_sync_peers_v1';
  static const _historyKey = 'lan_sync_history_v1';
  static const _historyLimit = 120;

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
