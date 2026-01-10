import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cloud_package.dart';

/// 云端道具包服务
class CloudPackageService {
  // ===== 索引文件源（GitHub 仓库）=====
  // GitHub 源（主）
  static const String kGitHubIndexUrl =
      'https://raw.githubusercontent.com/Invis1ble-2/grenades_repo/main/';
  // ghproxy 加速源（国内推荐）
  static const String kCDNIndexUrl =
      'https://ghproxy.grenade-helper.top/https://raw.githubusercontent.com/Invis1ble-2/grenades_repo/main/';

  // 当前使用的源
  static String kIndexBaseUrl = kGitHubIndexUrl;
  static bool _useCDN = false;

  /// 是否使用 CDN 加速（用于 CloudPackage.getDownloadUrl）
  static bool get isUsingCDN => _useCDN;

  static const String _lastImportedKey = 'cloud_package_last_imported';

  /// 获取云端道具包索引
  static Future<CloudPackageIndex?> fetchIndex() async {
    try {
      final response = await http
          .get(Uri.parse('${kIndexBaseUrl}index.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CloudPackageIndex.fromJson(json);
      }
    } catch (e) {
      debugPrint('获取索引失败: $e');
    }
    return null;
  }

  /// 切换源
  static void switchSource(bool useCDN) {
    _useCDN = useCDN;
    kIndexBaseUrl = useCDN ? kCDNIndexUrl : kGitHubIndexUrl;
  }

  // 存储正在下载的 client，用于取消
  static final Map<String, http.Client> _activeClients = {};

  /// 取消下载
  static void cancelDownload(String url) {
    final client = _activeClients.remove(url);
    client?.close();
  }

  /// 从 URL 下载 .cs2pkg 文件（带进度回调）
  /// [onProgress] 回调参数：(已下载字节数, 总字节数)
  static Future<String?> downloadPackage(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    // URL 应该是完整的 http(s) 地址
    return _downloadFromUrl(url, originalUrl: url, onProgress: onProgress);
  }

  static Future<String?> _downloadFromUrl(
    String url, {
    String? originalUrl,
    void Function(int received, int total)? onProgress,
  }) async {
    final trackingUrl = originalUrl ?? url;
    http.Client? client;
    try {
      debugPrint('正在下载: $url');

      // 使用流式下载支持进度回调
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

      client = http.Client();
      _activeClients[trackingUrl] = client;

      final response =
          await client.send(request).timeout(const Duration(seconds: 10));

      debugPrint('响应状态码: ${response.statusCode}');

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 0;
        final tempDir = await getTemporaryDirectory();
        final fileName = url.split('/').last;
        final filePath = '${tempDir.path}/$fileName';

        final file = File(filePath);
        final sink = file.openWrite();
        int received = 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, contentLength);
        }

        await sink.close();
        _activeClients.remove(trackingUrl);
        client.close();
        return filePath;
      } else {
        debugPrint('下载失败，状态码: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('下载失败 ($url): $e');
    } finally {
      _activeClients.remove(trackingUrl);
      client?.close();
    }
    return null;
  }

  /// 从任意 URL 导入道具包
  static Future<String?> downloadFromUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = url.split('/').last.isNotEmpty
            ? url.split('/').last
            : 'package.cs2pkg';
        final filePath = '${tempDir.path}/$fileName';
        await File(filePath).writeAsBytes(response.bodyBytes);
        return filePath;
      }
    } catch (e) {
      debugPrint('下载失败: $e');
    }
    return null;
  }

  /// 检查包是否需要更新（基于版本号）
  static Future<bool> isPackageUpToDate(
      String packageId, String version) async {
    final prefs = await SharedPreferences.getInstance();
    final lastImportedVersion = prefs.getString('$_lastImportedKey:$packageId');
    if (lastImportedVersion == null) return false; // 从未导入过
    return compareVersion(lastImportedVersion, version) >= 0;
  }

  /// 比较版本号，返回 1 表示 v1 > v2，0 表示相等，-1 表示 v1 < v2
  static int compareVersion(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// 标记包已导入（保存版本号）
  static Future<void> markPackageImported(
      String packageId, String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_lastImportedKey:$packageId', version);
  }

  /// 获取包的上次导入版本
  static Future<String?> getLastImportedVersion(String packageId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_lastImportedKey:$packageId');
  }

  /// 按地图筛选包列表
  static List<CloudPackage> filterByMap(
      List<CloudPackage> packages, String? mapFilter) {
    if (mapFilter == null || mapFilter == 'all') {
      return packages;
    }
    return packages.where((p) => p.map == null || p.map == mapFilter).toList();
  }

  /// 获取所有可用地图列表（从包中提取）
  static List<String> getAvailableMaps(List<CloudPackage> packages) {
    final maps = <String>{};
    for (final p in packages) {
      if (p.map != null && p.map!.isNotEmpty) {
        maps.add(p.map!);
      }
    }
    return maps.toList()..sort();
  }
}
