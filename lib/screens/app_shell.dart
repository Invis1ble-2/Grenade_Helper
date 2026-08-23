import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../theme/app_design_system.dart';
import 'about_screen.dart';
import 'data_transfer_hub_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  final SettingsService? settingsService;
  final Future<void> Function(HotkeyAction, HotkeyConfig)? onHotkeyChanged;
  final Future<void> Function()? onHotkeysReset;

  const AppShell({
    super.key,
    this.settingsService,
    this.onHotkeyChanged,
    this.onHotkeysReset,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  List<Widget> get _pages => [
        const HomeScreen(embedded: true),
        const DataTransferHubScreen(),
        SettingsScreen(
          settingsService: widget.settingsService,
          onHotkeyChanged: widget.onHotkeyChanged,
          onHotkeysReset: widget.onHotkeysReset,
        ),
      ];

  static const _destinations = [
    NavigationRailDestination(
        icon: Icon(Icons.map_outlined),
        selectedIcon: Icon(Icons.map_rounded),
        label: Text('地图库')),
    NavigationRailDestination(
        icon: Icon(Icons.swap_horiz_rounded),
        selectedIcon: Icon(Icons.sync_alt_rounded),
        label: Text('数据传输')),
    NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune_rounded),
        label: Text('设置')),
  ];

  @override
  Widget build(BuildContext context) {
    final mobile = AppBreakpoints.isMobile(context);
    final expanded = AppBreakpoints.isExpandedNavigation(context);
    final content = IndexedStack(index: _index, children: _pages);

    if (mobile) {
      return Scaffold(
        extendBody: true,
        body: content,
        bottomNavigationBar: _LiquidGlassNavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: expanded,
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: expanded
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const _AppLogo(size: 30),
                      const SizedBox(width: 10),
                      const Text('Grenade Helper',
                          style: TextStyle(fontWeight: FontWeight.w700))
                    ])
                  : const Tooltip(
                      message: 'Grenade Helper', child: _AppLogo(size: 32)),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    tooltip: '关于',
                    icon: const Icon(Icons.info_outline_rounded),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutScreen())),
                  ),
                ),
              ),
            ),
            destinations: _destinations,
          ),
          VerticalDivider(width: 1, color: context.appTheme.subtleBorder),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _LiquidGlassNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _LiquidGlassNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _items = [
    (Icons.map_outlined, Icons.map_rounded, '地图库'),
    (Icons.swap_horiz_rounded, Icons.sync_alt_rounded, '传输'),
    (Icons.tune_outlined, Icons.tune_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return SafeArea(
      minimum: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        AppBreakpoints.mobileBottomBarMinimumSafeArea,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: SizedBox(
            height: AppBreakpoints.mobileBottomBarHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF22262B) : Colors.white)
                        .withValues(alpha: isDark ? 0.42 : 0.34),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: isDark ? 0.15 : 0.09),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.28 : 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _GlassRefractionPainter(
                              primary: primary,
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
                      AnimatedAlign(
                        alignment: Alignment(
                          -1.0 + selectedIndex,
                          0,
                        ),
                        duration: AppMotion.panel,
                        curve: AppMotion.enter,
                        child: FractionallySizedBox(
                          widthFactor: 1 / _items.length,
                          heightFactor: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: BackdropFilter(
                                filter:
                                    ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(
                                            alpha: isDark ? 0.16 : 0.42),
                                        primary.withValues(
                                            alpha: isDark ? 0.20 : 0.11),
                                        Colors.white.withValues(
                                            alpha: isDark ? 0.04 : 0.15),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: primary.withValues(
                                          alpha: isDark ? 0.48 : 0.24),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withValues(alpha: 0.14),
                                        blurRadius: 13,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (var index = 0; index < _items.length; index++)
                            Expanded(
                              child: _LiquidGlassNavigationItem(
                                icon: _items[index].$1,
                                selectedIcon: _items[index].$2,
                                label: _items[index].$3,
                                selected: selectedIndex == index,
                                primary: primary,
                                onTap: () => onDestinationSelected(index),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassNavigationItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  const _LiquidGlassNavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: AppBreakpoints.mobileBottomBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon,
                  size: 22, color: selected ? primary : muted),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? primary : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassRefractionPainter extends CustomPainter {
  final Color primary;
  final bool isDark;

  const _GlassRefractionPainter({required this.primary, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height * 0.32;
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;

    highlight.color = Colors.white.withValues(alpha: isDark ? 0.25 : 0.58);
    canvas.drawArc(
      Rect.fromLTWH(
          -size.width * 0.08, -size.height * 0.33, size.width * 0.72, radius),
      0.12,
      1.1,
      false,
      highlight,
    );
    highlight.color =
        const Color(0xFF67D7FF).withValues(alpha: isDark ? 0.14 : 0.10);
    canvas.drawArc(
      Rect.fromLTWH(
          size.width * 0.48, size.height * 0.58, size.width * 0.66, radius),
      3.25,
      1.0,
      false,
      highlight,
    );
    highlight.color =
        const Color(0xFFFF8AC7).withValues(alpha: isDark ? 0.11 : 0.08);
    canvas.drawArc(
      Rect.fromLTWH(
          size.width * 0.58, -size.height * 0.2, size.width * 0.55, radius),
      1.65,
      0.68,
      false,
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRefractionPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.isDark != isDark;
}

class _AppLogo extends StatelessWidget {
  final double size;

  const _AppLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        'assets/icons/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
