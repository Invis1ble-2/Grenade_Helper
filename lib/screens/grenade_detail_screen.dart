import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';

import '../models.dart';
import '../providers.dart';

// --- 视频播放小组件 ---
class VideoPlayerWidget extends StatefulWidget {
  final File file;
  const VideoPlayerWidget({super.key, required this.file});

  @override
  State<VideoPlayerWidget> createState() => VideoPlayerWidgetState();
}

class VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _videoController = VideoPlayerController.file(widget.file);
      await _videoController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: true,
        allowMuting: true,
        aspectRatio: _videoController!.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
              child: Text(errorMessage,
                  style: const TextStyle(color: Colors.white)));
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      _errorMessage = e.toString();
      if (mounted) setState(() {});
    }
  }

  /// 切换播放/暂停状态 (供外部通过 GlobalKey 调用)
  void togglePlayPause() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        height: 200,
        child: Center(
          child:
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_chewieController == null) {
      return Container(
        color: Colors.black,
        height: 200,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }
}

// --- 主页面 ---
class GrenadeDetailScreen extends ConsumerStatefulWidget {
  final int grenadeId;
  final bool isEditing;

  const GrenadeDetailScreen(
      {super.key, required this.grenadeId, required this.isEditing});

  @override
  ConsumerState<GrenadeDetailScreen> createState() =>
      _GrenadeDetailScreenState();
}

