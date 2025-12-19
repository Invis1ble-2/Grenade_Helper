import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';

class DataService {
  final Isar isar;
  DataService(this.isar);

  // --- 导出 (分享) ---

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

      exportList.add({
        'mapName': g.layer.value?.map.value?.name ?? "Unknown",
        'layerName': g.layer.value?.name ?? "Default",
        'title': g.title,
        'type': g.type,
        'team': g.team,
        'x': g.xRatio,
        'y': g.yRatio,
        'steps': stepsData,
        'createdAt': g.createdAt.millisecondsSinceEpoch,
        'updatedAt': g.updatedAt.millisecondsSinceEpoch,
      });
    }

    // 3. 创建临时打包目录
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempDir.path, "export_temp"));
    if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
    exportDir.createSync();

    // 4. 写入 data.json
    final jsonFile = File(p.join(exportDir.path, "data.json"));
    jsonFile.writeAsStringSync(jsonEncode(exportList));

    // 5. 复制媒体文件
    for (var path in filesToZip) {
      final file = File(path);
      if (file.existsSync()) {
        file.copySync(p.join(exportDir.path, p.basename(path)));
      }
    }

    // 6. 压缩为 .cs2pkg
    final encoder = ZipFileEncoder();
    final zipPath = p.join(tempDir.path, "share_data.cs2pkg");
    encoder.create(zipPath);
    encoder.addDirectory(exportDir);
    encoder.close();
    if (!context.mounted) return;

    // 弹出底部菜单
    showModalBottomSheet(
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
                Share.shareXFiles([XFile(zipPath)], text: "CS2 道具数据分享");
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.folder_open, color: Colors.orangeAccent),
              title:
                  const Text("保存到手机文件夹", style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await _saveToFolder(context, zipPath);
              },
            ),
          ],
        ),
      ),
    );
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

  /// 从指定路径导入数据（支持拖拽导入）
  Future<String> importFromPath(String filePath) async {
    if (!filePath.toLowerCase().endsWith('.cs2pkg')) {
      return "请选择 .cs2pkg 格式的文件";
    }

    final file = File(filePath);

    // 使用当前 isar 实例的目录作为数据存储目录
    // 这样可以避免异步调用 SharedPreferences 可能导致的问题
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
    int count = 0;
    int skipped = 0;

    await isar.writeTxn(() async {
      for (var item in jsonData) {
        final mapName = item['mapName'];
        final layerName = item['layerName'];

        // 查找地图
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

        // 检查重复
        final title = item['title'] as String;
        final xRatio = (item['x'] as num).toDouble();
        final yRatio = (item['y'] as num).toDouble();

        await layer.grenades.load();
        bool exists = layer.grenades.any((g) =>
            g.title == title &&
            (g.xRatio - xRatio).abs() < 0.01 &&
            (g.yRatio - yRatio).abs() < 0.01);

        if (exists) {
          skipped++;
          continue;
        }

        // 创建 Grenade
        final g = Grenade(
          title: title,
          type: item['type'],
          team: item['team'],
          xRatio: xRatio,
          yRatio: yRatio,
          isNewImport: true,
          created: DateTime.fromMillisecondsSinceEpoch(item['createdAt']),
          updated: DateTime.now(),
        );
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
              final savePath = p.join(dataPath,
                  "${DateTime.now().millisecondsSinceEpoch}_$fileName");
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
        count++;
      }
    });

    if (count == 0 && skipped > 0) {
      return "所有 $skipped 个道具已存在，无需导入";
    } else if (skipped > 0) {
      return "成功导入 $count 个道具，跳过 $skipped 个已存在";
    }
    return "成功导入 $count 个道具";
  }

  Future<void> _saveToFolder(BuildContext context, String sourcePath) async {
    String? outputDirectory =
        await FilePicker.platform.getDirectoryPath(dialogTitle: "请选择保存位置");

    if (outputDirectory == null) return;

    try {
      final fileName =
          "cs2_tactics_backup_${DateTime.now().millisecondsSinceEpoch}.cs2pkg";
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
