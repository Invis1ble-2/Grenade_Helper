import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';

/// 悬浮窗状态服务 - 管理悬浮窗与主窗口的状态同步
class OverlayStateService extends ChangeNotifier {
  final Isar isar;

  // 当前选中的地图和楼层
  GameMap? _currentMap;
  MapLayer? _currentLayer;

  // 当前地图的所有道具（已过滤）
  List<Grenade> _allGrenades = [];
  List<Grenade> _filteredGrenades = [];

  // 当前选中的道具索引
  int _currentGrenadeIndex = 0;
  int _currentStepIndex = 0;

  // 过滤器状态
  final Set<int> _activeFilters = {
    GrenadeType.smoke,
    GrenadeType.flash,
    GrenadeType.molotov,
    GrenadeType.he,
  };

  // 准星位置 (0.0-1.0 比例坐标)
  double _crosshairX = 0.5;
  double _crosshairY = 0.5;
  bool _isSnapped = false;

  // 准星移动常量
  static const double _snapThreshold = 0.02; // 吸附阈值
  static const int _moveIntervalMs = 16; // 约60fps

  // 速度档位配置 (1-5档对应的速度值)
  static const List<double> _speedLevels = [
    0.0025, // 1档 - 最慢
    0.003, // 2档
    0.004, // 3档 - 当前默认
    0.0045, // 4档
    0.005, // 5档 - 最快
  ];

  // 当前速度档位 (1-5)
  int _navSpeedLevel = 3;

  /// 获取当前速度档位
  int get navSpeedLevel => _navSpeedLevel;

  /// 设置速度档位 (1-5)
  void setNavSpeedLevel(int level) {
    _navSpeedLevel = level.clamp(1, 5);
    print(
        '[OverlayStateService] setNavSpeedLevel: $level -> $_navSpeedLevel, speed: ${_speedLevels[_navSpeedLevel - 1]}');
  }

  /// 获取当前速度值
  double get _moveSpeed {
    final speed = _speedLevels[_navSpeedLevel - 1];
    return speed;
  }

  // 连续移动状态
  final Set<NavigationDirection> _activeDirections = {};
  Timer? _moveTimer;

  // 记忆：最后查看的道具 ID（按地图分组）
  final Map<int, int> _lastViewedGrenadeByMap = {};

  // 数据监听订阅
  StreamSubscription<void>? _grenadeSubscription;

  // 视频播放控制回调
  VoidCallback? _videoTogglePlayPauseCallback;

  OverlayStateService(this.isar);

  /// 注册视频播放/暂停回调
  void setVideoTogglePlayPauseCallback(VoidCallback? callback) {
    _videoTogglePlayPauseCallback = callback;
  }

  /// 触发视频播放/暂停
  void triggerVideoTogglePlayPause() {
    print('[OverlayStateService] triggerVideoTogglePlayPause called');
    _videoTogglePlayPauseCallback?.call();
  }

  /// 触发 UI 刷新（用于外部通知设置变更）
  void refresh() {
    notifyListeners();
  }

  // 悬浮窗透明度（用于跨进程 IPC 更新）
  double _overlayOpacity = 0.9;
  double get overlayOpacity => _overlayOpacity;

