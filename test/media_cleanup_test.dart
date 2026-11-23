import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/services/data_service.dart';
import 'package:grenade_helper/services/media_handle_service.dart';
import 'package:grenade_helper/services/migration_service.dart';
import 'package:grenade_helper/services/settings_service.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

Future<void> _initIsarCoreForTest() async {
  final libraries = <Abi, String>{};
  final packageConfigFile =
      File(p.join(Directory.current.path, '.dart_tool', 'package_config.json'));
  if (await packageConfigFile.exists()) {
    final decoded = jsonDecode(await packageConfigFile.readAsString());
    if (decoded is Map && decoded['packages'] is List) {
      for (final pkg in decoded['packages'] as List) {
        if (pkg is Map && pkg['name'] == 'isar_community_flutter_libs') {
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri != null && rootUri.isNotEmpty) {
            final rootPath = Uri.parse(rootUri).toFilePath();
            final winDll = File(p.join(rootPath, 'windows', 'libisar.dll'));
            if (await winDll.exists()) {
              libraries[Abi.windowsX64] = winDll.path;
            }
          }
          break;
        }
      }
    }
  }
  await Isar.initializeIsarCore(libraries: libraries);
}

Future<Isar> _openTestIsar(Directory dir, String name) {
  return Isar.open(
    [
      GameMapSchema,
      MapLayerSchema,
      GrenadeSchema,
      GrenadeStepSchema,
      StepMediaSchema,
      ImportHistorySchema,
      ImpactGroupSchema,
      FavoriteFolderSchema,
      TagSchema,
      GrenadeTagSchema,
      MapAreaSchema,
    ],
    directory: dir.path,
    name: name,
  );
}

