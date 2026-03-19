import 'dart:async';
import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:window_manager/window_manager.dart';
import '../models.dart';
import 'grenade_cluster_service.dart';
import 'settings_service.dart';

/// 悬浮窗状态服务
class OverlayStateService extends ChangeNotifier {
  final Isar isar;

  // 选中地图/楼层
  GameMap? _currentMap;
  MapLayer? _currentLayer;

  // 当前道具
  List<Grenade> _allGrenades = [];
  List<Grenade> _filteredGrenades = [];
  List<GrenadeCluster> _clusters = const [];

  // 选中索引
  int _currentGrenadeIndex = 0;
  int _currentStepIndex = 0;

  // 过滤器
  final Set<int> _activeFilters = {
    GrenadeType.smoke,
    GrenadeType.flash,
    GrenadeType.molotov,
    GrenadeType.he,
    GrenadeType.wallbang,
  };

  // 准星位置
  double _crosshairX = 0.5;
  double _crosshairY = 0.5;
  bool _isSnapped = false;

  // 吸附确认状态
  bool _isSnapConfirmed = false;
  Timer? _snapConfirmTimer;
  int? _suppressedSnapGrenadeId;
  Timer? _suppressedSnapTimer;
  DateTime? _lastNavigationActivityAt;

  // 移动常量
  static const int _moveIntervalMs = 16; // 约60fps

  // 速度档位配置
  static const List<double> _speedLevels = [
    0.0025,
    0.003,
    0.004, // 3档 - 当前默认
    0.0045,
    0.005,
  ];

  // 吸附阈值配置
  static const List<double> _snapThresholdLevels = [
    0.02,
    0.022,
    0.024, // 3档 - 默认
    0.027,
    0.03,
  ];
  static const double _snapReleaseMultiplier = 1.18;

  // 当前档位
  int _navSpeedLevel = 3;
  bool _navigationLocked = false;

  /// 获取档位
  int get navSpeedLevel => _navSpeedLevel;
  bool get navigationLocked => _navigationLocked;

  void setNavigationLocked(bool locked) {
    if (_navigationLocked == locked) return;
    _navigationLocked = locked;
    if (locked) {
      stopAllNavigation();
    } else {
      notifyListeners();
    }
  }

  /// 设置档位
  void setNavSpeedLevel(int level) {
    _navSpeedLevel = level.clamp(1, 5);
    debugPrint(
        '[OverlayStateService] setNavSpeedLevel: $level -> $_navSpeedLevel, speed: ${_speedLevels[_navSpeedLevel - 1]}, snapThreshold: ${_snapThresholdLevels[_navSpeedLevel - 1]}');
  }

  /// 获取速度
  double get _moveSpeed {
    final speed = _speedLevels[_navSpeedLevel - 1];
    return speed;
  }

  /// 获取吸附阈值
  double get _snapThreshold {
    return _snapThresholdLevels[_navSpeedLevel - 1];
  }

  /// 增加速度
  void increaseNavSpeed() {
    if (_navSpeedLevel < 5) {
      setNavSpeedLevel(_navSpeedLevel + 1);
      debugPrint('[OverlayStateService] Speed increased to $_navSpeedLevel');
      notifyListeners();
    }
  }

  /// 减少速度
  void decreaseNavSpeed() {
    if (_navSpeedLevel > 1) {
      setNavSpeedLevel(_navSpeedLevel - 1);
      debugPrint('[OverlayStateService] Speed decreased to $_navSpeedLevel');
      notifyListeners();
    }
  }

  // 移动状态
  final Set<NavigationDirection> _activeDirections = {};
  // 心跳记录
  final Map<NavigationDirection, DateTime> _lastHeartbeat = {};
  Timer? _moveTimer;
  Timer? _heartbeatTimer;

  // 记忆位置
  final Map<int, int> _lastViewedGrenadeByMap = {};

  // 监听订阅
  StreamSubscription<void>? _grenadeSubscription;

  // 视频回调
  VoidCallback? _videoTogglePlayPauseCallback;

  OverlayStateService(this.isar);

  /// 注册视频回调
  void setVideoTogglePlayPauseCallback(VoidCallback? callback) {
    _videoTogglePlayPauseCallback = callback;
  }

  /// 触发播放/暂停
  void triggerVideoTogglePlayPause() {
    debugPrint('[OverlayStateService] triggerVideoTogglePlayPause called');
    _videoTogglePlayPauseCallback?.call();
  }

