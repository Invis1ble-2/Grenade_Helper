import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grenade_helper/screens/data_transfer_hub_screen.dart';
import 'package:grenade_helper/theme/app_design_system.dart';

void main() {
  test('light and dark themes expose the expected semantic colors', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.scaffoldBackgroundColor, const Color(0xFFF4F5F6));
    expect(light.colorScheme.primary, const Color(0xFFC65D00));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0D0F12));
    expect(dark.colorScheme.primary, const Color(0xFFFFB44C));
    expect(light.extension<AppThemeExtension>(), AppThemeExtension.light);
    expect(dark.extension<AppThemeExtension>(), AppThemeExtension.dark);
  });

  testWidgets('breakpoints select mobile and expanded navigation widths',
      (tester) async {
    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Text(
              '${AppBreakpoints.isMobile(context)}:'
              '${AppBreakpoints.isExpandedNavigation(context)}',
            ),
          ),
        ),
      );
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAt(390);
    expect(find.text('true:false'), findsOneWidget);

    await pumpAt(1180);
    expect(find.text('false:false'), findsOneWidget);

    await pumpAt(1440);
    expect(find.text('false:true'), findsOneWidget);
  });

  testWidgets('data transfer hub adapts without layout overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const DataTransferHubScreen(),
      ),
    );

    expect(find.text('导入道具包'), findsOneWidget);
    expect(find.text('导出与分享'), findsOneWidget);
    expect(find.text('局域网同步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
