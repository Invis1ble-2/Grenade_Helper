import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../models.dart';
import '../services/settings_service.dart';
import '../services/overlay_state_service.dart';
import '../widgets/radar_mini_map.dart';
import 'grenade_detail_screen.dart'
    show VideoPlayerWidget, VideoPlayerWidgetState;

/// 悬浮窗组件
class OverlayWindow extends StatefulWidget {
  final SettingsService settingsService;
  final OverlayStateService overlayState;
  final AsyncCallback onClose;
  final AsyncCallback onMinimize;
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
  final ScrollController _scrollController = ScrollController();
  bool _isMediaFullscreenPreview = false;
  bool _isTogglingMediaFullscreenPreview = false;
  Rect? _normalWindowBoundsBeforePreview;

  @override
  void initState() {
    super.initState();
    _hotkeys = widget.settingsService.getHotkeys();
    widget.overlayState.addListener(_onStateChanged);
    // 注册视频回调
    widget.overlayState.setVideoTogglePlayPauseCallback(_handleVideoToggle);
  }

  void _handleVideoToggle() {
    // print('[OverlayWindow] _handleVideoToggle called');
    if (_videoPlayerKey.currentState != null) {
      _videoPlayerKey.currentState!.togglePlayPause();
      // print('[OverlayWindow] Video toggle called successfully');
    } else {
      // print('[OverlayWindow] No video player state available');
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  /// 重载热键
  void reloadHotkeys([Map<HotkeyAction, HotkeyConfig>? newHotkeys]) {
    // print(
    //     '[OverlayWindow] reloadHotkeys called, before reload: ${_hotkeys[HotkeyAction.navigateUp]?.toDisplayString()}');
    setState(() {
      // 加载热键
      _hotkeys = newHotkeys ?? widget.settingsService.getHotkeys();
    });
    // print(
    //     '[OverlayWindow] Hotkeys reloaded, after reload: ${_hotkeys[HotkeyAction.navigateUp]?.toDisplayString()}');
    // print('[OverlayWindow] Total hotkeys loaded: ${_hotkeys.length}');
  }

  @override
  void dispose() {
    widget.overlayState.setVideoTogglePlayPauseCallback(null);
    widget.overlayState.removeListener(_onStateChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getHotkeyLabel(HotkeyAction action) {
    final config = _hotkeys[action];
    final label = config?.toDisplayString() ?? '?';
    return label;
  }

  Offset? get persistedWindowPosition {
    if (_isMediaFullscreenPreview && _normalWindowBoundsBeforePreview != null) {
      return _normalWindowBoundsBeforePreview!.topLeft;
    }
    return null;
  }

  bool get blocksDirectionalNavigation => _isMediaFullscreenPreview;

  Future<void> pauseActiveVideoPlayback() async {
    await _videoPlayerKey.currentState?.pauseIfPlaying();
  }

  @override
  Widget build(BuildContext context) {
    final overlayOpacity = widget.overlayState.overlayOpacity;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        color: Colors.transparent,
        child: _isMediaFullscreenPreview
            ? _buildFullscreenPreview()
            : Opacity(
                opacity: overlayOpacity,
                child: Container(
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

  /// 标题栏
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
            // 地图名
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

            // 道具名
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

            // 速度显示
            _buildSpeedIndicator(),
            const SizedBox(width: 8),

            // 过滤器
            _buildFilterButtons(),
            const SizedBox(width: 12),

            // 最小化
            _buildWindowButton(
              icon: Icons.remove,
              onTap: () => unawaited(widget.onClose()),
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
        _buildFilterIcon(GrenadeType.wallbang, Icons.apps, Colors.cyan, state),
      ],
    );
  }

  /// 速度指示器
  Widget _buildSpeedIndicator() {
    final state = widget.overlayState;
    final increaseSpeedKey = _getHotkeyLabel(HotkeyAction.increaseNavSpeed);
    final decreaseSpeedKey = _getHotkeyLabel(HotkeyAction.decreaseNavSpeed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Text(
        '速度:${state.navSpeedLevel}/5 ($decreaseSpeedKey/$increaseSpeedKey)',
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
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

  /// 主内容
  Widget _buildContent() {
    final state = widget.overlayState;

    // 无地图
    if (!state.hasMap) {
      return _buildNoMapPrompt();
    }

    // 无道具
    if (state.filteredGrenades.isEmpty) {
      return _buildNoGrenadePrompt();
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 雷达
          _buildRadarMap(),
          const SizedBox(height: 16),

          // 吸附内容
          if (state.isSnapConfirmed && state.currentGrenade != null) ...[
            // 媒体区
            _buildMediaArea(),
            const SizedBox(height: 12),

            // 步骤说明
            _buildDescription(),
          ] else
            // 导航提示
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

    // 动态宽度
    return LayoutBuilder(
      builder: (context, constraints) {
        // 宽度适配
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
    final medias = _getCurrentStepMedias();
    if (medias == null) {
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

    if (medias.isEmpty) {
      return Container(
        height: 350,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
        ),
      );
    }

    return Column(
      children: medias.asMap().entries.map((entry) {
        final index = entry.key;
        final media = entry.value;
        return Padding(
          padding: EdgeInsets.only(bottom: index < medias.length - 1 ? 8 : 0),
          child: _buildSingleMediaItem(
            media,
            isFullscreenPreview: _isMediaFullscreenPreview,
          ),
        );
      }).toList(),
    );
  }

  /// 单个媒体
  Widget _buildSingleMediaItem(
    StepMedia media, {
    required bool isFullscreenPreview,
    double? preferredHeight,
  }) {
    final loadingHeight =
        preferredHeight ?? (isFullscreenPreview ? 560.0 : 400.0);
    final defaultHeight =
        preferredHeight ?? (isFullscreenPreview ? 560.0 : 400.0);
    final portraitHeight =
        preferredHeight ?? (isFullscreenPreview ? 760.0 : 450.0);

    // 图片显示
    if (media.type == MediaType.image) {
      return FutureBuilder<Size?>(
        future: _getImageSize(media.localPath),
        builder: (context, snapshot) {
          // 加载占位
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              height: loadingHeight,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.orange,
                  strokeWidth: 2,
                ),
              ),
            );
          }

          // 图片高度
          double height = defaultHeight;
          // 0:正 1:竖 2:横
          int imageType = 0;

          if (preferredHeight == null &&
              snapshot.hasData &&
              snapshot.data != null) {
            final size = snapshot.data!;
            final diff = (size.height - size.width).abs();

            if (diff <= 400) {
              // 判定正方形
              imageType = 0;
            } else if (size.height > size.width) {
              // 竖屏
              imageType = 1;
              height = portraitHeight;
            } else {
              // 横版
              imageType = 2;
            }
          }

          return Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildMediaView(media, imageType: imageType),
          );
        },
      );
    }

    // 非图片（视频）使用默认高度
    return Container(
      height: defaultHeight,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _buildMediaView(media),
    );
  }

  /// 图片尺寸
  Future<Size?> _getImageSize(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      return Size(image.width.toDouble(), image.height.toDouble());
    } catch (e) {
      return null;
    }
  }

  /// 媒体视图
  Widget _buildMediaView(StepMedia media, {int imageType = 0}) {
    final file = File(media.localPath);
    if (!file.existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
      );
    }

    if (media.type == MediaType.image) {
      // 缩放逻辑
      final bool needsScale = !_isMediaFullscreenPreview && imageType != 0;

      Widget imageWidget = Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      );

      // 应用缩放
      if (needsScale) {
        // 类型判断
        final double scale = imageType == 1 ? 1.5 : 1.3; // 缩放倍率
        imageWidget = Transform.scale(
          scale: scale,
          child: imageWidget,
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageWidget,
      );
    }

    // 视频
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
          // 步骤标题已移动到底部导航栏
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

  Widget _buildFullscreenPreview() {
    final title = widget.overlayState.currentGrenade?.title ?? '媒体预览';
    final fullscreenKey =
        _getHotkeyLabel(HotkeyAction.toggleMediaFullscreenPreview);
    final medias = _getCurrentStepMedias();

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(toggleMediaFullscreenPreview()),
          child: Container(
            color: Colors.black.withValues(alpha: 0.38),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1600,
                maxHeight: 980,
              ),
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xF214171C),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.fullscreen,
                            color: Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$fullscreenKey 退出全屏',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildWindowButton(
                            icon: Icons.fullscreen_exit,
                            onTap: () =>
                                unawaited(toggleMediaFullscreenPreview()),
                            color: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _buildFullscreenPreviewContent(medias),
                      ),
                      const SizedBox(height: 12),
                      _buildFullscreenHintBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenPreviewContent(List<StepMedia>? medias) {
    final safeMedias = medias ?? const <StepMedia>[];

    if (safeMedias.length == 1) {
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _buildSingleMediaItem(
                  safeMedias.first,
                  isFullscreenPreview: true,
                  preferredHeight: constraints.maxHeight,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildDescription(),
        ],
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: [
          _buildMediaArea(),
          const SizedBox(height: 12),
          _buildDescription(),
        ],
      ),
    );
  }

  Widget _buildFullscreenHintBar() {
    final state = widget.overlayState;
    final grenade = state.currentGrenade;
    final grenadeTotal = state.currentClusterGrenades.length;
    final grenadeIndex = grenade == null ? 0 : state.currentClusterIndex + 1;
    final steps = grenade?.steps.toList() ?? const <GrenadeStep>[];
    steps.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));
    final stepTotal = steps.isEmpty ? 0 : steps.length;
    final stepIndex = steps.isEmpty ? 0 : state.currentStepIndex + 1;
    final currentStep =
        steps.isNotEmpty && state.currentStepIndex < steps.length
            ? steps[state.currentStepIndex]
            : null;
    final stepTitle = (currentStep?.title ?? '').trim();
    final stepDisplayTitle = stepTitle.isEmpty ? '步骤' : stepTitle;

    final prevGrenadeKey = _getHotkeyLabel(HotkeyAction.prevGrenade);
    final nextGrenadeKey = _getHotkeyLabel(HotkeyAction.nextGrenade);
    final prevStepKey = _getHotkeyLabel(HotkeyAction.prevStep);
    final nextStepKey = _getHotkeyLabel(HotkeyAction.nextStep);
    final togglePlayKey = _getHotkeyLabel(HotkeyAction.togglePlayPause);
    final fullscreenKey =
        _getHotkeyLabel(HotkeyAction.toggleMediaFullscreenPreview);
    final scrollUpKey = _getHotkeyLabel(HotkeyAction.scrollUp);
    final scrollDownKey = _getHotkeyLabel(HotkeyAction.scrollDown);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;

          final leftInfo = Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '道具 $grenadeIndex/$grenadeTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$stepDisplayTitle $stepIndex/$stepTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );

          final rightHints = Wrap(
            spacing: 14,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$prevGrenadeKey/$nextGrenadeKey 切换道具',
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
              Text(
                '$prevStepKey/$nextStepKey 切换步骤',
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
              Text(
                '$togglePlayKey 播放/暂停',
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
              Text(
                '$scrollUpKey/$scrollDownKey 滚动',
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
              Text(
                '$fullscreenKey 退出全屏',
                style: TextStyle(color: Colors.grey[300], fontSize: 12),
              ),
              Text(
                '方向导航已禁用',
                style: TextStyle(
                  color: Colors.orange[300],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leftInfo,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: rightHints,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftInfo),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: rightHints,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 底栏
  Widget _buildFooter() {
    final state = widget.overlayState;

    if (!state.hasMap || state.currentGrenade == null) {
      // 提示文本
      final navUpKey = _getHotkeyLabel(HotkeyAction.navigateUp);
      final navDownKey = _getHotkeyLabel(HotkeyAction.navigateDown);
      final navLeftKey = _getHotkeyLabel(HotkeyAction.navigateLeft);
      final navRightKey = _getHotkeyLabel(HotkeyAction.navigateRight);
      final prevGrenadeKey = _getHotkeyLabel(HotkeyAction.prevGrenade);
      final nextGrenadeKey = _getHotkeyLabel(HotkeyAction.nextGrenade);
      final prevStepKey = _getHotkeyLabel(HotkeyAction.prevStep);
      final nextStepKey = _getHotkeyLabel(HotkeyAction.nextStep);
      final scrollUpKey = _getHotkeyLabel(HotkeyAction.scrollUp);
      final scrollDownKey = _getHotkeyLabel(HotkeyAction.scrollDown);
      final fullscreenKey =
          _getHotkeyLabel(HotkeyAction.toggleMediaFullscreenPreview);

      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(14)),
        ),
        child: Center(
          child: Text(
            '$navUpKey$navLeftKey$navDownKey$navRightKey 导航 | $prevGrenadeKey/$nextGrenadeKey 道具 | $prevStepKey/$nextStepKey 步骤 | $scrollUpKey/$scrollDownKey 滚动 | $fullscreenKey 全屏',
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
              // 道具切换
              _buildNavRow(
                label: '道具',
                current: state.currentClusterIndex + 1,
                total: state.currentClusterGrenades.length,
                onPrev: state.prevGrenade,
                onNext: state.nextGrenade,
                color: Colors.orange,
              ),

              // 步骤切换
              _buildStepNavRow(
                steps: steps,
                currentIndex: state.currentStepIndex,
                onPrev: state.prevStep,
                onNext: state.nextStep,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 快捷键提示
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
                  final scrollUpKey = _getHotkeyLabel(HotkeyAction.scrollUp);
                  final scrollDownKey =
                      _getHotkeyLabel(HotkeyAction.scrollDown);
                  final fullscreenKey = _getHotkeyLabel(
                    HotkeyAction.toggleMediaFullscreenPreview,
                  );

                  return Text(
                    '$navUpKey$navLeftKey$navDownKey$navRightKey 导航 | $smokeKey/$flashKey/$molotovKey/$heKey 过滤 | $prevGrenadeKey/$nextGrenadeKey 道具 | $prevStepKey/$nextStepKey 步骤 | $scrollUpKey/$scrollDownKey 滚动 | $fullscreenKey 全屏',
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  );
                }),
              ),
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

  /// 步骤导航
  Widget _buildStepNavRow({
    required List<GrenadeStep> steps,
    required int currentIndex,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    final currentStep =
        currentIndex < steps.length ? steps[currentIndex] : null;
    final title = currentStep?.title ?? '';
    final displayTitle = title.isEmpty ? '步骤' : title;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 22),
          color: Colors.blue,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: onPrev,
        ),
        Text(
          '$displayTitle ${currentIndex + 1}/${steps.length}',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 22),
          color: Colors.blue,
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
      if (_isMediaFullscreenPreview) return;
      if (Platform.isWindows) return;
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
    // print(
    //     '[OverlayWindow] Key pressed: ${key.keyLabel} (keyId: ${key.keyId}), Alt: $hasAlt, Ctrl: $hasCtrl, Shift: $hasShift');

    // 检查每个动作
    for (final entry in _hotkeys.entries) {
      // 跳过方向键动作（已在上面处理）
      if (_isNavigationAction(entry.key)) continue;

      if (_matchesHotkey(key, hasAlt, hasCtrl, hasShift, entry.value)) {
        // print('[OverlayWindow] Hotkey matched: ${entry.key}');
        _executeAction(entry.key);
        return;
      }
    }

    // 直接检查 Alt+P 用于视频播放/暂停 (备用方案)
    if (hasAlt && !hasCtrl && !hasShift && key == LogicalKeyboardKey.keyP) {
      _executeAction(HotkeyAction.togglePlayPause);
      return;
    }

    // 直接检查 Alt+Enter 用于媒体全屏预览 (备用方案)
    if (hasAlt && !hasCtrl && !hasShift && key == LogicalKeyboardKey.enter) {
      _executeAction(HotkeyAction.toggleMediaFullscreenPreview);
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
        unawaited(widget.onClose());
        break;
      case HotkeyAction.navigateUp:
        if (_isMediaFullscreenPreview) break;
        state.navigateDirection(NavigationDirection.up);
        break;
      case HotkeyAction.navigateDown:
        if (_isMediaFullscreenPreview) break;
        state.navigateDirection(NavigationDirection.down);
        break;
      case HotkeyAction.navigateLeft:
        if (_isMediaFullscreenPreview) break;
        state.navigateDirection(NavigationDirection.left);
        break;
      case HotkeyAction.navigateRight:
        if (_isMediaFullscreenPreview) break;
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
      case HotkeyAction.toggleWallbang:
        state.toggleFilter(GrenadeType.wallbang);
        break;
      case HotkeyAction.togglePlayPause:
        // print(
        //     'togglePlayPause: currentState = ${_videoPlayerKey.currentState}');
        if (_videoPlayerKey.currentState != null) {
          _videoPlayerKey.currentState!.togglePlayPause();
          // print('togglePlayPause: called successfully');
        } else {
          // print('togglePlayPause: no video player state available');
        }
        break;
      case HotkeyAction.toggleMediaFullscreenPreview:
        unawaited(toggleMediaFullscreenPreview());
        break;
      case HotkeyAction.increaseNavSpeed:
        state.increaseNavSpeed();
        break;
      case HotkeyAction.decreaseNavSpeed:
        state.decreaseNavSpeed();
        break;
      case HotkeyAction.scrollUp:
        scrollContent(-300);
        break;
      case HotkeyAction.scrollDown:
        scrollContent(300);
        break;
    }
  }

  /// 滚动内容区域（公开方法，供 IPC 调用）
  void scrollContent(double delta) {
    if (!_scrollController.hasClients) return;
    final newOffset = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  List<StepMedia>? _getCurrentStepMedias() {
    final state = widget.overlayState;
    final grenade = state.currentGrenade;
    if (grenade == null) return null;

    final steps = grenade.steps.toList()
      ..sort((a, b) => a.stepIndex.compareTo(b.stepIndex));
    if (steps.isEmpty) return null;

    final currentStep = state.currentStepIndex < steps.length
        ? steps[state.currentStepIndex]
        : steps.first;

    final medias = currentStep.medias.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return medias;
  }

  Future<void> toggleMediaFullscreenPreview() async {
    if (_isTogglingMediaFullscreenPreview) return;

    final medias = _getCurrentStepMedias();
    if (!_isMediaFullscreenPreview && (medias == null || medias.isEmpty)) {
      return;
    }

    _isTogglingMediaFullscreenPreview = true;
    try {
      if (_isMediaFullscreenPreview) {
        final restoreBounds = _normalWindowBoundsBeforePreview;
        widget.overlayState.setNavigationLocked(false);
        await windowManager.setFullScreen(false);
        if (restoreBounds != null) {
          await windowManager.setBounds(restoreBounds);
        }
        if (!mounted) return;
        setState(() {
          _isMediaFullscreenPreview = false;
          _normalWindowBoundsBeforePreview = null;
        });
        return;
      }

      _normalWindowBoundsBeforePreview ??= await windowManager.getBounds();
      widget.overlayState.setNavigationLocked(true);
      await windowManager.setFullScreen(true);

      if (!mounted) return;
      setState(() {
        _isMediaFullscreenPreview = true;
      });
    } catch (e) {
      debugPrint(
          '[OverlayWindow] Failed to toggle media fullscreen preview: $e');
    } finally {
      _isTogglingMediaFullscreenPreview = false;
    }
  }
}
