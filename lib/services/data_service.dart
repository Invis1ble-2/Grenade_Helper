import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models.dart';
import '../models/tag.dart';
import '../models/grenade_tag.dart';

/// 导入状态
enum ImportStatus { newItem, update, skip }

/// 道具预览项
class GrenadePreviewItem {
  final Map<String, dynamic> rawData;
  final String uniqueId;
  final String title;
  final int type;
  final String mapName;
  final String layerName;
  final String? author;
  final ImportStatus status;
  final DateTime updatedAt;

  GrenadePreviewItem({
    required this.rawData,
    required this.uniqueId,
    required this.title,
    required this.type,
    required this.mapName,
    required this.layerName,
    this.author,
    required this.status,
    required this.updatedAt,
  });
}

/// 道具包预览结果
class PackagePreviewResult {
  final Map<String, List<GrenadePreviewItem>> grenadesByMap;
  final String filePath;
  final Map<String, List<int>> memoryImages;

  PackagePreviewResult({
    required this.grenadesByMap,
    required this.filePath,
    required this.memoryImages,
  });

  bool get isMultiMap => grenadesByMap.keys.length > 1;

  int get totalCount =>
      grenadesByMap.values.fold(0, (sum, list) => sum + list.length);

  List<String> get mapNames => grenadesByMap.keys.toList();
}

/// isolate 中执行的打包参数
class _PackageParams {
  final String exportDirPath;
  final String zipPath;
  final String jsonData;
  final List<String> filesToCopy;

  _PackageParams({
    required this.exportDirPath,
    required this.zipPath,
    required this.jsonData,
    required this.filesToCopy,
  });
}

/// 在 isolate 中执行文件复制和压缩（顶层函数）
Future<void> _packageFilesInIsolate(_PackageParams params) async {
  final exportDir = Directory(params.exportDirPath);

  // 清理并创建目录
  if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
  exportDir.createSync(recursive: true);

  // 写入 data.json
  final jsonFile = File(p.join(exportDir.path, "data.json"));
  jsonFile.writeAsStringSync(params.jsonData);

  // 复制媒体文件
  for (var filePath in params.filesToCopy) {
    final file = File(filePath);
    if (file.existsSync()) {
      file.copySync(p.join(exportDir.path, p.basename(filePath)));
    }
  }

  // 压缩为 .cs2pkg
  final encoder = ZipFileEncoder();
  encoder.create(params.zipPath);
  encoder.addDirectory(exportDir);
  encoder.close();
}

class DataService {
  final Isar isar;
  DataService(this.isar);