  /// 设置悬浮窗透明度（由 IPC 调用）
  void setOpacity(double value) {
    _overlayOpacity = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
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

  Grenade? get currentGrenade {
    if (_filteredGrenades.isEmpty ||
        _currentGrenadeIndex < 0 ||
        _currentGrenadeIndex >= _filteredGrenades.length) {
      return null;
    }
    return _filteredGrenades[_currentGrenadeIndex];
  }

  /// 合并阈值（与 map_screen.dart 中的 clusterGrenades 保持一致）
  static const double _clusterThreshold = 0.03;

  /// 获取当前点位（cluster）内的所有道具
  List<Grenade> get currentClusterGrenades {
    final current = currentGrenade;
    if (current == null) return [];

    return _filteredGrenades.where((g) {
      final dx = (g.xRatio - current.xRatio).abs();
      final dy = (g.yRatio - current.yRatio).abs();
      return (dx * dx + dy * dy) < _clusterThreshold * _clusterThreshold;
    }).toList();
  }

  /// 当前道具在 cluster 内的索引
  int get currentClusterIndex {
    final cluster = currentClusterGrenades;
    if (cluster.isEmpty || currentGrenade == null) return 0;
    return cluster.indexWhere((g) => g.id == currentGrenade!.id);
  }

  bool get hasMap => _currentMap != null && _currentLayer != null;

  /// 设置当前地图（从 MapScreen 调用）
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

  /// 清除地图上下文（离开 MapScreen 时）
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
    _currentGrenadeIndex = 0;
    _currentStepIndex = 0;
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
        print('OverlayStateService: Data changed, reloading...');
        _loadGrenades(notify: true);
      });
    }
  }

  /// 加载当前楼层的道具
  void _loadGrenades({bool notify = false}) {
    if (_currentLayer == null) {
      _allGrenades.clear();
      _filteredGrenades.clear();
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

  /// 应用过滤器
  void _applyFilters() {
    // 保存当前选中的道具 ID（用于恢复位置）
    final currentGrenadeId = currentGrenade?.id;

    _filteredGrenades =
        _allGrenades.where((g) => _activeFilters.contains(g.type)).toList();

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

  /// 切换过滤器
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

  /// 切换到当前点位的上一个道具（只在同一点位内循环）
  void prevGrenade() {
    final cluster = currentClusterGrenades;
    if (cluster.isEmpty) return;

    final clusterIdx = currentClusterIndex;
    final newClusterIdx = (clusterIdx - 1 + cluster.length) % cluster.length;
    final targetGrenade = cluster[newClusterIdx];

    // 找到该道具在 filteredGrenades 中的索引
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  /// 切换到当前点位的下一个道具（只在同一点位内循环）
  void nextGrenade() {
    final cluster = currentClusterGrenades;
    if (cluster.isEmpty) return;

    final clusterIdx = currentClusterIndex;
    final newClusterIdx = (clusterIdx + 1) % cluster.length;
    final targetGrenade = cluster[newClusterIdx];

    // 找到该道具在 filteredGrenades 中的索引
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  /// 切换到上一步
  void prevStep() {
    if (currentGrenade == null) return;
    final steps = currentGrenade!.steps.toList();
    if (steps.isEmpty) return;
    _currentStepIndex = (_currentStepIndex - 1 + steps.length) % steps.length;
    notifyListeners();
  }

  /// 切换到下一步
  void nextStep() {
    if (currentGrenade == null) return;
    final steps = currentGrenade!.steps.toList();
    if (steps.isEmpty) return;
    _currentStepIndex = (_currentStepIndex + 1) % steps.length;
    notifyListeners();
  }

  /// 初始化准星位置到当前道具位置
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

  /// 检查并吸附到最近的点位
  void _checkAndSnapToPoint() {
    if (_filteredGrenades.isEmpty) {
      _isSnapped = false;
      return;
    }

    Grenade? nearest;
    double minDist = double.infinity;

    for (final g in _filteredGrenades) {
      final dx = g.xRatio - _crosshairX;
      final dy = g.yRatio - _crosshairY;
      final dist = dx * dx + dy * dy;

      if (dist < minDist) {
        minDist = dist;
        nearest = g;
      }
    }

    // 检查是否在吸附范围内
    if (nearest != null && minDist < _snapThreshold * _snapThreshold) {
      // 吸附到点位
      _crosshairX = nearest.xRatio;
      _crosshairY = nearest.yRatio;
      _currentGrenadeIndex = _filteredGrenades.indexOf(nearest);
      _currentStepIndex = 0;
      _isSnapped = true;
    } else {
      // 未吸附
      _isSnapped = false;
    }
  }

  /// 开始向指定方向移动（按下按键时调用）
  void startNavigation(NavigationDirection direction) {
    _activeDirections.add(direction);
    _startMoveTimer();
  }

  /// 停止向指定方向移动（松开按键时调用）
  void stopNavigation(NavigationDirection direction) {
    _activeDirections.remove(direction);
    if (_activeDirections.isEmpty) {
      _stopMoveTimer();
    }
  }

  /// 停止所有方向移动
  void stopAllNavigation() {
    _activeDirections.clear();
    _stopMoveTimer();
  }

  /// 启动移动定时器
  void _startMoveTimer() {
    if (_moveTimer != null) return;

    _moveTimer = Timer.periodic(
      Duration(milliseconds: _moveIntervalMs),
      (_) => _updateCrosshairPosition(),
    );
    // 立即执行一次
    _updateCrosshairPosition();
  }

  /// 停止移动定时器
  void _stopMoveTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  /// 更新准星位置（每帧调用）
  void _updateCrosshairPosition() {
    if (_activeDirections.isEmpty) return;

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

    // 如果当前已吸附，先解除吸附状态才能移动
    // 否则每帧都会被 _checkAndSnapToPoint 拉回吸附点
    if (_isSnapped) {
      _isSnapped = false;
    }

    // 应用移动
    _crosshairX = (_crosshairX + dx).clamp(0.0, 1.0);
    _crosshairY = (_crosshairY + dy).clamp(0.0, 1.0);

    // 检查并吸附到最近点位
    _checkAndSnapToPoint();
    notifyListeners();
  }

  /// 单次移动（兼容旧的单次按键调用，如全局热键）
  void navigateDirection(NavigationDirection direction) {
    // 单次移动步长根据速度档位动态调整（约等于按住80ms的移动量）
    final singleMoveStep = _moveSpeed * 8;

    // 如果当前已吸附，先解除吸附状态才能移动
    if (_isSnapped) {
      _isSnapped = false;
    }

    switch (direction) {
      case NavigationDirection.up:
        _crosshairY = (_crosshairY - singleMoveStep).clamp(0.0, 1.0);
        break;
      case NavigationDirection.down:
        _crosshairY = (_crosshairY + singleMoveStep).clamp(0.0, 1.0);
        break;
      case NavigationDirection.left:
        _crosshairX = (_crosshairX - singleMoveStep).clamp(0.0, 1.0);
        break;
      case NavigationDirection.right:
        _crosshairX = (_crosshairX + singleMoveStep).clamp(0.0, 1.0);
        break;
    }

    _checkAndSnapToPoint();
    notifyListeners();
  }

  /// 直接设置道具索引
  void setGrenadeIndex(int index) {
    if (index >= 0 && index < _filteredGrenades.length) {
      _currentGrenadeIndex = index;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }
}

enum NavigationDirection { up, down, left, right }
