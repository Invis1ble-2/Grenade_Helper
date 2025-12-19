import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../services/settings_service.dart';
import '../services/overlay_state_service.dart';
import '../widgets/radar_mini_map.dart';
import 'grenade_detail_screen.dart'
    show VideoPlayerWidget, VideoPlayerWidgetState;

/// 悬浮窗组件 - 独立无边框窗口，显示道具教程
class OverlayWindow extends StatefulWidget {
  final SettingsService settingsService;
  final OverlayStateService overlayState;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onStartDrag;

  const OverlayWindow({
    super.key,
    required this.settingsService,
    required this.overlayState,
    required this.onClose,
    required this.onMinimize,
    required this.onStartDrag,
  });

  @override
  State<OverlayWindow> createState() => OverlayWindowState();
}

class OverlayWindowState extends State<OverlayWindow> {
  final FocusNode _focusNode = FocusNode();
  late Map<HotkeyAction, HotkeyConfig> _hotkeys;
  final GlobalKey<VideoPlayerWidgetState> _videoPlayerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _hotkeys = widget.settingsService.getHotkeys();
    widget.overlayState.addListener(_onStateChanged);
    // 注册视频播放/暂停回调
    widget.overlayState.setVideoTogglePlayPauseCallback(_handleVideoToggle);
  }

  void _handleVideoToggle() {
    print('[OverlayWindow] _handleVideoToggle called');
    if (_videoPlayerKey.currentState != null) {
      _videoPlayerKey.currentState!.togglePlayPause();
      print('[OverlayWindow] Video toggle called successfully');
    } else {
      print('[OverlayWindow] No video player state available');
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  /// 重新加载热键配置
  void reloadHotkeys([Map<HotkeyAction, HotkeyConfig>? newHotkeys]) {
    print(
        '[OverlayWindow] reloadHotkeys called, before reload: ${_hotkeys[HotkeyAction.navigateUp]?.toDisplayString()}');
    setState(() {
      // 如果提供了新的热键配置，直接使用；否则从 settingsService 加载
      _hotkeys = newHotkeys ?? widget.settingsService.getHotkeys();
    });
    print(
        '[OverlayWindow] Hotkeys reloaded, after reload: ${_hotkeys[HotkeyAction.navigateUp]?.toDisplayString()}');
    print('[OverlayWindow] Total hotkeys loaded: ${_hotkeys.length}');
  }

  @override
  void dispose() {
    widget.overlayState.setVideoTogglePlayPauseCallback(null);
    widget.overlayState.removeListener(_onStateChanged);
    _focusNode.dispose();
    super.dispose();
  }

  String _getHotkeyLabel(HotkeyAction action) {
    final config = _hotkeys[action];
    final label = config?.toDisplayString() ?? '?';
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final overlayOpacity = widget.overlayState.overlayOpacity;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Opacity(
        opacity: overlayOpacity,
        child: Material(
          color: const Color(0xFF1B1E23),
          child: Container(
            // 移除固定尺寸，让容器填满窗口
            constraints: const BoxConstraints(
              minWidth: 600,
              minHeight: 750,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1E23),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                _buildTitleBar(),
                Expanded(child: _buildContent()),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 自定义标题栏（可拖动，无系统按钮）
  Widget _buildTitleBar() {
    final state = widget.overlayState;
    final mapName = state.currentMap?.name ?? '未选择地图';
    final grenade = state.currentGrenade;
    final title = grenade?.title ?? '';

    return GestureDetector(
      onPanStart: (_) => widget.onStartDrag(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(
          children: [
            // 拖动手柄图标
            Icon(Icons.drag_indicator, color: Colors.grey[600], size: 20),
            const SizedBox(width: 8),

            // 地图名称标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                mapName,
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 道具标题
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 过滤器按钮
            _buildFilterButtons(),
            const SizedBox(width: 12),

            // 最小化按钮（隐藏悬浮窗，使用 onClose 以便同时注销热键）
            _buildWindowButton(
              icon: Icons.remove,
              onTap: widget.onClose,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildFilterButtons() {
    final state = widget.overlayState;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFilterIcon(GrenadeType.smoke, Icons.cloud, Colors.grey, state),
        _buildFilterIcon(
            GrenadeType.flash, Icons.flash_on, Colors.yellow, state),
        _buildFilterIcon(GrenadeType.molotov, Icons.local_fire_department,
            Colors.red, state),
        _buildFilterIcon(GrenadeType.he, Icons.circle, Colors.green, state),
      ],
    );
  }

  Widget _buildFilterIcon(
      int type, IconData icon, Color color, OverlayStateService state) {
    final isActive = state.activeFilters.contains(type);
    return GestureDetector(
      onTap: () => state.toggleFilter(type),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? color : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  /// 主内容区域
  Widget _buildContent() {
    final state = widget.overlayState;

    // 未进入地图
    if (!state.hasMap) {
      return _buildNoMapPrompt();
    }

    // 没有道具
    if (state.filteredGrenades.isEmpty) {
      return _buildNoGrenadePrompt();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 雷达小地图（始终显示）
          _buildRadarMap(),
          const SizedBox(height: 16),

          // 根据吸附状态显示内容
          if (state.isSnapped && state.currentGrenade != null) ...[
            // 道具媒体区域
            _buildMediaArea(),
            const SizedBox(height: 12),

            // 步骤说明
            _buildDescription(),
          ] else
            // 未吸附提示
            _buildNavigationHint(),
        ],
      ),
    );
  }

  Widget _buildNoMapPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 80, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text(
            '请先进入地图',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在主界面选择一张地图后\n悬浮窗将显示该地图的道具',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildNoGrenadePrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_location_alt, size: 80, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text(
            '该地图暂无道具',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先在地图上添加道具点位',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationHint() {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.gps_not_fixed,
              size: 48,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              '使用方向键移动准星',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '靠近点位时会自动吸附并显示道具信息',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarMap() {
    final state = widget.overlayState;
    final layer = state.currentLayer;

    if (layer == null) return const SizedBox.shrink();

    // 使用 LayoutBuilder 动态获取可用宽度，确保拉伸窗口后图标位置正确
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用可用宽度，高度保持固定比例
        final availableWidth =
            constraints.maxWidth > 0 ? constraints.maxWidth : 550.0;
        final radarHeight = 140.0;

        return RadarMiniMap(
          mapAssetPath: layer.assetPath,
          currentGrenade: state.currentGrenade,
          allGrenades: state.filteredGrenades,
          crosshairX: state.crosshairX,
          crosshairY: state.crosshairY,
          isSnapped: state.isSnapped,
          width: availableWidth,
          height: radarHeight,
          zoomLevel: 1.3,
        );
      },
    );
  }

  Widget _buildMediaArea() {
    final state = widget.overlayState;
    final grenade = state.currentGrenade;
    if (grenade == null) return const SizedBox.shrink();

    final steps = grenade.steps.toList();
    steps.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));

    if (steps.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('该道具暂无步骤', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final currentStep = state.currentStepIndex < steps.length
        ? steps[state.currentStepIndex]
        : steps.first;

    final medias = currentStep.medias.toList();

    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: medias.isEmpty
          ? const Center(
              child:
                  Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
            )
          : _buildMediaView(medias.first),
    );
  }

  Widget _buildMediaView(StepMedia media) {
    final file = File(media.localPath);
    if (!file.existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
      );
    }

    if (media.type == MediaType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        ),
      );
    }

    // 视频播放
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: VideoPlayerWidget(key: _videoPlayerKey, file: file),
    );
  }

  Widget _buildDescription() {
    final state = widget.overlayState;
    final grenade = state.currentGrenade;
    if (grenade == null) return const SizedBox.shrink();

    final steps = grenade.steps.toList();
    steps.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));

    if (steps.isEmpty) return const SizedBox.shrink();

    final currentStep = state.currentStepIndex < steps.length
        ? steps[state.currentStepIndex]
        : steps.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentStep.title.isNotEmpty)
            Text(
              currentStep.title,
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          if (currentStep.title.isNotEmpty) const SizedBox(height: 4),
          Text(
            currentStep.description.isNotEmpty
                ? currentStep.description
                : '(无说明)',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// 底部导航栏
  Widget _buildFooter() {
    final state = widget.overlayState;

    if (!state.hasMap || state.currentGrenade == null) {
      // 动态构建提示文本
      final navUpKey = _getHotkeyLabel(HotkeyAction.navigateUp);
      final navDownKey = _getHotkeyLabel(HotkeyAction.navigateDown);
      final navLeftKey = _getHotkeyLabel(HotkeyAction.navigateLeft);
      final navRightKey = _getHotkeyLabel(HotkeyAction.navigateRight);
      final increaseSpeedKey = _getHotkeyLabel(HotkeyAction.increaseNavSpeed);
      final decreaseSpeedKey = _getHotkeyLabel(HotkeyAction.decreaseNavSpeed);
      final prevGrenadeKey = _getHotkeyLabel(HotkeyAction.prevGrenade);
      final nextGrenadeKey = _getHotkeyLabel(HotkeyAction.nextGrenade);
      final prevStepKey = _getHotkeyLabel(HotkeyAction.prevStep);
      final nextStepKey = _getHotkeyLabel(HotkeyAction.nextStep);

      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(14)),
        ),
        child: Center(
          child: Text(
            '$navUpKey$navLeftKey$navDownKey$navRightKey 导航  |  $increaseSpeedKey/$decreaseSpeedKey 调速 (${state.navSpeedLevel}/5)  |  $prevGrenadeKey/$nextGrenadeKey 道具  |  $prevStepKey/$nextStepKey 步骤',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
      );
    }

    final grenade = state.currentGrenade!;
    final steps = grenade.steps.toList();
    steps.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 道具切换（只在当前点位内循环）
              _buildNavRow(
                label: '道具',
                current: state.currentClusterIndex + 1,
                total: state.currentClusterGrenades.length,
                onPrev: state.prevGrenade,
                onNext: state.nextGrenade,
                color: Colors.orange,
              ),

              // 步骤切换
              _buildNavRow(
                label: '步骤',
                current: state.currentStepIndex + 1,
                total: steps.length,
                onPrev: state.prevStep,
                onNext: state.nextStep,
                color: Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 左侧：快捷键提示（动态获取）
              Expanded(
                child: Builder(builder: (context) {
                  final navUpKey = _getHotkeyLabel(HotkeyAction.navigateUp);
                  final navDownKey = _getHotkeyLabel(HotkeyAction.navigateDown);
                  final navLeftKey = _getHotkeyLabel(HotkeyAction.navigateLeft);
                  final navRightKey =
                      _getHotkeyLabel(HotkeyAction.navigateRight);
                  final smokeKey = _getHotkeyLabel(HotkeyAction.toggleSmoke);
                  final flashKey = _getHotkeyLabel(HotkeyAction.toggleFlash);
                  final molotovKey =
                      _getHotkeyLabel(HotkeyAction.toggleMolotov);
                  final heKey = _getHotkeyLabel(HotkeyAction.toggleHE);
                  final prevGrenadeKey =
                      _getHotkeyLabel(HotkeyAction.prevGrenade);
                  final nextGrenadeKey =
                      _getHotkeyLabel(HotkeyAction.nextGrenade);
                  final prevStepKey = _getHotkeyLabel(HotkeyAction.prevStep);
                  final nextStepKey = _getHotkeyLabel(HotkeyAction.nextStep);

                  return Text(
                    '$navUpKey$navLeftKey$navDownKey$navRightKey 导航  |  $smokeKey/$flashKey/$molotovKey/$heKey 过滤  |  $prevGrenadeKey/$nextGrenadeKey 道具  |  $prevStepKey/$nextStepKey 步骤',
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  );
                }),
              ),
              // 右侧：速度档位显示（动态获取）
              Builder(builder: (context) {
                final increaseSpeedKey =
                    _getHotkeyLabel(HotkeyAction.increaseNavSpeed);
                final decreaseSpeedKey =
                    _getHotkeyLabel(HotkeyAction.decreaseNavSpeed);

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '速度: ${state.navSpeedLevel}/5  ($increaseSpeedKey/$decreaseSpeedKey)',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavRow({
    required String label,
    required int current,
    required int total,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 22),
          color: color,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onPrev,
        ),
        Text(
          '$label $current/$total',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 22),
          color: color,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onNext,
        ),
      ],
    );
  }

  // === 快捷键处理 ===

  // === 快捷键处理 ===

  void _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    // 忽略单独的修饰键事件
    if (_isModifierKey(key)) return;

    // 处理方向键的连续移动
    final navDirection = _getNavigationDirection(key);
    if (navDirection != null) {
      if (event is KeyDownEvent) {
        widget.overlayState.startNavigation(navDirection);
      } else if (event is KeyUpEvent) {
        widget.overlayState.stopNavigation(navDirection);
      }
      return;
    }

    // 其他按键只处理 KeyDownEvent
    if (event is! KeyDownEvent) return;

    // 简单的修饰键检查
    final hasAlt = HardwareKeyboard.instance.isAltPressed;
    final hasCtrl = HardwareKeyboard.instance.isControlPressed;
    final hasShift = HardwareKeyboard.instance.isShiftPressed;

    // 调试日志：打印按键信息
    print(
        '[OverlayWindow] Key pressed: ${key.keyLabel} (keyId: ${key.keyId}), Alt: $hasAlt, Ctrl: $hasCtrl, Shift: $hasShift');

    // 检查每个动作
    for (final entry in _hotkeys.entries) {
      // 跳过方向键动作（已在上面处理）
      if (_isNavigationAction(entry.key)) continue;

      if (_matchesHotkey(key, hasAlt, hasCtrl, hasShift, entry.value)) {
        print('[OverlayWindow] Hotkey matched: ${entry.key}');
        _executeAction(entry.key);
        return;
      }
    }

    // 直接检查 Alt+P 用于视频播放/暂停 (备用方案)
    if (hasAlt && !hasCtrl && !hasShift && key == LogicalKeyboardKey.keyP) {
      _executeAction(HotkeyAction.togglePlayPause);
      return;
    }
  }

  /// 获取按键对应的导航方向（根据用户配置的热键判断）
  NavigationDirection? _getNavigationDirection(LogicalKeyboardKey key) {
    // 根据用户配置的热键来判断方向
    final upConfig = _hotkeys[HotkeyAction.navigateUp];
    final downConfig = _hotkeys[HotkeyAction.navigateDown];
    final leftConfig = _hotkeys[HotkeyAction.navigateLeft];
    final rightConfig = _hotkeys[HotkeyAction.navigateRight];

    // 使用 keyId 比较
    if (upConfig != null && key.keyId == upConfig.key.keyId) {
      return NavigationDirection.up;
    }
    if (downConfig != null && key.keyId == downConfig.key.keyId) {
      return NavigationDirection.down;
    }
    if (leftConfig != null && key.keyId == leftConfig.key.keyId) {
      return NavigationDirection.left;
    }
    if (rightConfig != null && key.keyId == rightConfig.key.keyId) {
      return NavigationDirection.right;
    }
    return null;
  }

  /// 判断是否是导航动作
  bool _isNavigationAction(HotkeyAction action) {
    return action == HotkeyAction.navigateUp ||
        action == HotkeyAction.navigateDown ||
        action == HotkeyAction.navigateLeft ||
        action == HotkeyAction.navigateRight;
  }

  /// 判断是否是修饰键
  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  bool _matchesHotkey(
    LogicalKeyboardKey key,
    bool hasAlt,
    bool hasCtrl,
    bool hasShift,
    HotkeyConfig config,
  ) {
    // 使用 keyId 比较而不是对象比较
    if (key.keyId != config.key.keyId) return false;

    final needsAlt = config.modifiers.any((m) =>
        m == LogicalKeyboardKey.alt ||
        m == LogicalKeyboardKey.altLeft ||
        m == LogicalKeyboardKey.altRight);
    final needsCtrl = config.modifiers.any((m) =>
        m == LogicalKeyboardKey.control ||
        m == LogicalKeyboardKey.controlLeft ||
        m == LogicalKeyboardKey.controlRight);
    final needsShift = config.modifiers.any((m) =>
        m == LogicalKeyboardKey.shift ||
        m == LogicalKeyboardKey.shiftLeft ||
        m == LogicalKeyboardKey.shiftRight);

    return hasAlt == needsAlt && hasCtrl == needsCtrl && hasShift == needsShift;
  }

  void _executeAction(HotkeyAction action) {
    final state = widget.overlayState;

    switch (action) {
      case HotkeyAction.hideOverlay:
      case HotkeyAction.toggleOverlay:
        widget.onClose();
        break;
      case HotkeyAction.navigateUp:
        state.navigateDirection(NavigationDirection.up);
        break;
      case HotkeyAction.navigateDown:
        state.navigateDirection(NavigationDirection.down);
        break;
      case HotkeyAction.navigateLeft:
        state.navigateDirection(NavigationDirection.left);
        break;
      case HotkeyAction.navigateRight:
        state.navigateDirection(NavigationDirection.right);
        break;
      case HotkeyAction.prevGrenade:
        state.prevGrenade();
        break;
      case HotkeyAction.nextGrenade:
        state.nextGrenade();
        break;
      case HotkeyAction.prevStep:
        state.prevStep();
        break;
      case HotkeyAction.nextStep:
        state.nextStep();
        break;
      case HotkeyAction.toggleSmoke:
        state.toggleFilter(GrenadeType.smoke);
        break;
      case HotkeyAction.toggleFlash:
        state.toggleFilter(GrenadeType.flash);
        break;
      case HotkeyAction.toggleMolotov:
        state.toggleFilter(GrenadeType.molotov);
        break;
      case HotkeyAction.toggleHE:
        state.toggleFilter(GrenadeType.he);
        break;
      case HotkeyAction.togglePlayPause:
        print(
            'togglePlayPause: currentState = ${_videoPlayerKey.currentState}');
        if (_videoPlayerKey.currentState != null) {
          _videoPlayerKey.currentState!.togglePlayPause();
          print('togglePlayPause: called successfully');
        } else {
          print('togglePlayPause: no video player state available');
        }
        break;
      case HotkeyAction.increaseNavSpeed:
        state.increaseNavSpeed();
        break;
      case HotkeyAction.decreaseNavSpeed:
        state.decreaseNavSpeed();
        break;
    }
  }
}
