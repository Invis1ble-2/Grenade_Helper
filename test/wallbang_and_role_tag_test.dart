import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/models/grenade_tag.dart';
import 'package:grenade_helper/models/map_area.dart';
import 'package:grenade_helper/models/tag.dart';
import 'package:grenade_helper/providers.dart';
import 'package:grenade_helper/screens/grenade_detail_screen.dart';
import 'package:grenade_helper/screens/impact_point_picker_screen.dart';
import 'package:grenade_helper/services/tag_service.dart';
import 'package:grenade_helper/theme/app_design_system.dart';
import 'package:grenade_helper/widgets/grenade_tag_editor.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (condition()) return;
  }
}

void main() {
  setUpAll(() async {
    await _initIsarCoreForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('roleTagToTeamType and sortTagsForDisplay map and prioritize role tags',
      () {
    Tag makeTag(String name, int dimension, int sortOrder) => Tag(
          name: name,
          colorValue: 0xFF9C27B0,
          dimension: dimension,
          sortOrder: sortOrder,
          mapId: 1,
        );

    expect(
      roleTagToTeamType(makeTag('通用', TagDimension.role, 0)),
      TeamType.all,
    );
    expect(
      roleTagToTeamType(makeTag('CT方', TagDimension.role, 0)),
      TeamType.ct,
    );
    expect(
      roleTagToTeamType(makeTag('ct', TagDimension.role, 0)),
      TeamType.ct,
    );
    expect(
      roleTagToTeamType(makeTag('T方', TagDimension.role, 0)),
      TeamType.t,
    );
    expect(
      roleTagToTeamType(makeTag('T', TagDimension.role, 0)),
      TeamType.t,
    );
    expect(
      roleTagToTeamType(makeTag('CT方', TagDimension.custom, 0)),
      isNull,
    );

    final unsorted = <Tag>[
      for (int i = 0; i < 15; i++) makeTag('区域$i', TagDimension.area, i),
      makeTag('T方', TagDimension.role, 99),
      makeTag('通用', TagDimension.role, 100),
      makeTag('CT方', TagDimension.role, 98),
    ];

    final sorted = sortTagsForDisplay(unsorted);
    expect(sorted.take(3).map((t) => t.name).toList(), ['通用', 'CT方', 'T方']);
  });

  testWidgets(
      'GrenadeTagEditor falls back to grenade.team without silent DB write and enforces exclusive role sync',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
    late Directory tempDir;
    late Isar isar;
    late GameMap map;
    late Tag roleAll;
    late Tag roleCt;
    late Tag roleT;
    late Tag areaTag;
    late Grenade grenade;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gh_role_tag_');
      isar = await _openTestIsar(tempDir, 'role_tag_test');
      map = GameMap(name: 'Mirage', backgroundPath: '');
      roleAll = Tag(
        name: '通用',
        colorValue: 0xFF9C27B0,
        dimension: TagDimension.role,
        isSystem: true,
        sortOrder: 2,
        mapId: 0,
      );
      roleCt = Tag(
        name: 'CT方',
        colorValue: 0xFF9C27B0,
        dimension: TagDimension.role,
        isSystem: true,
        sortOrder: 1,
        mapId: 0,
      );
      roleT = Tag(
        name: 'T方',
        colorValue: 0xFF9C27B0,
        dimension: TagDimension.role,
        isSystem: true,
        sortOrder: 0,
        mapId: 0,
      );
      areaTag = Tag(
        name: 'A点',
        colorValue: 0xFF4CAF50,
        dimension: TagDimension.area,
        isSystem: true,
        sortOrder: 3,
        mapId: 0,
      );
      grenade = Grenade(
        title: 'A1 烟雾',
        type: GrenadeType.smoke,
        team: TeamType.ct,
        hasLocalEdits: false,
        xRatio: 0.3,
        yRatio: 0.4,
      );

      isar.writeTxnSync(() {
        isar.gameMaps.putSync(map);
        for (final tag in [roleAll, roleCt, roleT, areaTag]) {
          tag.mapId = map.id;
        }
        isar.tags.putAllSync([roleAll, roleCt, roleT, areaTag]);
        isar.grenades.putSync(grenade);
        isar.grenadeTags.putSync(
          GrenadeTag(grenadeId: grenade.id, tagId: areaTag.id),
        );
      });
    });

    try {
      var changeCallbacks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: GrenadeTagEditor(
              grenadeId: grenade.id,
              mapId: map.id,
              tagService: TagService(isar),
              onTagsChanged: () => changeCallbacks++,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('2 个已选').evaluate().isNotEmpty,
      );

      expect(find.text('2 个已选'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(isar.grenades.getSync(grenade.id)?.hasLocalEdits, isFalse);
      expect(isar.grenadeTags.countSync(), 1);

      await tester.tap(find.text('T方'));
      await tester.pump();
      await _pumpUntil(tester, () => changeCallbacks == 1);

      final afterTapT = isar.grenades.getSync(grenade.id);
      final linksAfterT =
          isar.grenadeTags.filter().grenadeIdEqualTo(grenade.id).findAllSync();
      expect(afterTapT?.team, TeamType.t);
      expect(afterTapT?.hasLocalEdits, isTrue);
      expect(linksAfterT.map((e) => e.tagId).toSet(), {areaTag.id, roleT.id});

      await tester.tap(find.text('T方'));
      await tester.pump();
      await _pumpUntil(tester, () => changeCallbacks == 2);

      final afterUntapT = isar.grenades.getSync(grenade.id);
      final linksAfterAll =
          isar.grenadeTags.filter().grenadeIdEqualTo(grenade.id).findAllSync();
      expect(afterUntapT?.team, TeamType.all);
      expect(
          linksAfterAll.map((e) => e.tagId).toSet(), {areaTag.id, roleAll.id});

      await tester.tap(find.text('通用'));
      await tester.pump();
      await _pumpUntil(tester, () => find.text('2 个已选').evaluate().isNotEmpty);

      final afterTapAll = isar.grenades.getSync(grenade.id);
      final linksStayAll =
          isar.grenadeTags.filter().grenadeIdEqualTo(grenade.id).findAllSync();
      expect(afterTapAll?.team, TeamType.all);
      expect(
          linksStayAll.map((e) => e.tagId).toSet(), {areaTag.id, roleAll.id});
      expect(find.text('2 个已选'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
    }
  });

  testWidgets(
      'ImpactPointPickerScreen switches between wallbangLineMode and standard impact mode',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
    late Directory tempDir;
    late Isar isar;
    late MapLayer layer;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gh_wallbang_pick_');
      isar = await _openTestIsar(tempDir, 'wallbang_pick_test');
      layer = MapLayer(name: 'Default', assetPath: '', sortOrder: 0);
      isar.writeTxnSync(() {
        isar.mapLayers.putSync(layer);
      });
    });

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: ImpactPointPickerScreen(
              key: const ValueKey('wallbang_edit'),
              grenadeId: 1,
              throwX: 0.25,
              throwY: 0.35,
              layerId: layer.id,
              grenadeType: GrenadeType.wallbang,
              wallbangLineMode: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('设置穿线方位').evaluate().isNotEmpty,
      );

      expect(find.text('设置穿线方位'), findsOneWidget);
      expect(find.text('穿点'), findsOneWidget);
      expect(find.text('穿线方向'), findsOneWidget);
      expect(find.text('点击地图任意位置设置穿线方位'), findsOneWidget);
      expect(find.byIcon(Icons.north_east_rounded), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PhotoView),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: ImpactPointPickerScreen(
              key: const ValueKey('wallbang_view'),
              grenadeId: 1,
              initialX: 0.75,
              initialY: 0.65,
              throwX: 0.25,
              throwY: 0.35,
              layerId: layer.id,
              grenadeType: GrenadeType.wallbang,
              readOnly: true,
              wallbangLineMode: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('查看穿线方位').evaluate().isNotEmpty,
      );

      expect(find.text('查看穿线方位'), findsOneWidget);
      expect(find.text('穿线方向'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PhotoView),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(PhotoView),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: ImpactPointPickerScreen(
              key: const ValueKey('standard_edit'),
              grenadeId: 1,
              initialX: 0.75,
              initialY: 0.65,
              throwX: 0.25,
              throwY: 0.35,
              layerId: layer.id,
              grenadeType: GrenadeType.smoke,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('选择爆点位置').evaluate().isNotEmpty,
      );

      expect(find.text('投掷点'), findsOneWidget);
      expect(find.text('爆点'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PhotoView),
          matching: find.byIcon(Icons.close),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
    }
  });

  testWidgets(
      'GrenadeDetailScreen hides top team dropdown in edit mode and handles wallbang line section',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Directory tempDir;
    late Isar isar;
    late GameMap map;
    late MapLayer layer;
    late Grenade wallbang;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gh_wallbang_detail_');
      isar = await _openTestIsar(tempDir, 'wallbang_detail_test');
      map = GameMap(name: 'Mirage', backgroundPath: '');
      layer = MapLayer(name: 'Default', assetPath: '', sortOrder: 0);
      wallbang = Grenade(
        title: 'B小木门穿点',
        type: GrenadeType.wallbang,
        team: TeamType.ct,
        xRatio: 0.2,
        yRatio: 0.3,
      );

      isar.writeTxnSync(() {
        isar.gameMaps.putSync(map);
        isar.mapLayers.putSync(layer);
        map.layers.add(layer);
        map.layers.saveSync();
        isar.grenades.putSync(wallbang);
        wallbang.layer.value = layer;
        wallbang.layer.saveSync();
      });
    });

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('edit_empty'),
              grenadeId: wallbang.id,
              isEditing: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('穿线方位').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );

      expect(find.byType(DropdownButton<int>), findsOneWidget);
      expect(find.text('穿线方位'), findsOneWidget);
      expect(find.text('尚未设置穿线'), findsOneWidget);
      expect(find.text('设置穿线'), findsOneWidget);
      expect(find.text('绘制爆点范围'), findsNothing);
      expect(find.text('清除'), findsNothing);

      isar.writeTxnSync(() {
        wallbang.impactXRatio = 0.6;
        wallbang.impactYRatio = 0.4;
        isar.grenades.putSync(wallbang);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('edit_filled'),
              grenadeId: wallbang.id,
              isEditing: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('修改穿线').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );

      expect(find.text('方位终点 (0.600, 0.400)'), findsOneWidget);
      expect(find.text('修改穿线'), findsOneWidget);
      expect(find.text('清除'), findsOneWidget);
      expect(find.text('绘制爆点范围'), findsNothing);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('view_filled'),
              grenadeId: wallbang.id,
              isEditing: false,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('查看').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );

      expect(find.text('CT'), findsOneWidget);
      expect(find.text('穿线方位'), findsOneWidget);
      expect(find.text('方位终点 (0.600, 0.400)'), findsOneWidget);
      expect(find.text('查看'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('edit_clear'),
              grenadeId: wallbang.id,
              isEditing: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('修改穿线').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );

      await tester.tap(find.text('清除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('清除穿线'), findsOneWidget);
      expect(find.text('确定要清除已设置的穿线吗？'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('清除'),
        ),
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            find.text('尚未设置穿线').evaluate().isNotEmpty &&
            find.text('穿线已清除').evaluate().isNotEmpty,
      );
      await _pumpUntil(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }

      final cleared = isar.grenades.getSync(wallbang.id);
      expect(cleared?.impactXRatio, isNull);
      expect(cleared?.impactYRatio, isNull);
      expect(cleared?.hasLocalEdits, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await isar.close(deleteFromDisk: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
    }
  });
}
