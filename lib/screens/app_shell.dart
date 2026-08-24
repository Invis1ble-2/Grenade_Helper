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

class _LiquidGlassNavigationBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _LiquidGlassNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  State<_LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<_LiquidGlassNavigationBar> {
  late final Future<ui.FragmentProgram> _glassProgram;
  ui.FragmentShader? _barShader;
  ui.FragmentShader? _indicatorShader;
  ui.ImageFilter? _barFilter;
  ui.ImageFilter? _indicatorFilter;

  @override
  void initState() {
    super.initState();
    _glassProgram = ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
  }

  @override
  void dispose() {
    _barShader?.dispose();
    _indicatorShader?.dispose();
    super.dispose();
  }

  static const _items = [
    (Icons.map_outlined, Icons.map_rounded, '地图库'),
    (Icons.swap_horiz_rounded, Icons.sync_alt_rounded, '传输'),
    (Icons.tune_outlined, Icons.tune_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.FragmentProgram>(
      future: _glassProgram,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget.withDetails(
            message: 'Liquid glass shader failed to load',
            error: FlutterError('${snapshot.error}'),
          );
        }
        final program = snapshot.data;
        if (program == null) {
          // Keep the layout stable while the mandatory shader asset loads.
          return const SizedBox(
            height: AppBreakpoints.mobileBottomBarHeight +
                AppBreakpoints.mobileBottomBarMinimumSafeArea,
          );
        }
        _prepareFilters(program);
        return _buildBar(context);
      },
    );
  }

  void _prepareFilters(ui.FragmentProgram program) {
    if (_barFilter != null && _indicatorFilter != null) return;

    _barShader = program.fragmentShader()
      ..setFloat(2, -118)
      ..setFloat(3, 10)
      ..setFloat(4, 0.055)
      ..setFloat(5, 0.085);
    _indicatorShader = program.fragmentShader()
      ..setFloat(2, -82)
      ..setFloat(3, 7)
      ..setFloat(4, 0.075)
      ..setFloat(5, 0.105);
    _barFilter = ui.ImageFilter.shader(_barShader!);
    _indicatorFilter = ui.ImageFilter.shader(_indicatorShader!);
  }

  Widget _buildBar(BuildContext context) {
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
              borderRadius: BorderRadius.circular(25),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropFilter(
                    filter: _barFilter!,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF101418) : Colors.white)
                            .withValues(alpha: isDark ? 0.24 : 0.11),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white
                                .withValues(alpha: isDark ? 0.10 : 0.26),
                            primary.withValues(alpha: isDark ? 0.06 : 0.035),
                            Colors.black
                                .withValues(alpha: isDark ? 0.10 : 0.025),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.34 : 0.16),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LiquidGlassRimPainter(
                          primary: primary,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
                  AnimatedAlign(
                    alignment: Alignment(-1.0 + widget.selectedIndex, 0),
                    duration: AppMotion.panel,
                    curve: AppMotion.enter,
                    child: FractionallySizedBox(
                      widthFactor: 1 / _items.length,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _LiquidGlassIndicator(
                          filter: _indicatorFilter!,
                          primary: primary,
                          isDark: isDark,
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
                            selected: widget.selectedIndex == index,
                            primary: primary,
                            onTap: () => widget.onDestinationSelected(index),
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
    );
  }
}

class _LiquidGlassIndicator extends StatelessWidget {
  final ui.ImageFilter filter;
  final Color primary;
  final bool isDark;

  const _LiquidGlassIndicator({
    required this.filter,
    required this.primary,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: filter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: primary.withValues(alpha: isDark ? 0.08 : 0.045),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.18 : 0.34),
                    primary.withValues(alpha: isDark ? 0.12 : 0.08),
                    Colors.black.withValues(alpha: isDark ? 0.12 : 0.035),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _LiquidGlassRimPainter(
                primary: primary,
                isDark: isDark,
                indicator: true,
              ),
            ),
          ),
        ],
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

class _LiquidGlassRimPainter extends CustomPainter {
  final Color primary;
  final bool isDark;
  final bool indicator;

  const _LiquidGlassRimPainter({
    required this.primary,
    required this.isDark,
    this.indicator = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height * (indicator ? 0.38 : 0.36));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = indicator ? 1.1 : 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(
              alpha:
                  indicator ? (isDark ? 0.40 : 0.56) : (isDark ? 0.30 : 0.46)),
          const Color(0xFF78E7FF).withValues(alpha: isDark ? 0.22 : 0.17),
          primary.withValues(alpha: isDark ? 0.23 : 0.15),
          const Color(0xFFFF8FC8).withValues(alpha: isDark ? 0.16 : 0.10),
          Colors.white.withValues(alpha: isDark ? 0.08 : 0.14),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), radius),
      edge,
    );

    final topRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = indicator ? 1.0 : 0.9
      ..color = Colors.white.withValues(
          alpha: indicator ? (isDark ? 0.24 : 0.38) : (isDark ? 0.16 : 0.28));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(indicator ? 2.0 : 1.5),
        Radius.circular(size.height * (indicator ? 0.32 : 0.31)),
      ),
      topRim,
    );

    final bottomRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.black.withValues(alpha: isDark ? 0.30 : 0.10);
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.25,
        size.width * 0.84,
        size.height * 1.30,
      ),
      0.25,
      2.65,
      false,
      bottomRim,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassRimPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.isDark != isDark ||
      oldDelegate.indicator != indicator;
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
