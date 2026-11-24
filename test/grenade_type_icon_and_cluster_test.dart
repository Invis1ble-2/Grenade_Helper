import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/models.dart';
import 'package:grenade_helper/screens/map_screen.dart';
import 'package:grenade_helper/widgets/grenade_type_icon.dart';

void main() {
  testWidgets(
      'GrenadeTypeIcon preserves requested size and centers inside unaligned fixed Container',
      (tester) async {
    final previousUseLegacy = GrenadeTypeIcon.useLegacy;
    GrenadeTypeIcon.useLegacy = false;
    addTearDown(() => GrenadeTypeIcon.useLegacy = previousUseLegacy);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Container(
              key: const Key('fixed-circle'),
              width: 28,
              height: 28,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: const GrenadeTypeIcon(
                type: GrenadeType.smoke,
                size: 11.5,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final containerFinder = find.byKey(const Key('fixed-circle'));
    final svgFinder = find.byType(SvgPicture);
    expect(tester.getSize(containerFinder), const Size(28, 28));
    expect(tester.getSize(svgFinder), const Size(11.5, 11.5));
    expect(tester.getCenter(svgFinder), tester.getCenter(containerFinder));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GrenadeTypeIcon shrinks to icon size under loose constraints',
      (tester) async {
    final previousUseLegacy = GrenadeTypeIcon.useLegacy;
    GrenadeTypeIcon.useLegacy = false;
    addTearDown(() => GrenadeTypeIcon.useLegacy = previousUseLegacy);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GrenadeTypeIcon(
              type: GrenadeType.wallbang,
              size: 11.5,
              color: Colors.cyan,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(GrenadeTypeIcon)), const Size(11.5, 11.5));
    expect(tester.getSize(find.byType(SvgPicture)), const Size(11.5, 11.5));
    expect(tester.takeException(), isNull);
  });

  test('clusterGrenadesByImpact excludes wallbang grenades even with line coordinates',
      () {
    final he = Grenade(
      title: 'HE',
      type: GrenadeType.he,
      xRatio: 0.1,
      yRatio: 0.1,
    )
      ..id = 1
      ..impactXRatio = 0.25
      ..impactYRatio = 0.25;

    final smoke = Grenade(
      title: 'Smoke',
      type: GrenadeType.smoke,
      xRatio: 0.2,
      yRatio: 0.2,
    )
      ..id = 2
      ..impactXRatio = 0.75
      ..impactYRatio = 0.75;

    final smokeWithoutImpact = Grenade(
      title: 'Smoke No Impact',
      type: GrenadeType.smoke,
      xRatio: 0.3,
      yRatio: 0.3,
    )..id = 3;

    final wallbangOverlapping = Grenade(
      title: 'Wallbang Overlapping',
      type: GrenadeType.wallbang,
      xRatio: 0.4,
      yRatio: 0.4,
    )
      ..id = 4
      ..impactXRatio = 0.25
      ..impactYRatio = 0.25;

    final wallbangStandalone = Grenade(
      title: 'Wallbang Standalone',
      type: GrenadeType.wallbang,
      xRatio: 0.5,
      yRatio: 0.5,
    )
      ..id = 5
      ..impactXRatio = 0.55
      ..impactYRatio = 0.55;

    final input = [
      he,
      smoke,
      smokeWithoutImpact,
      wallbangOverlapping,
      wallbangStandalone,
    ];

    for (final threshold in [0.0, 0.05]) {
      final clusters = clusterGrenadesByImpact(input, threshold: threshold);
      final clusteredIds =
          clusters.expand((c) => c.grenades).map((g) => g.id).toList();
      expect(clusters, hasLength(2));
      expect(clusteredIds, unorderedEquals([1, 2]));
      expect(
        clusters.expand((c) => c.grenades).any((g) => g.type == GrenadeType.wallbang),
        isFalse,
      );
    }
  });
}