class _GrenadeDetailScreenState extends ConsumerState<GrenadeDetailScreen> {
  Grenade? grenade;
  final _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final isar = ref.read(isarProvider);
    grenade = await isar.grenades.get(widget.grenadeId);
    if (grenade != null) {
      grenade!.steps.loadSync();
      for (var step in grenade!.steps) {
        step.medias.loadSync();
      }
      _titleController.text = grenade!.title;
    }
    setState(() {});
  }

  void _updateGrenade(
      {String? title, int? type, int? team, bool? isFavorite}) async {
    if (grenade == null) return;
    final isar = ref.read(isarProvider);

    if (title != null) grenade!.title = title;
    if (type != null) grenade!.type = type;
    if (team != null) grenade!.team = team;
    if (isFavorite != null) grenade!.isFavorite = isFavorite;

    grenade!.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.grenades.put(grenade!);
    });
    _loadData();
  }

  void _deleteGrenade() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("确认删除"),
              content: const Text("删除后无法恢复，确定要删除这个道具吗？"),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("取消")),
                TextButton(
                  onPressed: () async {
                    final isar = ref.read(isarProvider);
                    await isar.writeTxn(() async {
                      await isar.grenades.delete(grenade!.id);
                    });
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: const Text("删除", style: TextStyle(color: Colors.red)),
                ),
              ],
            ));
  }

  void _startAddStep() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1E23),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("添加步骤",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 15),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: "步骤标题 (可选)",
                hintText: "例如：站位、瞄点",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF2A2D33),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "说明文字",
                hintText: "在此输入详细操作说明...",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF2A2D33),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (descController.text.trim().isEmpty &&
                    titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("请至少输入标题或说明")));
                  return;
                }
                Navigator.pop(ctx);
                _saveStep(titleController.text, descController.text);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child:
                  const Text("保存 (仅文字)", style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickMediaForNewStep(
                          titleController.text, descController.text, true);
                    },
                    icon: const Icon(Icons.image, color: Colors.black),
                    label: const Text("加图并保存",
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickMediaForNewStep(
                          titleController.text, descController.text, false);
                    },
                    icon: const Icon(Icons.videocam, color: Colors.white),
                    label: const Text("加视频并保存",
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _saveStep(String title, String desc,
      {String? mediaPath, int? mediaType}) async {
    final isar = ref.read(isarProvider);

    final step = GrenadeStep(
      title: title,
      description: desc,
      stepIndex: grenade!.steps.length,
    );

    await isar.writeTxn(() async {
      await isar.grenadeSteps.put(step);
      step.grenade.value = grenade;
      await step.grenade.save();

      if (mediaPath != null && mediaType != null) {
        final media = StepMedia(localPath: mediaPath, type: mediaType);
        await isar.stepMedias.put(media);
        media.step.value = step;
        await media.step.save();
        step.medias.add(media);
        await step.medias.save();
      }

      grenade!.steps.add(step);
      await grenade!.steps.save();
      grenade!.updatedAt = DateTime.now();
      await isar.grenades.put(grenade!);
    });
    _loadData();
  }

  Future<void> _pickMediaForNewStep(
      String title, String desc, bool isImage) async {
    final path = await _pickAndProcessMedia(isImage);
    if (path != null) {
      _saveStep(title, desc,
          mediaPath: path,
          mediaType: isImage ? MediaType.image : MediaType.video);
    }
  }

  Future<void> _appendMediaToStep(GrenadeStep step, bool isImage) async {
    final path = await _pickAndProcessMedia(isImage);
    if (path != null) {
      final isar = ref.read(isarProvider);
      final media = StepMedia(
          localPath: path, type: isImage ? MediaType.image : MediaType.video);
      await isar.writeTxn(() async {
        await isar.stepMedias.put(media);
        media.step.value = step;
        await media.step.save();
        step.medias.add(media);
        await step.medias.save();
      });
      setState(() {});
    }
  }

  Future<String?> _pickAndProcessMedia(bool isImage) async {
    final picker = ImagePicker();
    final dir = await getApplicationDocumentsDirectory();

    if (isImage) {
      final xFile = await picker.pickImage(source: ImageSource.gallery);
      if (xFile == null) return null;
      if (!mounted) return null;

      String? resultPath;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProImageEditor.file(
            File(xFile.path),
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes) async {
                final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
                final savePath = p.join(dir.path, fileName);
                await File(savePath).writeAsBytes(bytes);
                resultPath = savePath;
                if (mounted) Navigator.pop(context);
              },
            ),
          ),
        ),
      );
      return resultPath;
    } else {
      final xFile = await picker.pickVideo(source: ImageSource.gallery);
      if (xFile == null) return null;
      if (!mounted) return null;

      try {
        final fileName =
            "${DateTime.now().millisecondsSinceEpoch}${p.extension(xFile.path)}";
        final savePath = p.join(dir.path, fileName);
        await File(xFile.path).copy(savePath);
        return savePath;
      } catch (e) {
        print('Video copy error: $e');
        return null;
      }
    }
  }

  // 显示全屏可缩放图片
  void _showFullscreenImage(String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          extendBodyBehindAppBar: true,
          body: Center(
            child: PhotoView(
              imageProvider: FileImage(File(imagePath)),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  // 编辑步骤文字（标题和描述）
  void _editStep(GrenadeStep step) {
    final titleController = TextEditingController(text: step.title);
    final descController = TextEditingController(text: step.description);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1E23),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("编辑步骤",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 15),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: "步骤标题",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF2A2D33),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descController,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "说明文字",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF2A2D33),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final isar = ref.read(isarProvider);
                step.title = titleController.text;
                step.description = descController.text;
                await isar.writeTxn(() async {
                  await isar.grenadeSteps.put(step);
                  grenade!.updatedAt = DateTime.now();
                  await isar.grenades.put(grenade!);
                });
                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("步骤已更新"),
                    duration: Duration(milliseconds: 800)));
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text("保存修改",
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // 编辑图片（重新进入图片编辑器）
  Future<void> _editImage(StepMedia media) async {
    if (media.type != MediaType.image) return;

    final dir = await getApplicationDocumentsDirectory();
    final file = File(media.localPath);
    if (!file.existsSync()) return;

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProImageEditor.file(
          file,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              // 保存编辑后的新文件（覆盖原文件或创建新文件）
              final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
              final savePath = p.join(dir.path, fileName);
              await File(savePath).writeAsBytes(bytes);

              // 更新媒体路径
              final isar = ref.read(isarProvider);
              media.localPath = savePath;
              await isar.writeTxn(() async {
                await isar.stepMedias.put(media);
                grenade!.updatedAt = DateTime.now();
                await isar.grenades.put(grenade!);
              });

              if (mounted) {
                Navigator.pop(context);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("图片已更新"),
                    duration: Duration(milliseconds: 800)));
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (grenade == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final isEditing = widget.isEditing;

    return Scaffold(
      appBar: AppBar(
        title: isEditing
            ? TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: "输入标题",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle,
                        color: Colors.greenAccent),
                    tooltip: "保存标题",
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      _updateGrenade(title: _titleController.text);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("标题已更新"),
                          duration: Duration(milliseconds: 500)));
                    },
                  ),
                ),
                onSubmitted: (val) => _updateGrenade(title: val),
              )
            : Text(grenade!.title),
        actions: [
          IconButton(
            icon: Icon(grenade!.isFavorite ? Icons.star : Icons.star_border,
                color: Colors.yellowAccent),
            onPressed: () => _updateGrenade(isFavorite: !grenade!.isFavorite),
          ),
          if (isEditing)
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _deleteGrenade),
        ],
      ),
      body: Column(
        children: [
          if (isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF2A2D33),
              child: Row(
                children: [
                  DropdownButton<int>(
                    value: grenade!.type,
                    dropdownColor: const Color(0xFF2A2D33),
                    items: const [
                      DropdownMenuItem(
                          value: GrenadeType.smoke, child: Text("☁️ 烟雾")),
                      DropdownMenuItem(
                          value: GrenadeType.flash, child: Text("⚡ 闪光")),
                      DropdownMenuItem(
                          value: GrenadeType.molotov, child: Text("🔥 燃烧")),
                      DropdownMenuItem(
                          value: GrenadeType.he, child: Text("💣 手雷")),
                    ],
                    onChanged: (val) => _updateGrenade(type: val),
                    underline: Container(),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: grenade!.team,
                    dropdownColor: const Color(0xFF2A2D33),
                    items: const [
                      DropdownMenuItem(
                          value: TeamType.all, child: Text("⚪ 通用")),
                      DropdownMenuItem(
                          value: TeamType.ct, child: Text("🔵 CT (警)")),
                      DropdownMenuItem(
                          value: TeamType.t, child: Text("🟡 T (匪)")),
                    ],
                    onChanged: (val) => _updateGrenade(team: val),
                    underline: Container(),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildStepList(isEditing)),
          _buildFooterInfo(),
        ],
      ),
      floatingActionButton: isEditing
          ? FloatingActionButton.extended(
              onPressed: _startAddStep,
              icon: const Icon(Icons.add),
              label: const Text("添加步骤"),
              backgroundColor: Colors.orange,
            )
          : null,
    );
  }

  Widget _buildStepList(bool isEditing) {
    final steps = grenade!.steps.toList();
    steps.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));

    if (steps.isEmpty) {
      return const Center(
          child: Text("暂无教学步骤", style: TextStyle(color: Colors.grey)));
    }

    if (isEditing) {
      return ReorderableListView(
        padding: const EdgeInsets.all(16),
        onReorder: (oldIndex, newIndex) {
          if (oldIndex < newIndex) newIndex -= 1;
          final item = steps.removeAt(oldIndex);
          steps.insert(newIndex, item);
          final isar = ref.read(isarProvider);
          for (int i = 0; i < steps.length; i++) {
            steps[i].stepIndex = i;
          }
          isar.writeTxnSync(() {
            isar.grenadeSteps.putAllSync(steps);
          });
          setState(() {});
        },
        children: steps.map((step) => _buildStepCard(step, isEditing)).toList(),
      );
    } else {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: steps.length,
        itemBuilder: (ctx, index) => _buildStepCard(steps[index], isEditing),
      );
    }
  }

  // 构建单个媒体项（图片或视频）
  Widget _buildMediaItem(StepMedia media, bool isEditing) {
    return Center(
      child: Stack(
        children: [
          SizedBox(
            width: MediaQuery.of(context).size.width - 48,
            height: 250,
            child: media.type == MediaType.image
                ? GestureDetector(
                    onTap: () => _showFullscreenImage(media.localPath),
                    child: Image.file(
                      File(media.localPath),
                      fit: BoxFit.contain,
                    ),
                  )
                : VideoPlayerWidget(file: File(media.localPath)),
          ),
          if (isEditing) ...[
            // 编辑图片按钮
            if (media.type == MediaType.image)
              Positioned(
                top: 5,
                right: 40,
                child: GestureDetector(
                  onTap: () => _editImage(media),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit,
                        size: 14, color: Colors.orangeAccent),
                  ),
                ),
              ),
            // 删除按钮
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                onTap: () async {
                  final isar = ref.read(isarProvider);
                  await isar.writeTxn(() async {
                    await isar.stepMedias.delete(media.id);
                  });
                  _loadData();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete,
                      size: 14, color: Colors.redAccent),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildStepCard(GrenadeStep step, bool isEditing) {
    return Card(
      key: ValueKey(step.id),
      margin: const EdgeInsets.only(bottom: 20),
      color: const Color(0xFF25282F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text("#${step.stepIndex + 1}",
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      step.title.isNotEmpty
                          ? step.title
                          : "步骤 ${step.stepIndex + 1}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white70)),
                ),
                if (isEditing) ...[
                  IconButton(
                    icon: const Icon(Icons.edit,
                        size: 20, color: Colors.orangeAccent),
                    onPressed: () => _editStep(step),
                    tooltip: "编辑步骤",
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate,
                        size: 20, color: Colors.blueAccent),
                    onPressed: () => _appendMediaToStep(step, true),
                    tooltip: "追加图片",
                  ),
                  IconButton(
                    icon: const Icon(Icons.video_call,
                        size: 20, color: Colors.greenAccent),
                    onPressed: () => _appendMediaToStep(step, false),
                    tooltip: "追加视频",
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.red),
                    onPressed: () async {
                      final isar = ref.read(isarProvider);
                      await isar.writeTxn(() async {
                        await isar.grenadeSteps.delete(step.id);
                      });
                      _loadData();
                    },
                  ),
                ]
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          if (step.medias.isNotEmpty)
            // 图片/视频垂直排列
            Column(
              children: step.medias
                  .map((media) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildMediaItem(media, isEditing),
                      ))
                  .toList(),
            )
          else if (isEditing)
            Container(
              height: 60,
              width: double.infinity,
              color: Colors.black26,
              child: const Center(
                  child: Text("暂无媒体，点击上方按钮添加",
                      style: TextStyle(color: Colors.grey))),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              step.description.isEmpty ? "（暂无文字说明）" : step.description,
              style: const TextStyle(
                  fontSize: 15, height: 1.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterInfo() {
    if (grenade == null) return const SizedBox();
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        children: [
          Text("创建于: ${fmt.format(grenade!.createdAt)}",
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
          Text("最后编辑: ${fmt.format(grenade!.updatedAt)}",
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }
}
