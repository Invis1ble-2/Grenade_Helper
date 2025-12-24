import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 更新信息模型
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String content;
  final String downloadUrl;

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.content,
    required this.downloadUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: json['versionCode'] ?? 0,
      versionName: json['versionName'] ?? '',
      content: json['content'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
    );
  }
}

/// 下载链接配置
class DownloadLinks {
  /// 网盘下载链接
  static const Map<String, String> panLinks = {
    '百度网盘': 'https://pan.baidu.com/s/5QyKQdw4AIqxcrHgbiN6gTw',
    '夸克网盘': 'https://pan.quark.cn/s/2907fabc3738',
    '蓝奏云网盘（密码4j0g）': 'https://wwanb.lanzoum.com/b016kfxakh',
  };

  /// 官方下载链接（根据平台动态生成）
  static String getOfficialUrl(String platform) {
    return 'https://cdn.grenade-helper.top:8443/download/$platform';
  }
}

/// 更新检测服务
class UpdateService {
  static const String _baseUrl = 'https://cdn.grenade-helper.top:8443';

  /// 获取当前平台标识
  String get currentPlatform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// 检查更新
  /// 返回 null 表示无需更新或检测失败
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      // 获取当前应用版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., "1.0.3"

      // 从服务器获取最新版本信息
      final platform = currentPlatform;
      if (platform == 'unknown') return null;

      final response = await http
          .get(Uri.parse('$_baseUrl/update/$platform'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final latestInfo = UpdateInfo.fromJson(json);

      // 比较版本号 (versionName)
      if (_isNewerVersion(latestInfo.versionName, currentVersion)) {
        return latestInfo;
      }

      return null;
    } catch (e) {
      // 网络错误或解析错误，静默失败
      print('Update check failed: $e');
      return null;
    }
  }

  /// 比较版本号，判断 latest 是否比 current 新
  /// 例如: "1.0.4" > "1.0.3" 返回 true
  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      // 补齐长度
      while (latestParts.length < 3) {
        latestParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      // 逐段比较
      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }

      return false; // 相等
    } catch (e) {
      return false;
    }
  }
}