  /// 刷新UI
  void refresh() {
    notifyListeners();
  }

  /// 强制重载
  void reloadData() {
    debugPrint(
        '[OverlayStateService] reloadData called, reloading grenades...');
    _loadGrenades(notify: true);
  }

  // 透明度
  double _overlayOpacity = 0.9;
  double get overlayOpacity => _overlayOpacity;

  /// 设置透明度
  void setOpacity(double value) {
    _overlayOpacity = value;
    notifyListeners();
  }

  // 尺寸索引
  int _overlaySizeIndex = 1;
  int get overlaySizeIndex => _overlaySizeIndex;

  /// 设置尺寸
  Future<void> setOverlaySize(int index) async {
    _overlaySizeIndex = index;
    final s = SettingsService.calculateSizePixels(index);
    debugPrint('[OverlayStateService] Resizing window to: ${s.$1}x${s.$2}');
    try {
      await windowManager.setSize(Size(s.$1, s.$2));
    } catch (e) {
      debugPrint('[OverlayStateService] Error resizing window: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _snapConfirmTimer?.cancel();
    _suppressedSnapTimer?.cancel();
    _grenadeSubscription?.cancel();
    super.dispose();
  }

  // Getters
  GameMap? get currentMap => _currentMap;
  MapLayer? get currentLayer => _currentLayer;
  List<Grenade> get filteredGrenades => _filteredGrenades;
  List<Grenade> get allGrenades => _allGrenades;
  int get currentGrenadeIndex => _currentGrenadeIndex;
  int get currentStepIndex => _currentStepIndex;
  Set<int> get activeFilters => _activeFilters;

  // 准星位置 getters
  double get crosshairX => _crosshairX;
  double get crosshairY => _crosshairY;
  bool get isSnapped => _isSnapped;

  /// 是否确认吸附
  bool get isSnapConfirmed => _isSnapConfirmed;

  Grenade? get currentGrenade {
    if (_filteredGrenades.isEmpty ||
        _currentGrenadeIndex < 0 ||
        _currentGrenadeIndex >= _filteredGrenades.length) {
      return null;
    }
    return _filteredGrenades[_currentGrenadeIndex];
  }

  /// 合并阈值
  static const double _clusterThreshold = 0.03;

  /// 获取点位道具
  List<Grenade> get currentClusterGrenades {
    final cluster = GrenadeClusterService.findClusterForGrenade(
      _clusters,
      currentGrenade,
    );
    return cluster?.members ?? const [];
  }

  /// 点位内索引
  int get currentClusterIndex {
    final cluster = currentClusterGrenades;
    if (cluster.isEmpty || currentGrenade == null) return 0;
    return cluster.indexWhere((g) => g.id == currentGrenade!.id);
  }

  bool get hasMap => _currentMap != null && _currentLayer != null;

  /// 设置地图
  void setCurrentMap(GameMap map, MapLayer layer) {
    // 只有当 ID 变化时才重新设置，避免重复刷新
    if (_currentMap?.id == map.id && _currentLayer?.id == layer.id) {
      // 更新引用以防万一
      _currentMap = map;
      _currentLayer = layer;
      return;
    }

    _currentMap = map;
    _currentLayer = layer;

    // 设置监听器
    _setupWatcher();

    _loadGrenades();

    // 恢复上次查看的道具位置
    final lastGrenadeId = _lastViewedGrenadeByMap[map.id];
    if (lastGrenadeId != null) {
      final idx = _filteredGrenades.indexWhere((g) => g.id == lastGrenadeId);
      if (idx >= 0) {
        _currentGrenadeIndex = idx;
      }
    } else {
      _currentGrenadeIndex = 0;
    }
    _currentStepIndex = 0;

    // 初始化准星位置到当前道具位置
    _initCrosshairPosition();

    notifyListeners();
  }

  /// 清除地图
  void clearMap() {
    _grenadeSubscription?.cancel();

    // 保存当前查看的道具
    if (_currentMap != null && currentGrenade != null) {
      _lastViewedGrenadeByMap[_currentMap!.id] = currentGrenade!.id;
    }

    _currentMap = null;
    _currentLayer = null;
    _allGrenades.clear();
    _filteredGrenades.clear();
    _clusters = const [];
    _currentGrenadeIndex = 0;
    _currentStepIndex = 0;
    _suppressedSnapGrenadeId = null;
    _suppressedSnapTimer?.cancel();
    _lastNavigationActivityAt = null;
    notifyListeners();
  }

  void _setupWatcher() {
    _grenadeSubscription?.cancel();
    if (_currentLayer != null) {
      // 监听当前楼层的道具变化
      _grenadeSubscription = isar.grenades
          .filter()
          .layer((q) => q.idEqualTo(_currentLayer!.id))
          .watch(fireImmediately: false)
          .listen((_) {
        // 数据变化时重新加载
        debugPrint('OverlayStateService: Data changed, reloading...');
        _loadGrenades(notify: true);
      });
    }
  }

  /// 加载道具
  void _loadGrenades({bool notify = false}) {
    if (_currentLayer == null) {
      _allGrenades.clear();
      _filteredGrenades.clear();
      _clusters = const [];
      return;
    }

    _currentLayer!.grenades.loadSync();
    _allGrenades = _currentLayer!.grenades.toList();

    // 加载关联数据
    for (final g in _allGrenades) {
      g.steps.loadSync();
      for (final step in g.steps) {
        step.medias.loadSync();
      }
    }

    _applyFilters();

    if (notify) {
      notifyListeners();
    }
  }

  /// 应用过滤
  void _applyFilters() {
    // 保存当前选中的道具 ID（用于恢复位置）
    final currentGrenadeId = currentGrenade?.id;

    _filteredGrenades =
        GrenadeClusterService.sortGrenades(
      _allGrenades.where((g) => _activeFilters.contains(g.type)),
    );
    _clusters = GrenadeClusterService.buildClusters(
      _filteredGrenades,
      threshold: _clusterThreshold,
    );

    if (_filteredGrenades.isEmpty) {
      _currentGrenadeIndex = 0;
    } else if (currentGrenadeId != null) {
      // 尝试保持在同一个道具上
      final idx = _filteredGrenades.indexWhere((g) => g.id == currentGrenadeId);
      _currentGrenadeIndex = idx >= 0 ? idx : 0;
    } else {
      // 没有之前选中的道具，重置到第一个
      _currentGrenadeIndex = 0;
    }

    // 确保步骤索引有效
    _currentStepIndex = 0;
  }

  /// 切换过滤
  void toggleFilter(int type) {
    if (_activeFilters.contains(type)) {
      // 确保至少保留一个过滤器
      if (_activeFilters.length > 1) {
        _activeFilters.remove(type);
      }
    } else {
      _activeFilters.add(type);
    }
    _applyFilters();
    notifyListeners();
  }

  /// 上一个道具
  void prevGrenade() {
    final cluster = currentClusterGrenades;
    if (cluster.length <= 1) return;

    final clusterIdx = currentClusterIndex;
    if (clusterIdx <= 0) return;

    final newClusterIdx = clusterIdx - 1;
    final targetGrenade = cluster[newClusterIdx];

    // 找到该道具在 filteredGrenades 中的索引
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0 && globalIdx != _currentGrenadeIndex) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  /// 下一个道具
  void nextGrenade() {
    final cluster = currentClusterGrenades;
    if (cluster.length <= 1) return;

    final clusterIdx = currentClusterIndex;
    if (clusterIdx < 0 || clusterIdx >= cluster.length - 1) return;

    final newClusterIdx = clusterIdx + 1;
    final targetGrenade = cluster[newClusterIdx];

    // 找到该道具在 filteredGrenades 中的索引
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0 && globalIdx != _currentGrenadeIndex) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  /// 上一步
  void prevStep() {
    if (currentGrenade == null) return;
    final steps = currentGrenade!.steps.toList();
    if (steps.isEmpty) return;
    _currentStepIndex = (_currentStepIndex - 1 + steps.length) % steps.length;
    notifyListeners();
  }

  /// 下一步
  void nextStep() {
    if (currentGrenade == null) return;
    final steps = currentGrenade!.steps.toList();
    if (steps.isEmpty) return;
    _currentStepIndex = (_currentStepIndex + 1) % steps.length;
    notifyListeners();
  }

  /// 初始化准星
  void _initCrosshairPosition() {
    final grenade = currentGrenade;
    if (grenade != null) {
      _crosshairX = grenade.xRatio;
      _crosshairY = grenade.yRatio;
      _isSnapped = true;
    } else {
      // 无道具时准星在地图中心
      _crosshairX = 0.5;
      _crosshairY = 0.5;
      _isSnapped = false;
    }
  }

  /// 检查吸附
  /// [ignoreCurrent] - 如果为 true，则忽略当前 cluster（用于逃离吸附）
  void _checkAndSnapToPointEx({bool ignoreCurrent = false}) {
    if (_filteredGrenades.isEmpty) {
      _isSnapped = false;
      _suppressedSnapGrenadeId = null;
      _suppressedSnapTimer?.cancel();
      return;
    }

    final clusters = _clusters;
    if (clusters.isEmpty) {
      _isSnapped = false;
      _suppressedSnapGrenadeId = null;
      _suppressedSnapTimer?.cancel();
      return;
    }

    final currentGrenadeId = currentGrenade?.id;
    GrenadeCluster? nearestCluster;
    double minDist = double.infinity;
    double nearestSnapThresholdSq = _snapThreshold * _snapThreshold;

    for (final cluster in clusters) {
      // 使用 cluster 第一个元素作为中心（与 _clusterGrenades 的构建逻辑和 RadarMiniMap 的显示逻辑保持一致）
      // 之前使用平均值会导致吸附点（first）与引力中心（average）不重合，导致移动时可能反而更靠近引力中心而无法逃离
      final centerPoint = cluster.anchor;
      final centerX = centerPoint.xRatio;
      final centerY = centerPoint.yRatio;
      final isCurrentCluster = currentGrenadeId != null &&
          cluster.containsGrenade(currentGrenadeId);
      final clusterSnapThreshold =
          isCurrentCluster && _suppressedSnapGrenadeId == null
              ? _snapThreshold * _snapReleaseMultiplier
              : _snapThreshold;
      final clusterSnapThresholdSq =
          clusterSnapThreshold * clusterSnapThreshold;

      if (_suppressedSnapGrenadeId != null &&
          cluster.containsGrenade(_suppressedSnapGrenadeId!)) {
        final dx = centerX - _crosshairX;
        final dy = centerY - _crosshairY;
        final dist = dx * dx + dy * dy;
        if (dist < clusterSnapThresholdSq) {
          continue;
        }
      }

      // 如果要求忽略当前 cluster，检查是否是当前所在的 cluster
      if (ignoreCurrent &&
          _suppressedSnapGrenadeId == null &&
          isCurrentCluster) {
          continue; // 跳过当前 cluster
      }

      // 计算准星到 cluster 中心的距离
      final dx = centerX - _crosshairX;
      final dy = centerY - _crosshairY;
      final dist = dx * dx + dy * dy;

      if (dist < minDist) {
        minDist = dist;
        nearestCluster = cluster;
        nearestSnapThresholdSq = clusterSnapThresholdSq;
      }
    }

    if (_suppressedSnapGrenadeId != null) {
      final suppressedGrenade = _filteredGrenades
          .where((g) => g.id == _suppressedSnapGrenadeId)
          .cast<Grenade?>()
          .firstWhere(
            (_) => true,
            orElse: () => null,
          );
      if (suppressedGrenade == null) {
        _suppressedSnapGrenadeId = null;
        _suppressedSnapTimer?.cancel();
      } else {
        final dx = suppressedGrenade.xRatio - _crosshairX;
        final dy = suppressedGrenade.yRatio - _crosshairY;
        final releaseThreshold = _snapThreshold * _snapReleaseMultiplier;
        if (dx * dx + dy * dy > releaseThreshold * releaseThreshold) {
          _suppressedSnapGrenadeId = null;
          _suppressedSnapTimer?.cancel();
        }
      }
    }

    // 检查是否在吸附范围内
    if (nearestCluster != null && minDist < nearestSnapThresholdSq) {
      // 吸附到 cluster 的第一个道具（作为代表）
      final nearest = nearestCluster.anchor;
      final wasSnapped = _isSnapped;
      final previousGrenadeId = currentGrenade?.id;

      _crosshairX = nearest.xRatio;
      _crosshairY = nearest.yRatio;
      _currentGrenadeIndex = _filteredGrenades.indexOf(nearest);
      _currentStepIndex = 0;
      _isSnapped = true;
      _suppressedSnapGrenadeId = null;
      _suppressedSnapTimer?.cancel();

      // 如果是新吸附到不同的道具，重置确认状态并启动延迟确认定时器
      if (!wasSnapped || previousGrenadeId != nearest.id) {
        _isSnapConfirmed = false;
        _snapConfirmTimer?.cancel();
        _snapConfirmTimer = Timer(const Duration(milliseconds: 100), () {
          if (_isSnapped && currentGrenade?.id == nearest.id) {
            _isSnapConfirmed = true;
            notifyListeners();
          }
        });
      }
    } else {
      // 未吸附，取消确认状态
      _isSnapped = false;
      _isSnapConfirmed = false;
      _snapConfirmTimer?.cancel();
    }
  }

  /// 开始移动
  void startNavigation(NavigationDirection direction) {
    if (_navigationLocked) return;
    final now = DateTime.now();

    // 关键修复：当按下新方向时，如果有相反方向在活动，先移除相反方向
    // 这样可以避免相反方向同时激活导致的不移动问题
    final opposite = _getOppositeDirection(direction);
    if (_activeDirections.contains(opposite)) {
      _activeDirections.remove(opposite);
      _lastHeartbeat.remove(opposite);
      // debugPrint('[OverlayState] Removed opposite direction: ${opposite!.name}');
    }

    _activeDirections.add(direction);

    // 刷新所有活跃方向的心跳（支持斜向移动时的键盘重复限制）
    for (final dir in _activeDirections) {
      _lastHeartbeat[dir] = now;
    }

    // 调试日志：显示当前活跃的方向
    // debugPrint(
    //     '[OverlayState] Active directions: ${_activeDirections.length} - ${_activeDirections.map((d) => d.name).join(', ')}');

    _startMoveTimer();
    _startHeartbeatTimer();
  }

  /// 反方向
  NavigationDirection? _getOppositeDirection(NavigationDirection dir) {
    switch (dir) {
      case NavigationDirection.up:
        return NavigationDirection.down;
      case NavigationDirection.down:
        return NavigationDirection.up;
      case NavigationDirection.left:
        return NavigationDirection.right;
      case NavigationDirection.right:
        return NavigationDirection.left;
    }
  }

  /// 停止移动
  void stopNavigation(NavigationDirection direction) {
    _activeDirections.remove(direction);
    if (_activeDirections.isEmpty) {
      _stopMoveTimer();
      // 停止移动时，尝试吸附到最近的点（此时不再忽略当前点）
      _checkAndSnapToPointEx(ignoreCurrent: false);
      notifyListeners();
    }
  }

  /// 停止所有
  void stopAllNavigation() {
    _activeDirections.clear();
    _stopMoveTimer();
    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  /// 启动定时器
  void _startMoveTimer() {
    if (_moveTimer != null) return;

    _moveTimer = Timer.periodic(
      Duration(milliseconds: _moveIntervalMs),
      (_) => _updateCrosshairPosition(),
    );
    // 立即执行一次
    _updateCrosshairPosition();
  }

  /// 停止定时器
  void _stopMoveTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  /// 启动心跳
  void _startHeartbeatTimer() {
    if (_heartbeatTimer != null) return;

    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = DateTime.now();
      final toStop = <NavigationDirection>[];

      // 使用固定短超时（80ms），保证响应跟手
      const timeout = 80;

      for (final dir in _activeDirections) {
        final last = _lastHeartbeat[dir];
        if (last != null) {
          if (now.difference(last).inMilliseconds > timeout) {
            toStop.add(dir);
          }
        }
      }

      if (toStop.isNotEmpty) {
        for (final dir in toStop) {
          _activeDirections.remove(dir);
          _lastHeartbeat.remove(dir);
          // debugPrint('[OverlayState] Heartbeat timeout for: ${dir.name}');
        }

        if (_activeDirections.isEmpty) {
          _stopMoveTimer();
          _checkAndSnapToPointEx(ignoreCurrent: false);
          notifyListeners();
        }
      }

      if (_activeDirections.isEmpty) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
      }
    });
  }

