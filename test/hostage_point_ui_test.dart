import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/providers.dart';
import 'package:grenade_helper/spawn_point_data.dart';
import 'package:grenade_helper/widgets/app_svg_icon.dart';

void main() {
  testWidgets('ui_hostage.svg asset loads and renders via AppSvgIcon',
      (tester) async {
    final svgContent = await rootBundle.loadString('assets/icons/ui_hostage.svg');
    expect(svgContent, contains('<svg'));
    expect(svgContent, contains('<circle'));
    expect(svgContent, contains('<path'));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppSvgIcon(
              asset: 'assets/icons/ui_hostage.svg',
              size: 17,
              color: Color(0xFF34D399),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppSvgIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('spawnPointData flags hostage maps vs defusal maps accurately', () {
    expect(spawnPointData['office']?.hasHostageSpawns, isTrue);
    expect(spawnPointData['italy']?.hasHostageSpawns, isTrue);
    expect(spawnPointData['mirage']?.hasHostageSpawns, isFalse);
  });

  test('spawn and hostage toggle providers default to false', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(showSpawnPointsProvider), isFalse);
    expect(container.read(showHostagePointsProvider), isFalse);
  });
}