void main() {
  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  tearDown(() {
    MediaHandleService.externalReleaser = null;
  });

  test('deleteStep cascades StepMedia rows and deletes unused files only',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_step_delete_');
    final isar = await _openTestIsar(tempDir, 'step_delete_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final uniqueImg = File(p.join(tempDir.path, 'unique.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final uniqueVid = File(p.join(tempDir.path, 'unique.mp4'))
      ..writeAsBytesSync([4, 5, 6]);
    final sharedImg = File(p.join(tempDir.path, 'shared.jpg'))
      ..writeAsBytesSync([7, 8, 9]);

    final map = GameMap(name: 'Mirage', backgroundPath: 'assets/bg.webp');
    final layer =
        MapLayer(name: 'Default', assetPath: 'assets/radar.svg', sortOrder: 0);
    final grenade =
        Grenade(title: 'A Smoke', type: GrenadeType.smoke, xRatio: 0.5, yRatio: 0.5);
    final step1 = GrenadeStep(title: 'S1', description: 'D1', stepIndex: 0);
    final step2 = GrenadeStep(title: 'S2', description: 'D2', stepIndex: 1);
    final m1 = StepMedia(localPath: uniqueImg.path, type: MediaType.image);
    final m2 = StepMedia(localPath: uniqueVid.path, type: MediaType.video);
    final m3 = StepMedia(localPath: sharedImg.path, type: MediaType.image);
    final m4 = StepMedia(localPath: sharedImg.path, type: MediaType.image);

    await isar.writeTxn(() async {
      await isar.gameMaps.put(map);
      await isar.mapLayers.put(layer);
      map.layers.add(layer);
      await map.layers.save();

      await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();

      await isar.grenadeSteps.putAll([step1, step2]);
      grenade.steps.addAll([step1, step2]);
      await grenade.steps.save();

      await isar.stepMedias.putAll([m1, m2, m3, m4]);
      step1.medias.addAll([m1, m2, m3]);
      await step1.medias.save();
      step2.medias.add(m4);
      await step2.medias.save();
    });

    final dataService = DataService(isar);
    final failed = await dataService.deleteStep(step1);

    expect(failed, isEmpty);
    expect(await isar.grenadeSteps.count(), 1);
    expect(await isar.stepMedias.count(), 1);
    expect(uniqueImg.existsSync(), isFalse);
    expect(uniqueVid.existsSync(), isFalse);
    expect(sharedImg.existsSync(), isTrue);
  });

  test('deleteStepMedia releases locked video handle before deleting file',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_video_lock_');
    final isar = await _openTestIsar(tempDir, 'video_lock_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final videoFile = File(p.join(tempDir.path, 'locked.mp4'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    RandomAccessFile? handle = await videoFile.open(mode: FileMode.append);
    final token = Object();
    var localReleased = false;
    var externalReleased = false;

    MediaHandleService.register(token, videoFile.path, () async {
      localReleased = true;
      await handle?.close();
      handle = null;
    });
    MediaHandleService.externalReleaser = (paths) async {
      externalReleased = paths.isNotEmpty;
    };
    addTearDown(() async {
      MediaHandleService.unregister(token);
      await handle?.close();
    });

    final map = GameMap(name: 'Inferno', backgroundPath: 'assets/bg.webp');
    final layer =
        MapLayer(name: 'Default', assetPath: 'assets/radar.svg', sortOrder: 0);
    final grenade =
        Grenade(title: 'B Molotov', type: GrenadeType.molotov, xRatio: 0.2, yRatio: 0.3);
    final step = GrenadeStep(title: 'S1', description: 'D1', stepIndex: 0);
    final media = StepMedia(localPath: videoFile.path, type: MediaType.video);

    await isar.writeTxn(() async {
      await isar.gameMaps.put(map);
      await isar.mapLayers.put(layer);
      map.layers.add(layer);
      await map.layers.save();
      await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
      await isar.grenadeSteps.put(step);
      grenade.steps.add(step);
      await grenade.steps.save();
      await isar.stepMedias.put(media);
      step.medias.add(media);
      await step.medias.save();
    });

    final deleted = await DataService(isar).deleteStepMedia(media);

    expect(localReleased, isTrue);
    expect(externalReleased, isTrue);
    expect(deleted, isTrue);
    expect(videoFile.existsSync(), isFalse);
    expect(await isar.stepMedias.count(), 0);
  });

  test(
      'scanOrphanMediaFiles catches orphan-DB-shielded files, preserves custom maps, and skips flutter_assets',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_orphan_scan_');
    final isar = await _openTestIsar(tempDir, 'orphan_scan_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final liveImg = File(p.join(tempDir.path, 'live.jpg'))
      ..writeAsBytesSync([1]);
    final customBg = File(p.join(tempDir.path, 'custom_bg.png'))
      ..writeAsBytesSync([2]);
    final customIcon = File(p.join(tempDir.path, 'custom_icon.svg'))
      ..writeAsBytesSync([3]);
    final customRadar = File(p.join(tempDir.path, 'custom_radar.webp'))
      ..writeAsBytesSync([4]);
    final shieldedByOrphanMedia =
        File(p.join(tempDir.path, 'from_deleted_step.jpg'))
          ..writeAsBytesSync([5]);
    final orphanWmv = File(p.join(tempDir.path, 'unused.wmv'))
      ..writeAsBytesSync([6]);
    final flutterAsset =
        File(p.join(tempDir.path, 'flutter_assets', 'assets', 'icon.png'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([7]);

    final map = GameMap(
      name: 'CustomCache',
      backgroundPath: customBg.path,
      iconPath: customIcon.path,
    );
    final layer =
        MapLayer(name: 'Default', assetPath: customRadar.path, sortOrder: 0);
    final grenade =
        Grenade(title: 'Mid Smoke', type: GrenadeType.smoke, xRatio: 0.5, yRatio: 0.5);
    final liveStep = GrenadeStep(title: 'Live', description: 'Live', stepIndex: 0);
    final liveMedia = StepMedia(localPath: liveImg.path, type: MediaType.image);
    final orphanStep =
        GrenadeStep(title: 'OrphanStep', description: 'Dead', stepIndex: 1);
    final orphanMedia = StepMedia(
        localPath: shieldedByOrphanMedia.path, type: MediaType.image);

    await isar.writeTxn(() async {
      await isar.gameMaps.put(map);
      await isar.mapLayers.put(layer);
      map.layers.add(layer);
      await map.layers.save();
      await isar.grenades.put(grenade);
      grenade.layer.value = layer;
      await grenade.layer.save();
      await isar.grenadeSteps.putAll([liveStep, orphanStep]);
      grenade.steps.add(liveStep);
      await grenade.steps.save();
      await isar.stepMedias.putAll([liveMedia, orphanMedia]);
      liveStep.medias.add(liveMedia);
      await liveStep.medias.save();
    });

    final dataService = DataService(isar);
    final scan = await dataService.scanOrphanMediaFiles();
    final scannedPaths =
        scan.orphanFiles.map((e) => DataService.normalizeMediaPath(e.path)).toSet();

    expect(
      scannedPaths,
      equals({
        DataService.normalizeMediaPath(shieldedByOrphanMedia.path),
        DataService.normalizeMediaPath(orphanWmv.path),
      }),
    );
    expect(scan.orphanStepIds, equals([orphanStep.id]));
    expect(scan.orphanMediaIds, equals([orphanMedia.id]));

    final cleanup = await dataService.cleanupOrphanMediaFiles(
      scan.orphanFiles,
      orphanStepIds: scan.orphanStepIds,
      orphanMediaIds: scan.orphanMediaIds,
    );

    expect(cleanup.failedFiles, isEmpty);
    expect(cleanup.deletedFiles.length, 2);
    expect(cleanup.deletedStepRecords, 1);
    expect(cleanup.deletedMediaRecords, 1);

    expect(shieldedByOrphanMedia.existsSync(), isFalse);
    expect(orphanWmv.existsSync(), isFalse);
    expect(liveImg.existsSync(), isTrue);
    expect(customBg.existsSync(), isTrue);
    expect(customIcon.existsSync(), isTrue);
    expect(customRadar.existsSync(), isTrue);
    expect(flutterAsset.existsSync(), isTrue);
  });

  test('deleteGrenades cleans steps, medias, and files even when layer is null',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_null_layer_');
    final isar = await _openTestIsar(tempDir, 'null_layer_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final img = File(p.join(tempDir.path, 'orphan_grenade.jpg'))
      ..writeAsBytesSync([1, 2]);
    final grenade = Grenade(
        title: 'Detached', type: GrenadeType.he, xRatio: 0.1, yRatio: 0.1);
    final step = GrenadeStep(title: 'S', description: 'D', stepIndex: 0);
    final media = StepMedia(localPath: img.path, type: MediaType.image);

    await isar.writeTxn(() async {
      await isar.grenades.put(grenade);
      await isar.grenadeSteps.put(step);
      grenade.steps.add(step);
      await grenade.steps.save();
      await isar.stepMedias.put(media);
      step.medias.add(media);
      await step.medias.save();
    });

    await DataService(isar).deleteGrenades([grenade]);

    expect(await isar.grenades.count(), 0);
    expect(await isar.grenadeSteps.count(), 0);
    expect(await isar.stepMedias.count(), 0);
    expect(img.existsSync(), isFalse);
  });

  test('migrateMediaPathsToCurrentDirectory rewrites relocated local paths only',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('gh_migrate_paths_');
    final isar = await _openTestIsar(tempDir, 'migrate_paths_test');
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final migratedMediaFile = File(p.join(tempDir.path, 'pic.jpg'))
      ..writeAsBytesSync([1]);
    final migratedBgFile = File(p.join(tempDir.path, 'bg.png'))
      ..writeAsBytesSync([2]);
    final migratedRadarFile = File(p.join(tempDir.path, 'radar.webp'))
      ..writeAsBytesSync([3]);

    final media = StepMedia(
      localPath: r'C:\OldLocation\data\pic.jpg',
      type: MediaType.image,
    );
    final customMap = GameMap(
      name: 'Custom',
      backgroundPath: r'C:\OldLocation\data\bg.png',
      iconPath: 'assets/icons/mirage_icon.svg',
    );
    final customLayer = MapLayer(
      name: 'Default',
      assetPath: r'C:\OldLocation\data\radar.webp',
      sortOrder: 0,
    );

    await isar.writeTxn(() async {
      await isar.stepMedias.put(media);
      await isar.gameMaps.put(customMap);
      await isar.mapLayers.put(customLayer);
    });

    final migratedCount =
        await MigrationService(isar).migrateMediaPathsToCurrentDirectory();

    expect(migratedCount, 3);
    final updatedMedia = await isar.stepMedias.get(media.id);
    final updatedMap = await isar.gameMaps.get(customMap.id);
    final updatedLayer = await isar.mapLayers.get(customLayer.id);

    expect(updatedMedia?.localPath, migratedMediaFile.path);
    expect(updatedMap?.backgroundPath, migratedBgFile.path);
    expect(updatedMap?.iconPath, 'assets/icons/mirage_icon.svg');
    expect(updatedLayer?.assetPath, migratedRadarFile.path);
  });

  test('SettingsService.copyDirectory skips flutter runtime and lock files',
      () async {
    final source = await Directory.systemTemp.createTemp('gh_copy_src_');
    final dest = await Directory.systemTemp.createTemp('gh_copy_dst_');
    addTearDown(() async {
      if (await source.exists()) await source.delete(recursive: true);
      if (await dest.exists()) await dest.delete(recursive: true);
    });

    File(p.join(source.path, 'default.isar')).writeAsBytesSync([1]);
    File(p.join(source.path, 'default.isar-lck')).writeAsBytesSync([2]);
    File(p.join(source.path, 'icudtl.dat')).writeAsBytesSync([3]);
    File(p.join(source.path, '12345.jpg')).writeAsBytesSync([4]);
    File(p.join(source.path, 'flutter_assets', 'kernel_blob.bin'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([5]);

    await SettingsService.copyDirectory(source, dest);

    expect(File(p.join(dest.path, 'default.isar')).existsSync(), isTrue);
    expect(File(p.join(dest.path, '12345.jpg')).existsSync(), isTrue);
    expect(File(p.join(dest.path, 'default.isar-lck')).existsSync(), isFalse);
    expect(File(p.join(dest.path, 'icudtl.dat')).existsSync(), isFalse);
    expect(Directory(p.join(dest.path, 'flutter_assets')).existsSync(), isFalse);
  });
}
