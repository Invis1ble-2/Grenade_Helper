import 'package:flutter/foundation.dart';
import '../models.dart';

/// 悬浮窗状态服务 - 管理悬浮窗与主窗口的状态同步
class OverlayStateService extends ChangeNotifier {
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

  // 记忆：最后查看的道具 ID（按地图分组）
  final Map<int, int> _lastViewedGrenadeByMap = {};

  OverlayStateService();

  // Getters
  GameMap? get currentMap => _currentMap;
  MapLayer? get currentLayer => _currentLayer;
  List<Grenade> get filteredGrenades => _filteredGrenades;
  List<Grenade> get allGrenades => _allGrenades;
  int get currentGrenadeIndex => _currentGrenadeIndex;
  int get currentStepIndex => _currentStepIndex;
  Set<int> get activeFilters => _activeFilters;

  Grenade? get currentGrenade {
    if (_filteredGrenades.isEmpty ||
        _currentGrenadeIndex < 0 ||
        _currentGrenadeIndex >= _filteredGrenades.length) {
      return null;
    }
    return _filteredGrenades[_currentGrenadeIndex];
  }

  bool get hasMap => _currentMap != null && _currentLayer != null;

  /// 设置当前地图（从 MapScreen 调用）
  void setCurrentMap(GameMap map, MapLayer layer) {
    _currentMap = map;
    _currentLayer = layer;
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

    notifyListeners();
  }

  /// 清除地图上下文（离开 MapScreen 时）
  void clearMap() {
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

  /// 加载当前楼层的道具
  void _loadGrenades() {
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
  }

  /// 刷新数据（用于悬浮窗实时更新）
  void refresh() {
    if (_currentLayer == null) return;
    _loadGrenades();
    notifyListeners();
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

  /// 切换到上一个道具
  void prevGrenade() {
    if (_filteredGrenades.isEmpty) return;
    _currentGrenadeIndex =
        (_currentGrenadeIndex - 1 + _filteredGrenades.length) %
            _filteredGrenades.length;
    _currentStepIndex = 0;
    notifyListeners();
  }

  /// 切换到下一个道具
  void nextGrenade() {
    if (_filteredGrenades.isEmpty) return;
    _currentGrenadeIndex =
        (_currentGrenadeIndex + 1) % _filteredGrenades.length;
    _currentStepIndex = 0;
    notifyListeners();
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

  /// 空间导航 - 向指定方向导航
  void navigateDirection(NavigationDirection direction) {
    if (currentGrenade == null || _filteredGrenades.isEmpty) return;

    final current = currentGrenade!;
    Grenade? nearest;
    double minDist = double.infinity;

    for (int i = 0; i < _filteredGrenades.length; i++) {
      if (i == _currentGrenadeIndex) continue;

      final g = _filteredGrenades[i];
      final dx = g.xRatio - current.xRatio;
      final dy = g.yRatio - current.yRatio;

      // 检查是否在正确的方向上
      bool isInDirection = false;
      switch (direction) {
        case NavigationDirection.up:
          isInDirection = dy < -0.01;
          break;
        case NavigationDirection.down:
          isInDirection = dy > 0.01;
          break;
        case NavigationDirection.left:
          isInDirection = dx < -0.01;
          break;
        case NavigationDirection.right:
          isInDirection = dx > 0.01;
          break;
      }

      if (isInDirection) {
        final dist = dx * dx + dy * dy;
        if (dist < minDist) {
          minDist = dist;
          nearest = g;
        }
      }
    }

    if (nearest != null) {
      _currentGrenadeIndex = _filteredGrenades.indexOf(nearest);
      _currentStepIndex = 0;
      notifyListeners();
    }
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
