/// 云端道具包模型
class CloudPackage {
  final String id;
  final String name;
  final String description;
  final String author;
  final String? map; // null = 全图
  final String version; // 版本号，如 "1.0.0"
  final String updated; // 最后更新日期
  final String url; // 主源下载地址（R2 直连）
  final String? cdnUrl; // CDN 加速下载地址（可选）

  CloudPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    this.map,
    required this.version,
    required this.updated,
    required this.url,
    this.cdnUrl,
  });

  factory CloudPackage.fromJson(Map<String, dynamic> json) {
    return CloudPackage(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '未知',
      map: json['map'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      updated: json['updated'] as String? ?? '',
      url: json['url'] as String,
      cdnUrl: json['cdnUrl'] as String?,
    );
  }

  /// 根据当前源设置获取下载 URL
  String getDownloadUrl(bool useCDN) {
    if (useCDN && cdnUrl != null && cdnUrl!.isNotEmpty) {
      return cdnUrl!;
    }
    return url;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'author': author,
        'map': map,
        'version': version,
        'updated': updated,
        'url': url,
        if (cdnUrl != null) 'cdnUrl': cdnUrl,
      };
}


/// 云端仓库索引
class CloudPackageIndex {
  final int version;
  final String? updated; // 索引最后更新日期
  final List<String> sources; // 贡献者 JSON 文件列表
  final List<CloudPackage> packages;

  CloudPackageIndex({
    required this.version,
    this.updated,
    this.sources = const [],
    required this.packages,
  });

  factory CloudPackageIndex.fromJson(Map<String, dynamic> json) {
    return CloudPackageIndex(
      version: json['version'] as int? ?? 1,
      updated: json['updated'] as String?,
      sources: (json['sources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      packages: (json['packages'] as List<dynamic>?)
              ?.map((e) => CloudPackage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
