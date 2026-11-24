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
import 'package:grenade_helper/services/area_service.dart';
import 'package:grenade_helper/services/tag_service.dart';
import 'package:grenade_helper/theme/app_design_system.dart';
import 'package:grenade_helper/widgets/grenade_tag_editor.dart';
import 'package:grenade_helper/widgets/selectable_grenade_list_item.dart';
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
            final candidates = <(Abi, List<String>)>[
              (Abi.windowsX64, ['windows', 'libisar.dll']),
              (Abi.linuxX64, ['linux', 'libisar.so']),
              (Abi.macosX64, ['macos', 'libisar.dylib']),
              (Abi.macosArm64, ['macos', 'libisar.dylib']),
            ];
            for (final (abi, segments) in candidates) {
              final libFile = File(p.joinAll([rootPath, ...segments]));
              if (await libFile.exists()) {
                libraries[abi] = libFile.path;
              }
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

  testWidgets(
      'GrenadeTagEditor cleans dirty role links on tapping 通用 without deleting custom role tags',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
    late Directory tempDir;
    late Isar isar;
    late GameMap map;
    late Tag roleAll;
    late Tag roleCt;
    late Tag roleT;
    late Tag customRoleTag;
    late Grenade grenade;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gh_dirty_role_');
      isar = await _openTestIsar(tempDir, 'dirty_role_test');
      map = GameMap(name: 'Mirage', backgroundPath: '');
      roleAll = Tag(
        name: '通用',
        colorValue: 0xFF9C27B0,
        dimension: TagDimension.role,
        isSystem: true,
        sortOrder: 0,
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
        sortOrder: 2,
        mapId: 0,
      );
      customRoleTag = Tag(
        name: '狙击手',
        colorValue: 0xFF2196F3,
        dimension: TagDimension.role,
        isSystem: false,
        sortOrder: 3,
        mapId: 0,
      );
      grenade = Grenade(
        title: '历史脏数据道具',
        type: GrenadeType.smoke,
        team: TeamType.all,
        hasLocalEdits: false,
        xRatio: 0.3,
        yRatio: 0.4,
      );

      isar.writeTxnSync(() {
        isar.gameMaps.putSync(map);
        for (final tag in [roleAll, roleCt, roleT, customRoleTag]) {
          tag.mapId = map.id;
        }
        isar.tags.putAllSync([roleAll, roleCt, roleT, customRoleTag]);
        isar.grenades.putSync(grenade);
        isar.grenadeTags.putAllSync([
          GrenadeTag(grenadeId: grenade.id, tagId: roleCt.id),
          GrenadeTag(grenadeId: grenade.id, tagId: roleT.id),
          GrenadeTag(grenadeId: grenade.id, tagId: customRoleTag.id),
        ]);
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

      expect(isar.grenades.getSync(grenade.id)?.hasLocalEdits, isFalse);

      await tester.tap(find.text('通用'));
      await tester.pump();
      await _pumpUntil(tester, () => changeCallbacks == 1);

      final linksAfterClean =
          isar.grenadeTags.filter().grenadeIdEqualTo(grenade.id).findAllSync();
      expect(
        linksAfterClean.map((e) => e.tagId).toSet(),
        {roleAll.id, customRoleTag.id},
      );
      expect(isar.grenades.getSync(grenade.id)?.team, TeamType.all);
      expect(isar.grenades.getSync(grenade.id)?.hasLocalEdits, isTrue);

      await tester.tap(find.text('通用'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(changeCallbacks, 1);
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
      'GrenadeDetailScreen aligns read-only role tag fallback and cleans impact data when switching to wallbang',
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
    late Tag roleAll;
    late Tag roleCt;
    late Grenade zeroLengthSmoke;
    late Grenade nonZeroSmoke;
    late Grenade steplessNoImpact;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gh_switch_wallbang_');
      isar = await _openTestIsar(tempDir, 'switch_wallbang_test');
      map = GameMap(name: 'Mirage', backgroundPath: '');
      layer = MapLayer(name: 'Default', assetPath: '', sortOrder: 0);
      roleAll = Tag(
        name: '通用',
        colorValue: 0xFF9C27B0,
        dimension: TagDimension.role,
        isSystem: true,
        sortOrder: 0,
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
      zeroLengthSmoke = Grenade(
        title: '爆点模式新建烟',
        type: GrenadeType.smoke,
        team: TeamType.ct,
        xRatio: 0.4,
        yRatio: 0.5,
      )
        ..impactXRatio = 0.4
        ..impactYRatio = 0.5
        ..impactAreaStrokes = '[{"points":[[0.4,0.5]],"widthRatio":0.05}]';
      nonZeroSmoke = Grenade(
        title: '普通爆点烟',
        type: GrenadeType.smoke,
        team: TeamType.ct,
        xRatio: 0.2,
        yRatio: 0.3,
      )
        ..impactXRatio = 0.7
        ..impactYRatio = 0.6
        ..impactGroupId = 42
        ..impactAreaStrokes = '[{"points":[[0.7,0.6]],"widthRatio":0.05}]';
      final step = GrenadeStep(title: '站位', description: '测试步骤', stepIndex: 0);
      steplessNoImpact = Grenade(
        title: '无步骤无爆点道具',
        type: GrenadeType.smoke,
        team: TeamType.ct,
        xRatio: 0.25,
        yRatio: 0.25,
      );

      isar.writeTxnSync(() {
        isar.gameMaps.putSync(map);
        roleAll.mapId = map.id;
        roleCt.mapId = map.id;
        isar.tags.putAllSync([roleAll, roleCt]);
        isar.mapLayers.putSync(layer);
        map.layers.add(layer);
        map.layers.saveSync();
        isar.grenades
            .putAllSync([zeroLengthSmoke, nonZeroSmoke, steplessNoImpact]);
        zeroLengthSmoke.layer.value = layer;
        zeroLengthSmoke.layer.saveSync();
        nonZeroSmoke.layer.value = layer;
        nonZeroSmoke.layer.saveSync();
        steplessNoImpact.layer.value = layer;
        steplessNoImpact.layer.saveSync();
        isar.grenadeSteps.putSync(step);
        zeroLengthSmoke.steps.add(step);
        zeroLengthSmoke.steps.saveSync();
      });
    });

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('readonly_stepless_tags'),
              grenadeId: steplessNoImpact.id,
              isEditing: false,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('CT方').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('CT方'), findsOneWidget);
      expect(find.text('暂无教学步骤'), findsOneWidget);
      expect(find.text('未绑定标签'), findsNothing);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('readonly_fallback'),
              grenadeId: zeroLengthSmoke.id,
              isEditing: false,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('CT方').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(find.text('CT方'), findsOneWidget);
      expect(find.text('未绑定标签'), findsNothing);
      expect(isar.grenadeTags.countSync(), 0);
      expect(isar.grenades.getSync(zeroLengthSmoke.id)?.hasLocalEdits, isFalse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('zero_to_wallbang'),
              grenadeId: zeroLengthSmoke.id,
              isEditing: true,
              pickThrowPoint: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.byType(DropdownButton<int>).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('穿点').last);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('尚未设置穿线').evaluate().isNotEmpty,
      );

      final convertedZero = isar.grenades.getSync(zeroLengthSmoke.id);
      expect(convertedZero?.type, GrenadeType.wallbang);
      expect(convertedZero?.impactXRatio, isNull);
      expect(convertedZero?.impactYRatio, isNull);
      expect(convertedZero?.impactAreaStrokes, isNull);
      expect(find.text('已设置'), findsNothing);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('nonzero_to_wallbang'),
              grenadeId: nonZeroSmoke.id,
              isEditing: true,
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.text('修改爆点').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('穿点').last);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('尚未设置穿线').evaluate().isNotEmpty,
      );

      final convertedNonZero = isar.grenades.getSync(nonZeroSmoke.id);
      expect(convertedNonZero?.type, GrenadeType.wallbang);
      expect(convertedNonZero?.impactXRatio, isNull);
      expect(convertedNonZero?.impactYRatio, isNull);
      expect(convertedNonZero?.impactAreaStrokes, isNull);
      expect(convertedNonZero?.impactGroupId, isNull);
      expect(find.text('设置穿线'), findsOneWidget);
      expect(find.text('已设置'), findsNothing);

      // 给穿点设置穿线后再切回普通道具，应同步清除已设置的穿线
      isar.writeTxnSync(() {
        final latest = isar.grenades.getSync(nonZeroSmoke.id)!;
        latest.impactXRatio = 0.8;
        latest.impactYRatio = 0.2;
        isar.grenades.putSync(latest);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [isarProvider.overrideWithValue(isar)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: GrenadeDetailScreen(
              key: const ValueKey('wallbang_to_smoke'),
              grenadeId: nonZeroSmoke.id,
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

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('烟雾').last);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('尚未设置爆点').evaluate().isNotEmpty,
      );

      final convertedBack = isar.grenades.getSync(nonZeroSmoke.id);
      expect(convertedBack?.type, GrenadeType.smoke);
      expect(convertedBack?.impactXRatio, isNull);
      expect(convertedBack?.impactYRatio, isNull);
      expect(convertedBack?.impactAreaStrokes, isNull);
      expect(convertedBack?.impactGroupId, isNull);
      expect(find.text('设置爆点'), findsOneWidget);
      expect(find.text('已设置'), findsNothing);
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
      'SelectableGrenadeListItem distinguishes 穿线 and 爆点 badges and AreaService excludes wallbang in impact mode',
      timeout: const Timeout(Duration(seconds: 30)),
      (tester) async {
    late Directory tempDir;
    late Isar isar;
    late GameMap map;
    late MapLayer layer;
    late Grenade smoke;
    late Grenade wallbang;
    late Grenade zeroWallbang;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gh_downstream_');
      isar = await _openTestIsar(tempDir, 'downstream_test');
      map = GameMap(name: 'Mirage', backgroundPath: '');
      layer = MapLayer(name: 'Default', assetPath: '', sortOrder: 0);
      smoke = Grenade(
        title: 'A点烟',
        type: GrenadeType.smoke,
        xRatio: 0.1,
        yRatio: 0.1,
      )
        ..impactXRatio = 0.5
        ..impactYRatio = 0.5;
      wallbang = Grenade(
        title: 'A点穿点',
        type: GrenadeType.wallbang,
        xRatio: 0.1,
        yRatio: 0.1,
      )
        ..impactXRatio = 0.5
        ..impactYRatio = 0.5;
      zeroWallbang = Grenade(
        title: '零长度穿点',
        type: GrenadeType.wallbang,
        xRatio: 0.5,
        yRatio: 0.5,
      )
        ..impactXRatio = 0.5
        ..impactYRatio = 0.5;

      isar.writeTxnSync(() {
        isar.gameMaps.putSync(map);
        isar.mapLayers.putSync(layer);
        map.layers.add(layer);
        map.layers.saveSync();
        isar.grenades.putAllSync([smoke, wallbang, zeroWallbang]);
        for (final g in [smoke, wallbang, zeroWallbang]) {
          g.layer.value = layer;
          g.layer.saveSync();
        }
      });
    });

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ListView(
              children: [
                SelectableGrenadeListItem(
                  grenade: smoke,
                  selected: false,
                  onChanged: (_) {},
                  onPreview: () {},
                ),
                SelectableGrenadeListItem(
                  grenade: wallbang,
                  selected: false,
                  onChanged: (_) {},
                  onPreview: () {},
                ),
                SelectableGrenadeListItem(
                  grenade: zeroWallbang,
                  selected: false,
                  onChanged: (_) {},
                  onPreview: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('爆点'), findsOneWidget);
      expect(find.text('穿线'), findsOneWidget);
      expect(find.byIcon(Icons.north_east_rounded), findsOneWidget);

      await tester.runAsync(() async {
        final areaService = AreaService(isar);
        final area = await areaService.createArea(
          name: '中路区域',
          colorValue: 0xFF4CAF50,
          strokes: jsonEncode([
            {
              'points': [
                [0.45, 0.45],
                [0.55, 0.45],
                [0.55, 0.55],
                [0.45, 0.55],
              ],
              'isShape': true,
              'widthRatio': 0.02,
            }
          ]),
          mapId: map.id,
          layerId: layer.id,
        );

        final allSummary = await areaService.autoTagAllGrenades(
          map.id,
          useImpactPoint: true,
        );
        expect(allSummary.processedGrenades, 1);
        expect(allSummary.matchedGrenades, 1);

        final singleSummary = await areaService.syncAreaTag(
          area,
          useImpactPoint: true,
        );
        expect(singleSummary.processedGrenades, 1);
        expect(singleSummary.matchedGrenades, 1);

        final smokeLinks = await isar.grenadeTags
            .filter()
            .grenadeIdEqualTo(smoke.id)
            .findAll();
        final wallbangLinks = await isar.grenadeTags
            .filter()
            .grenadeIdEqualTo(wallbang.id)
            .findAll();
        expect(smokeLinks.map((e) => e.tagId), contains(area.tagId));
        expect(wallbangLinks, isEmpty);
      });
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