  /// 删除媒体文件（静态方法，可在其他地方调用）
  static Future<void> deleteMediaFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('删除媒体文件失败: $e');
    }
  }

  /// 批量删除媒体文件
  static Future<void> deleteMediaFiles(List<String> paths) async {
    for (final path in paths) {
      await deleteMediaFile(path);
    }
  }

  /// 预览包
  Future<PackagePreviewResult?> previewPackage(String filePath) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return null;
    }

    final file = File(filePath);
    if (!file.existsSync()) return null;

    // 解压
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    List<dynamic> jsonData = [];
    final Map<String, List<int>> memoryImages = {};

    for (var archiveFile in archive) {
      final fileName = p.basename(archiveFile.name);
      if (fileName == "data.json") {
        jsonData = jsonDecode(utf8.decode(archiveFile.content as List<int>));
      } else {
        if (archiveFile.isFile && archiveFile.content != null) {
          memoryImages[fileName] = archiveFile.content as List<int>;
        }
      }
    }

    if (jsonData.isEmpty) return null;

    // 按地图分组
    final Map<String, List<GrenadePreviewItem>> grenadesByMap = {};

    for (var item in jsonData) {
      final mapName = item['mapName'] as String? ?? 'Unknown';
      final layerName = item['layerName'] as String? ?? 'Default';
      final title = item['title'] as String? ?? '';
      final type = item['type'] as int? ?? 0;
      final author = item['author'] as String?;
      final importedUniqueId = item['uniqueId'] as String?;
      final xRatio = (item['x'] as num?)?.toDouble() ?? 0.0;
      final yRatio = (item['y'] as num?)?.toDouble() ?? 0.0;
      final importedUpdatedAt = item['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
          : DateTime.now();

      // 生成临时 uniqueId（如果没有）
      final uniqueId =
          importedUniqueId ?? '${mapName}_${title}_${xRatio}_$yRatio';

      // 计算导入状态
      ImportStatus status = ImportStatus.newItem;

      // 查找地图
      final map = await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
      if (map != null) {
        await map.layers.load();
        MapLayer? layer;
        for (var l in map.layers) {
          if (l.name == layerName) {
            layer = l;
            break;
          }
        }
        layer ??= map.layers.isNotEmpty ? map.layers.first : null;

        if (layer != null) {
          // 查找已有道具
          Grenade? existing;

          if (importedUniqueId != null && importedUniqueId.isNotEmpty) {
            final allGrenades = await isar.grenades.where().findAll();
            existing = allGrenades
                .where((g) => g.uniqueId == importedUniqueId)
                .firstOrNull;
          }

          if (existing == null && importedUniqueId == null) {
            await layer.grenades.load();
            existing = layer.grenades
                .where((g) =>
                    g.title == title &&
                    (g.xRatio - xRatio).abs() < 0.01 &&
                    (g.yRatio - yRatio).abs() < 0.01)
                .firstOrNull;
          }

          if (existing != null) {
            if (importedUpdatedAt.isAfter(existing.updatedAt)) {
              status = ImportStatus.update;
            } else {
              status = ImportStatus.skip;
            }
          }
        }
      }

      final previewItem = GrenadePreviewItem(
        rawData: item,
        uniqueId: uniqueId,
        title: title,
        type: type,
        mapName: mapName,
        layerName: layerName,
        author: author,
        status: status,
        updatedAt: importedUpdatedAt,
      );

      grenadesByMap.putIfAbsent(mapName, () => []);
      grenadesByMap[mapName]!.add(previewItem);
    }

    return PackagePreviewResult(
      grenadesByMap: grenadesByMap,
      filePath: filePath,
      memoryImages: memoryImages,
    );
  }

  // --- 导出 (分享) ---

  /// 导出列表
  Future<void> exportSelectedGrenades(
      BuildContext context, List<Grenade> grenades) async {
    if (grenades.isEmpty) return;

    // 构建 JSON 数据结构
    final List<Map<String, dynamic>> exportList = [];
    final Set<String> filesToZip = {};

    for (var g in grenades) {
      g.layer.loadSync();
      g.layer.value?.map.loadSync();
      g.steps.loadSync();

      final stepsData = <Map<String, dynamic>>[];
      for (var s in g.steps) {
        s.medias.loadSync();
        final mediaData = <Map<String, dynamic>>[];
        for (var m in s.medias) {
          mediaData.add({'path': p.basename(m.localPath), 'type': m.type});
          filesToZip.add(m.localPath);
        }
        stepsData.add({
          'title': s.title,
          'description': s.description,
          'index': s.stepIndex,
          'medias': mediaData,
        });
      }

      // 获取道具关联的标签ID
      final grenadeTags = await isar.grenadeTags.filter().grenadeIdEqualTo(g.id).findAll();
      final tagIds = grenadeTags.map((gt) => gt.tagId).toList();

      exportList.add({
        'uniqueId': g.uniqueId,
        'mapName': g.layer.value?.map.value?.name ?? "Unknown",
        'layerName': g.layer.value?.name ?? "Default",
        'title': g.title,
        'type': g.type,
        'team': g.team,
        'author': g.author,
        'hasLocalEdits': g.hasLocalEdits,
        'x': g.xRatio,
        'y': g.yRatio,
        'impactX': g.impactXRatio,
        'impactY': g.impactYRatio,
        'impactAreaStrokes': g.impactAreaStrokes,
        'tagIds': tagIds,
        'steps': stepsData,
        'createdAt': g.createdAt.millisecondsSinceEpoch,
        'updatedAt': g.updatedAt.millisecondsSinceEpoch,
      });
    }

    // 获取临时目录路径
    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, "export_temp");
    final zipPath = p.join(tempDir.path, "share_data.cs2pkg");

    // 异步打包
    await compute(
      _packageFilesInIsolate,
      _PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(exportList),
        filesToCopy: filesToZip.toList(),
      ),
    );

    if (!context.mounted) return;

    // 根据平台显示不同的分享选项
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    if (isDesktop) {
      // 另存为
      await _saveToFolderWithCustomName(context, zipPath);
    } else {
      // 底部菜单
      await showModalBottomSheet(
        context: context,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          decoration: const BoxDecoration(
            color: Color(0xFF2A2D33),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const Text("选择导出方式",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blueAccent),
                title: const Text("系统分享 (微信/QQ)",
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                      ShareParams(files: [XFile(zipPath)], text: "CS2 道具数据分享"));
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.folder_open, color: Colors.orangeAccent),
                title:
                    const Text("保存到文件夹", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveToFolderWithCustomName(context, zipPath);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> exportData(BuildContext context,
      {required int scopeType,
      Grenade? singleGrenade,
      GameMap? singleMap}) async {
    final grenades = <Grenade>[];

    // 1. 确定要导出的数据范围
    if (scopeType == 0 && singleGrenade != null) {
      grenades.add(singleGrenade);
    } else if (scopeType == 1 && singleMap != null) {
      singleMap.layers.loadSync();
      for (var layer in singleMap.layers) {
        layer.grenades.loadSync();
        grenades.addAll(layer.grenades);
      }
    } else {
      grenades.addAll(isar.grenades.where().findAllSync());
    }

    if (grenades.isEmpty) return;

    // 2. 构建 JSON 数据结构
    final List<Map<String, dynamic>> exportList = [];
    final Set<String> filesToZip = {};

    for (var g in grenades) {
      g.layer.loadSync();
      g.layer.value?.map.loadSync();
      g.steps.loadSync();

      final stepsData = <Map<String, dynamic>>[];
      for (var s in g.steps) {
        s.medias.loadSync();
        final mediaData = <Map<String, dynamic>>[];
        for (var m in s.medias) {
          mediaData.add({'path': p.basename(m.localPath), 'type': m.type});
          filesToZip.add(m.localPath);
        }
        stepsData.add({
          'title': s.title,
          'description': s.description,
          'index': s.stepIndex,
          'medias': mediaData,
        });
      }

      // 获取道具关联的标签ID
      final grenadeTags = await isar.grenadeTags.filter().grenadeIdEqualTo(g.id).findAll();
      final tagIds = grenadeTags.map((gt) => gt.tagId).toList();

      exportList.add({
        'uniqueId': g.uniqueId,
        'mapName': g.layer.value?.map.value?.name ?? "Unknown",
        'layerName': g.layer.value?.name ?? "Default",
        'title': g.title,
        'type': g.type,
        'team': g.team,
        'author': g.author,
        'hasLocalEdits': g.hasLocalEdits,
        'x': g.xRatio,
        'y': g.yRatio,
        'impactX': g.impactXRatio,
        'impactY': g.impactYRatio,
        'impactAreaStrokes': g.impactAreaStrokes,
        'tagIds': tagIds,
        'steps': stepsData,
        'createdAt': g.createdAt.millisecondsSinceEpoch,
        'updatedAt': g.updatedAt.millisecondsSinceEpoch,
      });
    }

    // 3. 获取临时目录路径
    final tempDir = await getTemporaryDirectory();
    final exportDirPath = p.join(tempDir.path, "export_temp");
    final zipPath = p.join(tempDir.path, "share_data.cs2pkg");

    // 4. 异步打包
    await compute(
      _packageFilesInIsolate,
      _PackageParams(
        exportDirPath: exportDirPath,
        zipPath: zipPath,
        jsonData: jsonEncode(exportList),
        filesToCopy: filesToZip.toList(),
      ),
    );

    if (!context.mounted) return;

    // 根据平台显示不同的分享选项
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    if (isDesktop) {
      // 另存为
      await _saveToFolderWithCustomName(context, zipPath);
    } else {
      // 底部菜单
      await showModalBottomSheet(
        context: context,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          decoration: const BoxDecoration(
            color: Color(0xFF2A2D33),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const Text("选择导出方式",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.blueAccent),
                title: const Text("系统分享 (微信/QQ)",
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                      ShareParams(files: [XFile(zipPath)], text: "CS2 道具数据分享"));
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.folder_open, color: Colors.orangeAccent),
                title:
                    const Text("保存到文件夹", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveToFolderWithCustomName(context, zipPath);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  // --- 导入 ---

  Future<String> importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要导入的 .cs2pkg 文件',
    );
    if (result == null) return "取消导入";

    final filePath = result.files.single.path!;
    return importFromPath(filePath);
  }

  /// 导入路径
  Future<String> importFromPath(String filePath) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return "请选择 .cs2pkg 格式的文件";
    }

    final file = File(filePath);
    final importFileName = p.basename(filePath);

    // 数据目录
    // 避免异步问题
    final dataPath = isar.directory ?? '';

    // 2. 解压
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    List<dynamic> jsonData = [];
    final Map<String, List<int>> memoryImages = {};

    for (var file in archive) {
      final fileName = p.basename(file.name);
      if (fileName == "data.json") {
        jsonData = jsonDecode(utf8.decode(file.content as List<int>));
      } else {
        if (file.isFile && file.content != null) {
          memoryImages[fileName] = file.content as List<int>;
        }
      }
    }

    if (jsonData.isEmpty) return "文件格式错误或无数据";

    // 3. 写入数据库
    int newCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    final List<Grenade> importedGrenades = []; // 收集导入的道具

    await isar.writeTxn(() async {
      for (var item in jsonData) {
        final mapName = item['mapName'];
        final layerName = item['layerName'];

        // 查找地图
        final map =
            await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
        if (map == null) continue;

        await map.layers.load();
        MapLayer? layer;
        for (var l in map.layers) {
          if (l.name == layerName) {
            layer = l;
            break;
          }
        }
        layer ??= map.layers.isNotEmpty ? map.layers.first : null;
        if (layer == null) continue;

        // 解析导入数据
        final importedUniqueId = item['uniqueId'] as String?;
        final title = item['title'] as String;
        final xRatio = (item['x'] as num).toDouble();
        final yRatio = (item['y'] as num).toDouble();
        final importedUpdatedAt = item['updatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
            : DateTime.now();

        // 查找是否存在相同的道具
        Grenade? existing;

        // UUID查找
        if (importedUniqueId != null && importedUniqueId.isNotEmpty) {
          final allGrenades = await isar.grenades.where().findAll();
          existing = allGrenades
              .where((g) => g.uniqueId == importedUniqueId)
              .firstOrNull;
        }

        // 回退查找
        if (existing == null && importedUniqueId == null) {
          await layer.grenades.load();
          existing = layer.grenades
              .where((g) =>
                  g.title == title &&
                  (g.xRatio - xRatio).abs() < 0.01 &&
                  (g.yRatio - yRatio).abs() < 0.01)
              .firstOrNull;
        }

        if (existing != null) {
          // 比较时间
          if (importedUpdatedAt.isAfter(existing.updatedAt)) {
            // 更新
            await _updateExistingGrenade(
                existing, item, memoryImages, dataPath);
            importedGrenades.add(existing); // 记录更新的道具
            updatedCount++;
          } else {
            // 跳过
            skippedCount++;
          }
        } else {
          // 新建
          final newGrenade = await _createNewGrenade(
              item, memoryImages, dataPath, layer, importedUniqueId);
          importedGrenades.add(newGrenade); // 记录新增的道具
          newCount++;
        }
      }

      // 4. 记录历史
      if (importedGrenades.isNotEmpty) {
        final history = ImportHistory(
          fileName: importFileName,
          importedAt: DateTime.now(),
          newCount: newCount,
          updatedCount: updatedCount,
          skippedCount: skippedCount,
        );
        await isar.importHistorys.put(history);

        // 关联
        history.grenades.addAll(importedGrenades);
        await history.grenades.save();
      }
    });

    // 结果消息
    final List<String> messages = [];
    if (newCount > 0) messages.add("新增 $newCount 个");
    if (updatedCount > 0) messages.add("更新 $updatedCount 个");
    if (skippedCount > 0) messages.add("跳过 $skippedCount 个较旧版本");

    if (messages.isEmpty) {
      return "没有可导入的道具";
    }
    return "成功导入：${messages.join('，')}";
  }

  /// 预览导入
  Future<String> importFromPreview(
    PackagePreviewResult preview,
    Set<String> selectedUniqueIds,
  ) async {
    if (selectedUniqueIds.isEmpty) {
      return "未选择任何道具";
    }

    final importFileName = p.basename(preview.filePath);
    final dataPath = isar.directory ?? '';
    final memoryImages = preview.memoryImages;

    int newCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    final List<Grenade> importedGrenades = [];

    await isar.writeTxn(() async {
      for (var mapGrenades in preview.grenadesByMap.values) {
        for (var previewItem in mapGrenades) {
          // 过滤选中
          if (!selectedUniqueIds.contains(previewItem.uniqueId)) continue;

          final item = previewItem.rawData;
          final mapName = item['mapName'];
          final layerName = item['layerName'];

          // 查找地图
          final map =
              await isar.gameMaps.filter().nameEqualTo(mapName).findFirst();
          if (map == null) continue;

          await map.layers.load();
          MapLayer? layer;
          for (var l in map.layers) {
            if (l.name == layerName) {
              layer = l;
              break;
            }
          }
          layer ??= map.layers.isNotEmpty ? map.layers.first : null;
          if (layer == null) continue;

          final importedUniqueId = item['uniqueId'] as String?;
          final title = item['title'] as String;
          final xRatio = (item['x'] as num).toDouble();
          final yRatio = (item['y'] as num).toDouble();
          final importedUpdatedAt = item['updatedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
              : DateTime.now();

          Grenade? existing;

          if (importedUniqueId != null && importedUniqueId.isNotEmpty) {
            final allGrenades = await isar.grenades.where().findAll();
            existing = allGrenades
                .where((g) => g.uniqueId == importedUniqueId)
                .firstOrNull;
          }

          if (existing == null && importedUniqueId == null) {
            await layer.grenades.load();
            existing = layer.grenades
                .where((g) =>
                    g.title == title &&
                    (g.xRatio - xRatio).abs() < 0.01 &&
                    (g.yRatio - yRatio).abs() < 0.01)
                .firstOrNull;
          }

          if (existing != null) {
            if (importedUpdatedAt.isAfter(existing.updatedAt)) {
              await _updateExistingGrenade(
                  existing, item, memoryImages, dataPath);
              importedGrenades.add(existing);
              updatedCount++;
            } else {
              skippedCount++;
            }
          } else {
            final newGrenade = await _createNewGrenade(
                item, memoryImages, dataPath, layer, importedUniqueId);
            importedGrenades.add(newGrenade);
            newCount++;
          }
        }
      }

      if (importedGrenades.isNotEmpty) {
        final history = ImportHistory(
          fileName: importFileName,
          importedAt: DateTime.now(),
          newCount: newCount,
          updatedCount: updatedCount,
          skippedCount: skippedCount,
        );
        await isar.importHistorys.put(history);
        history.grenades.addAll(importedGrenades);
        await history.grenades.save();
      }
    });

    final List<String> messages = [];
    if (newCount > 0) messages.add("新增 $newCount 个");
    if (updatedCount > 0) messages.add("更新 $updatedCount 个");
    if (skippedCount > 0) messages.add("跳过 $skippedCount 个较旧版本");

    if (messages.isEmpty) {
      return "没有可导入的道具";
    }
    return "成功导入：${messages.join('，')}";
  }

  /// 更新
  Future<void> _updateExistingGrenade(
    Grenade existing,
    Map<String, dynamic> item,
    Map<String, List<int>> memoryImages,
    String dataPath,
  ) async {
    // 更新信息
    existing.title = item['title'];
    existing.type = item['type'];
    existing.team = item['team'];
    existing.author = item['author'] as String?;
    existing.hasLocalEdits = false; // 重置
    existing.isImported = true; // 导入标记
    existing.xRatio = (item['x'] as num).toDouble();
    existing.yRatio = (item['y'] as num).toDouble();
    existing.impactXRatio = (item['impactX'] as num?)?.toDouble();
    existing.impactYRatio = (item['impactY'] as num?)?.toDouble();
    existing.impactAreaStrokes = item['impactAreaStrokes'] as String?;
    existing.updatedAt = DateTime.fromMillisecondsSinceEpoch(item['updatedAt']);
    existing.isNewImport = true;
    await isar.grenades.put(existing);

    // 删旧数据
    await existing.steps.load();
    for (final step in existing.steps) {
      await step.medias.load();
      // 删旧文件
      for (final media in step.medias) {
        final file = File(media.localPath);
        if (await file.exists()) {
          await file.delete();
        }
        await isar.stepMedias.delete(media.id);
      }
      await isar.grenadeSteps.delete(step.id);
    }
    existing.steps.clear();
    await existing.steps.save();

    // 创建新的 Steps 和 Medias
    final stepsList = item['steps'] as List;
    for (var sItem in stepsList) {
      final step = GrenadeStep(
        title: sItem['title'] ?? "",
        description: sItem['description'],
        stepIndex: sItem['index'],
      );
      await isar.grenadeSteps.put(step);

      step.grenade.value = existing;
      await step.grenade.save();

      existing.steps.add(step);

      final mediasList = sItem['medias'] as List;
      for (var mItem in mediasList) {
        final fileName = mItem['path'];
        if (memoryImages.containsKey(fileName)) {
          final savePath = p.join(
              dataPath, "${DateTime.now().millisecondsSinceEpoch}_$fileName");
          await File(savePath).writeAsBytes(memoryImages[fileName]!);

          final media = StepMedia(localPath: savePath, type: mItem['type']);
          await isar.stepMedias.put(media);

          media.step.value = step;
          await media.step.save();

          step.medias.add(media);
        }
      }
      await step.medias.save();
    }
    await existing.steps.save();
  }

  /// 创建新道具
  Future<Grenade> _createNewGrenade(
    Map<String, dynamic> item,
    Map<String, List<int>> memoryImages,
    String dataPath,
    MapLayer layer,
    String? uniqueId,
  ) async {
    final g = Grenade(
      title: item['title'],
      type: item['type'],
      team: item['team'],
      xRatio: (item['x'] as num).toDouble(),
      yRatio: (item['y'] as num).toDouble(),
      isNewImport: true,
      hasLocalEdits: false,
      isImported: true, // 标记为导入的道具
      uniqueId: uniqueId ?? const Uuid().v4(),
      created: item['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['createdAt'])
          : DateTime.now(),
      updated: item['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'])
          : DateTime.now(),
    );
    g.author = item['author'] as String?;
    g.impactXRatio = (item['impactX'] as num?)?.toDouble();
    g.impactYRatio = (item['impactY'] as num?)?.toDouble();
    g.impactAreaStrokes = item['impactAreaStrokes'] as String?;
    await isar.grenades.put(g);

    // 设置关联
    g.layer.value = layer;
    await g.layer.save();

    // 创建 Steps & Medias
    final stepsList = item['steps'] as List;
    for (var sItem in stepsList) {
      final step = GrenadeStep(
        title: sItem['title'] ?? "",
        description: sItem['description'],
        stepIndex: sItem['index'],
      );
      await isar.grenadeSteps.put(step);

      step.grenade.value = g;
      await step.grenade.save();

      g.steps.add(step);

      final mediasList = sItem['medias'] as List;
      for (var mItem in mediasList) {
        final fileName = mItem['path'];
        if (memoryImages.containsKey(fileName)) {
          final savePath = p.join(
              dataPath, "${DateTime.now().millisecondsSinceEpoch}_$fileName");
          await File(savePath).writeAsBytes(memoryImages[fileName]!);

          final media = StepMedia(localPath: savePath, type: mItem['type']);
          await isar.stepMedias.put(media);

          media.step.value = step;
          await media.step.save();

          step.medias.add(media);
        }
      }
      await step.medias.save();
    }
    await g.steps.save();
    
    // 导入标签关联
    final tagIds = item['tagIds'] as List?;
    if (tagIds != null && tagIds.isNotEmpty) {
      for (final tagId in tagIds) {
        if (tagId is int) {
          // 检查标签是否存在
          final tag = await isar.tags.get(tagId);
          if (tag != null) {
            final grenadeTag = GrenadeTag(grenadeId: g.id, tagId: tagId);
            await isar.grenadeTags.put(grenadeTag);
          }
        }
      }
    }
    
    return g; // 返回创建的道具
  }

  /// 另存为对话框，支持自定义文件名
  Future<void> _saveToFolderWithCustomName(
      BuildContext context, String sourcePath) async {
    // 生成默认文件名
    final defaultFileName =
        "cs2_tactics_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}";

    // 显示文件名输入对话框
    final fileNameController = TextEditingController(text: defaultFileName);
    final customFileName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("导出文件"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("请输入文件名："),
            const SizedBox(height: 16),
            TextField(
              controller: fileNameController,
              decoration: const InputDecoration(
                suffixText: ".cs2pkg",
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, fileNameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text("选择位置"),
          ),
        ],
      ),
    );

    if (customFileName == null || customFileName.isEmpty) return;
    if (!context.mounted) return;

    // 选择保存目录
    String? outputDirectory =
        await FilePicker.platform.getDirectoryPath(dialogTitle: "请选择保存位置");

    if (outputDirectory == null) return;

    try {
      final fileName = "$customFileName.cs2pkg";
      final destination = p.join(outputDirectory, fileName);

      final sourceFile = File(sourcePath);
      await sourceFile.copy(destination);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("文件已保存至:\n$destination"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("保存失败: $e"), backgroundColor: Colors.red));
      }
    }
  }
}