  /// 更新位置
  void _updateCrosshairPosition() {
    if (_activeDirections.isEmpty) return;
    _recordNavigationActivity();

    double dx = 0;
    double dy = 0;

    // 计算移动向量（支持同时按多个方向键）
    for (final dir in _activeDirections) {
      switch (dir) {
        case NavigationDirection.up:
          dy -= _moveSpeed;
          break;
        case NavigationDirection.down:
          dy += _moveSpeed;
          break;
        case NavigationDirection.left:
          dx -= _moveSpeed;
          break;
        case NavigationDirection.right:
          dx += _moveSpeed;
          break;
      }
    }

    // 对角线移动时归一化速度
    if (dx != 0 && dy != 0) {
      final factor = 0.707; // 1/sqrt(2)
      dx *= factor;
      dy *= factor;
    }

    // 如果当前已吸附，开始逃离时减速（增加吸附粘性）
    // 减速因子 0.8 意味着刚开始移动时只有 80% 的速度
    final wasSnapped = _isSnapped;
    if (wasSnapped) {
      dx *= 0.5;
      dy *= 0.5;
      _isSnapped = false;
      // 一旦用户从吸附态开始移动，立刻临时压制当前点位，
      // 避免在密集点位中还没走出释放阈值就被立即吸回去。
      _markCurrentSnapAsSuppressed();
    }

    // 应用移动
    _crosshairX = (_crosshairX + dx).clamp(0.0, 1.0);
    _crosshairY = (_crosshairY + dy).clamp(0.0, 1.0);

    // 当前点位的压制由 _suppressedSnapGrenadeId 管理；
    // 这里不再等“走出释放阈值后”才开始压制，否则会被原点反复吸回。
    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  /// 单次移动
  void navigateDirection(NavigationDirection direction) {
    if (_navigationLocked) return;
    _recordNavigationActivity();
    // 记录移动前是否处于吸附状态
    final wasSnapped = _isSnapped;

    // 基础移动步长
    double step = _moveSpeed * 8;

    // 如果是从吸附状态开始移动，强制步长大于吸附阈值，确保逃离
    if (wasSnapped) {
      // 1.5倍吸附阈值，确保一步移出引力圈（_checkAndSnapToPointEx 判断距离 < _snapThreshold）
      final escapeStep = _snapThreshold * 1.5;
      if (step < escapeStep) {
        step = escapeStep;
      }
    }

    // 如果当前已吸附，先解除吸附状态才能移动
    if (_isSnapped) {
      _isSnapped = false;
      // 单步导航同样需要先压制当前点位，否则密集点位会表现成“按了没动”。
      _markCurrentSnapAsSuppressed();
    }

    switch (direction) {
      case NavigationDirection.up:
        _crosshairY = (_crosshairY - step).clamp(0.0, 1.0);
        break;
      case NavigationDirection.down:
        _crosshairY = (_crosshairY + step).clamp(0.0, 1.0);
        break;
      case NavigationDirection.left:
        _crosshairX = (_crosshairX - step).clamp(0.0, 1.0);
        break;
      case NavigationDirection.right:
        _crosshairX = (_crosshairX + step).clamp(0.0, 1.0);
        break;
    }

    // 当前点位的压制由 _suppressedSnapGrenadeId 管理。
    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  void _markCurrentSnapAsSuppressed() {
    final grenade = currentGrenade;
    if (grenade == null) return;
    _suppressedSnapGrenadeId = grenade.id;
    _scheduleSuppressedSnapReset();
  }

  void _recordNavigationActivity() {
    _lastNavigationActivityAt = DateTime.now();
    if (_suppressedSnapGrenadeId != null) {
      _scheduleSuppressedSnapReset();
    }
  }

  void _scheduleSuppressedSnapReset() {
    _suppressedSnapTimer?.cancel();
    _suppressedSnapTimer = Timer(const Duration(milliseconds: 500), () {
      final lastActivityAt = _lastNavigationActivityAt;
      if (lastActivityAt == null) {
        _clearSuppressedSnapAndResnap();
        return;
      }

      final idleFor = DateTime.now().difference(lastActivityAt);
      if (idleFor < const Duration(milliseconds: 500)) {
        _scheduleSuppressedSnapReset();
        return;
      }

      if (_activeDirections.isNotEmpty) {
        _scheduleSuppressedSnapReset();
        return;
      }

      _clearSuppressedSnapAndResnap();
    });
  }

  void _clearSuppressedSnapAndResnap() {
    if (_suppressedSnapGrenadeId == null) return;
    _suppressedSnapGrenadeId = null;
    _suppressedSnapTimer?.cancel();
    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  /// 设置索引
  void setGrenadeIndex(int index) {
    if (index >= 0 && index < _filteredGrenades.length) {
      _currentGrenadeIndex = index;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }
}

enum NavigationDirection { up, down, left, right }
