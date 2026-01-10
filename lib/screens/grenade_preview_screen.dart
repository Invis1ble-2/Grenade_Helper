import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/data_service.dart';

/// 道具包中道具的预览页面（只读，不导入）
class GrenadePreviewScreen extends StatelessWidget {
  final GrenadePreviewItem grenade;
  final Map<String, List<int>> memoryImages;

  const GrenadePreviewScreen({
    super.key,
    required this.grenade,
    required this.memoryImages,
  });

  @override
  Widget build(BuildContext context) {
    final rawData = grenade.rawData;
    final steps = (rawData['steps'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(grenade.title),
        actions: [
          _buildStatusBadge(grenade.status),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // 顶部信息栏
          _buildInfoBar(context),
          // 步骤列表
          Expanded(
            child: steps.isEmpty
                ? const Center(
                    child: Text("无教学步骤", style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: steps.length,
                    itemBuilder: (context, index) =>
                        _buildStepCard(context, steps[index], index),
                  ),
          ),
          // 底部信息
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildInfoBar(BuildContext context) {
    final typeIcon = _getTypeIcon(grenade.type);
    final typeName = _getTypeName(grenade.type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(typeIcon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text(typeName, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Icon(Icons.map, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            "${grenade.mapName} - ${grenade.layerName}",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(BuildContext context, dynamic stepData, int index) {
    final title = stepData['title'] as String? ?? '';
    final description = stepData['description'] as String? ?? '';
    final medias = (stepData['medias'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "#${index + 1}",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title.isNotEmpty ? title : "步骤 ${index + 1}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 描述
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                description,
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
            ),
          // 媒体列表
          ...medias.map((media) => _buildMediaItem(context, media)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMediaItem(BuildContext context, dynamic mediaData) {
    final path = mediaData['path'] as String? ?? '';
    final type = mediaData['type'] as int? ?? 0;

    // 从内存中获取图片数据
    final imageBytes = memoryImages[path];

    if (imageBytes == null) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text("无法加载媒体", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (type == MediaType.video) {
      // 视频只显示占位符
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam, size: 48, color: Colors.orange),
              SizedBox(height: 8),
              Text("视频预览（导入后可播放）", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // 显示图片
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          Uint8List.fromList(imageBytes),
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 200,
              color: Colors.grey[800],
              child: const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            "作者: ${grenade.author ?? '匿名作者'}",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ImportStatus status) {
    Color color;
    String text;
    switch (status) {
      case ImportStatus.newItem:
        color = Colors.green;
        text = "新增";
        break;
      case ImportStatus.update:
        color = Colors.orange;
        text = "更新";
        break;
      case ImportStatus.skip:
        color = Colors.grey;
        text = "跳过";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  String _getTypeIcon(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return "☁️";
      case GrenadeType.flash:
        return "⚡";
      case GrenadeType.molotov:
        return "🔥";
      case GrenadeType.he:
        return "💣";
      case GrenadeType.wallbang:
        return "🧱";
      default:
        return "❓";
    }
  }

  String _getTypeName(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return "烟雾弹";
      case GrenadeType.flash:
        return "闪光弹";
      case GrenadeType.molotov:
        return "燃烧弹";
      case GrenadeType.he:
        return "手雷";
      case GrenadeType.wallbang:
        return "穿点";
      default:
        return "未知";
    }
  }
}
