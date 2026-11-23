import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../models.dart';
import '../models/overlay_snapshot.dart';
import 'grenade_cluster_service.dart';
import 'settings_service.dart';

class OverlayStateService extends ChangeNotifier {
  OverlayMapSnapshot? _snapshot;

  List<OverlayGrenadeItem> _allGrenades = const [];
  List<OverlayGrenadeItem> _filteredGrenades = const [];
  List<GrenadeCluster> _clusters = const [];

  int _currentGrenadeIndex = 0;
  int _currentStepIndex = 0;

  final Set<int> _activeFilters = {
    GrenadeType.smoke,
    GrenadeType.flash,
    GrenadeType.molotov,
    GrenadeType.he,
    GrenadeType.wallbang,
  };

  double _crosshairX = 0.5;
  double _crosshairY = 0.5;
  bool _isSnapped = false;

  bool _isSnapConfirmed = false;
  Timer? _snapConfirmTimer;
  int? _suppressedSnapGrenadeId;
  Timer? _suppressedSnapTimer;
  DateTime? _lastNavigationActivityAt;
  _SnapState _snapState = _SnapState.free;
  int? _candidateClusterAnchorId;
  DateTime? _candidateSince;
  int? _lockedClusterAnchorId;

  static const int _moveIntervalMs = 16;

  static const List<double> _speedLevels = [
    0.0025,
    0.003,
    0.004,
    0.0045,
    0.005,
  ];

  static const List<double> _snapThresholdLevels = [
    0.02,
    0.022,
    0.024,
    0.027,
    0.03,
  ];
  static const double _snapReleaseMultiplier = 1.18;
  static const double _snapAcquireRadiusMultiplier = 0.92;
  static const double _snapLockedReleaseMultiplier = 1.55;
  static const Duration _snapCandidateDuration = Duration(milliseconds: 72);

  int _navSpeedLevel = 3;
  bool _navigationLocked = false;

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

  void setNavSpeedLevel(int level) {
    final next = level.clamp(1, 5);
    if (_navSpeedLevel == next) return;
    _navSpeedLevel = next;
    notifyListeners();
  }

  double get _moveSpeed => _speedLevels[_navSpeedLevel - 1];
  double get _snapThreshold => _snapThresholdLevels[_navSpeedLevel - 1];

  void increaseNavSpeed() {
    if (_navSpeedLevel < 5) {
      setNavSpeedLevel(_navSpeedLevel + 1);
    }
  }

  void decreaseNavSpeed() {
    if (_navSpeedLevel > 1) {
      setNavSpeedLevel(_navSpeedLevel - 1);
    }
  }

  final Set<NavigationDirection> _activeDirections = {};
  final Map<NavigationDirection, DateTime> _lastHeartbeat = {};
  Timer? _moveTimer;
  Timer? _heartbeatTimer;

  final Map<int, int> _lastViewedGrenadeByMap = {};
  VoidCallback? _videoTogglePlayPauseCallback;

  void setVideoTogglePlayPauseCallback(VoidCallback? callback) {
    _videoTogglePlayPauseCallback = callback;
  }

  void triggerVideoTogglePlayPause() {
    _videoTogglePlayPauseCallback?.call();
  }

  void refresh() {
    notifyListeners();
  }

  double _overlayOpacity = 0.9;
  double get overlayOpacity => _overlayOpacity;

  void setOpacity(double value) {
    _overlayOpacity = value;
    notifyListeners();
  }

  int _overlaySizeIndex = 1;
  int get overlaySizeIndex => _overlaySizeIndex;

  Future<void> setOverlaySize(int index) async {
    _overlaySizeIndex = index;
    final s = SettingsService.calculateSizePixels(index);
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
    _heartbeatTimer?.cancel();
    _snapConfirmTimer?.cancel();
    _suppressedSnapTimer?.cancel();
    super.dispose();
  }

  String? get mapName => _snapshot?.mapName;
  String? get layerAssetPath => _snapshot?.layerAssetPath;
  List<OverlayGrenadeItem> get filteredGrenades => _filteredGrenades;
  List<OverlayGrenadeItem> get allGrenades => _allGrenades;
  int get currentGrenadeIndex => _currentGrenadeIndex;
  int get currentStepIndex => _currentStepIndex;
  Set<int> get activeFilters => _activeFilters;

  double get crosshairX => _crosshairX;
  double get crosshairY => _crosshairY;
  bool get isSnapped => _isSnapped;
  bool get isSnapConfirmed => _isSnapConfirmed;

  OverlayGrenadeItem? get currentGrenade {
    if (_filteredGrenades.isEmpty ||
        _currentGrenadeIndex < 0 ||
        _currentGrenadeIndex >= _filteredGrenades.length) {
      return null;
    }
    return _filteredGrenades[_currentGrenadeIndex];
  }

  static const double _clusterThreshold = 0.03;

  List<OverlayGrenadeItem> get currentClusterGrenades {
    final cluster = GrenadeClusterService.findClusterForGrenade(
      _clusters,
      currentGrenade,
    );
    return cluster?.members ?? const [];
  }

  int get currentClusterIndex {
    final cluster = currentClusterGrenades;
    if (cluster.isEmpty || currentGrenade == null) return 0;
    return cluster.indexWhere((g) => g.id == currentGrenade!.id);
  }

  bool get hasMap => _snapshot != null;

  void applyMapSnapshot(OverlayMapSnapshot snapshot) {
    final sameLayer = _snapshot != null &&
        _snapshot!.mapId == snapshot.mapId &&
        _snapshot!.layerId == snapshot.layerId;

    if (sameLayer) {
      final wasEmpty = _filteredGrenades.isEmpty;
      _snapshot = snapshot;
      _allGrenades = snapshot.grenades;
      _applyFilters(preserveStep: true);
      if (wasEmpty && _filteredGrenades.isNotEmpty) {
        _initCrosshairPosition();
      }
      notifyListeners();
      return;
    }

    if (_snapshot != null && currentGrenade != null) {
      _lastViewedGrenadeByMap[_snapshot!.mapId] = currentGrenade!.id;
    }

    _snapshot = snapshot;
    _allGrenades = snapshot.grenades;
    _applyFilters();

    final lastGrenadeId = _lastViewedGrenadeByMap[snapshot.mapId];
    if (lastGrenadeId != null) {
      final idx = _filteredGrenades.indexWhere((g) => g.id == lastGrenadeId);
      _currentGrenadeIndex = idx >= 0 ? idx : 0;
    } else {
      _currentGrenadeIndex = 0;
    }
    _currentStepIndex = 0;
    _initCrosshairPosition();
    notifyListeners();
  }

  void clearMap() {
    if (_snapshot != null && currentGrenade != null) {
      _lastViewedGrenadeByMap[_snapshot!.mapId] = currentGrenade!.id;
    }

    _snapshot = null;
    _allGrenades = const [];
    _filteredGrenades = const [];
    _clusters = const [];
    _currentGrenadeIndex = 0;
    _currentStepIndex = 0;
    _resetSnapState();
    _lastNavigationActivityAt = null;
    notifyListeners();
  }

  void _applyFilters({bool preserveStep = false}) {
    final currentGrenadeId = currentGrenade?.id;
    final previousStepIndex = _currentStepIndex;

    _filteredGrenades = GrenadeClusterService.sortGrenades(
      _allGrenades.where((g) => _activeFilters.contains(g.type)),
    );
    _clusters = GrenadeClusterService.buildClusters(
      _filteredGrenades,
      threshold: _clusterThreshold,
    );
    _syncSnapStateWithClusters();

    if (_filteredGrenades.isEmpty) {
      _currentGrenadeIndex = 0;
      _currentStepIndex = 0;
      return;
    }

    if (currentGrenadeId != null) {
      final idx = _filteredGrenades.indexWhere((g) => g.id == currentGrenadeId);
      _currentGrenadeIndex = idx >= 0 ? idx : 0;
      if (preserveStep && idx >= 0) {
        final stepCount = _filteredGrenades[idx].steps.length;
        _currentStepIndex =
            stepCount > 0 ? previousStepIndex.clamp(0, stepCount - 1) : 0;
        return;
      }
    } else {
      _currentGrenadeIndex = 0;
    }

    _currentStepIndex = 0;
  }

  void toggleFilter(int type) {
    if (_activeFilters.contains(type)) {
      if (_activeFilters.length > 1) {
        _activeFilters.remove(type);
      }
    } else {
      _activeFilters.add(type);
    }
    _applyFilters();
    notifyListeners();
  }

  void prevGrenade() {
    final cluster = currentClusterGrenades;
    if (cluster.length <= 1) return;

    final clusterIdx = currentClusterIndex;
    if (clusterIdx <= 0) return;

    final targetGrenade = cluster[clusterIdx - 1];
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0 && globalIdx != _currentGrenadeIndex) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  void nextGrenade() {
    final cluster = currentClusterGrenades;
    if (cluster.length <= 1) return;

    final clusterIdx = currentClusterIndex;
    if (clusterIdx < 0 || clusterIdx >= cluster.length - 1) return;

    final targetGrenade = cluster[clusterIdx + 1];
    final globalIdx =
        _filteredGrenades.indexWhere((g) => g.id == targetGrenade.id);
    if (globalIdx >= 0 && globalIdx != _currentGrenadeIndex) {
      _currentGrenadeIndex = globalIdx;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }

  void prevStep() {
    final grenade = currentGrenade;
    if (grenade == null || grenade.steps.isEmpty) return;
    _currentStepIndex =
        (_currentStepIndex - 1 + grenade.steps.length) % grenade.steps.length;
    notifyListeners();
  }

  void nextStep() {
    final grenade = currentGrenade;
    if (grenade == null || grenade.steps.isEmpty) return;
    _currentStepIndex = (_currentStepIndex + 1) % grenade.steps.length;
    notifyListeners();
  }

  void _initCrosshairPosition() {
    _resetSnapState();
    final grenade = currentGrenade;
    if (grenade == null) {
      _crosshairX = 0.5;
      _crosshairY = 0.5;
      return;
    }

    final cluster =
        GrenadeClusterService.findClusterForGrenade(_clusters, grenade);
    _crosshairX = cluster?.anchor.xRatio ?? grenade.xRatio;
    _crosshairY = cluster?.anchor.yRatio ?? grenade.yRatio;
    _lockedClusterAnchorId = cluster?.anchor.id ?? grenade.id;
    _snapState = _SnapState.locked;
    _isSnapped = true;
    _isSnapConfirmed = true;
  }

  void _checkAndSnapToPointEx({bool ignoreCurrent = false}) {
    if (_filteredGrenades.isEmpty || _clusters.isEmpty) {
      _resetSnapState();
      return;
    }

    _syncSnapStateWithClusters();
    _updateSuppressedClusterState();

    final lockedCluster = _findClusterByAnchorId(_lockedClusterAnchorId);
    if (lockedCluster != null &&
        !_isClusterSuppressed(lockedCluster) &&
        _distanceSqToCluster(lockedCluster) <= _snapLockedReleaseRadiusSq) {
      _applyLockedCluster(lockedCluster, preserveCurrentSelection: true);
      return;
    }
    if (lockedCluster == null ||
        _distanceSqToCluster(lockedCluster) > _snapLockedReleaseRadiusSq) {
      _lockedClusterAnchorId = null;
      if (_snapState == _SnapState.locked) {
        _setUnsnappedState(_SnapState.free);
      }
    }

    final nearestResult =
        _findNearestEligibleCluster(ignoreCurrent: ignoreCurrent);
    if (nearestResult == null) {
      _setUnsnappedState(_SnapState.free);
      return;
    }

    final nearestCluster = nearestResult.cluster;
    if (nearestResult.distanceSq > _snapAcquireRadiusSq) {
      _setUnsnappedState(_SnapState.free);
      return;
    }

    final requiredCandidateDuration =
        _activeDirections.isNotEmpty ? _snapCandidateDuration : Duration.zero;
    final anchorId = nearestCluster.anchor.id;

    if (requiredCandidateDuration == Duration.zero) {
      _applyLockedCluster(nearestCluster);
      return;
    }

    final now = DateTime.now();
    if (_candidateClusterAnchorId != anchorId) {
      _candidateClusterAnchorId = anchorId;
      _candidateSince = now;
      _setUnsnappedState(_SnapState.candidate);
      return;
    }

    final candidateSince = _candidateSince ?? now;
    if (now.difference(candidateSince) < requiredCandidateDuration) {
      _setUnsnappedState(_SnapState.candidate);
      return;
    }

    _applyLockedCluster(nearestCluster);
  }

  void startNavigation(NavigationDirection direction) {
    if (_navigationLocked) return;
    final now = DateTime.now();

    final opposite = _getOppositeDirection(direction);
    if (_activeDirections.contains(opposite)) {
      _activeDirections.remove(opposite);
      _lastHeartbeat.remove(opposite);
    }

    _activeDirections.add(direction);
    for (final dir in _activeDirections) {
      _lastHeartbeat[dir] = now;
    }

    _startMoveTimer();
    _startHeartbeatTimer();
  }

  NavigationDirection _getOppositeDirection(NavigationDirection dir) {
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

  void stopNavigation(NavigationDirection direction) {
    _activeDirections.remove(direction);
    if (_activeDirections.isEmpty) {
      _stopMoveTimer();
      _checkAndSnapToPointEx(ignoreCurrent: false);
      notifyListeners();
    }
  }

  void stopAllNavigation() {
    _activeDirections.clear();
    _stopMoveTimer();
    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  void _startMoveTimer() {
    if (_moveTimer != null) return;

    _moveTimer = Timer.periodic(
      const Duration(milliseconds: _moveIntervalMs),
      (_) => _updateCrosshairPosition(),
    );
    _updateCrosshairPosition();
  }

  void _stopMoveTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  void _startHeartbeatTimer() {
    if (_heartbeatTimer != null) return;

    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = DateTime.now();
      final toStop = <NavigationDirection>[];
      const timeout = 80;

      for (final dir in _activeDirections) {
        final last = _lastHeartbeat[dir];
        if (last != null && now.difference(last).inMilliseconds > timeout) {
          toStop.add(dir);
        }
      }

      if (toStop.isNotEmpty) {
        for (final dir in toStop) {
          _activeDirections.remove(dir);
          _lastHeartbeat.remove(dir);
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

  void _updateCrosshairPosition() {
    if (_activeDirections.isEmpty) return;
    _recordNavigationActivity();

    double dx = 0;
    double dy = 0;

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

    if (dx != 0 && dy != 0) {
      const factor = 0.707;
      dx *= factor;
      dy *= factor;
    }

    if (_isSnapped) {
      dx *= 0.5;
      dy *= 0.5;
      _isSnapped = false;
      _markCurrentSnapAsSuppressed();
    }

    _crosshairX = (_crosshairX + dx).clamp(0.0, 1.0);
    _crosshairY = (_crosshairY + dy).clamp(0.0, 1.0);

    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  void navigateDirection(NavigationDirection direction) {
    if (_navigationLocked) return;
    _recordNavigationActivity();
    final wasSnapped = _isSnapped;

    double step = _moveSpeed * 8;
    if (wasSnapped) {
      final escapeStep = _snapThreshold * 1.5;
      if (step < escapeStep) {
        step = escapeStep;
      }
    }

    if (_isSnapped) {
      _isSnapped = false;
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

    _checkAndSnapToPointEx(ignoreCurrent: false);
    notifyListeners();
  }

  void _markCurrentSnapAsSuppressed() {
    final cluster = _currentCluster;
    if (cluster == null) return;
    _suppressedSnapGrenadeId = cluster.anchor.id;
    _lockedClusterAnchorId = null;
    if (_snapState == _SnapState.locked) {
      _setUnsnappedState(_SnapState.free);
    }
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
      if (idleFor < const Duration(milliseconds: 500) ||
          _activeDirections.isNotEmpty) {
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

  GrenadeCluster? get _currentCluster =>
      GrenadeClusterService.findClusterForGrenade(_clusters, currentGrenade) ??
      _findClusterByAnchorId(_lockedClusterAnchorId);

  GrenadeCluster? _findClusterByAnchorId(int? anchorId) {
    if (anchorId == null) return null;
    for (final cluster in _clusters) {
      if (cluster.anchor.id == anchorId) {
        return cluster;
      }
    }
    return null;
  }

  ({GrenadeCluster cluster, double distanceSq})? _findNearestEligibleCluster({
    required bool ignoreCurrent,
  }) {
    final currentClusterAnchorId = _currentCluster?.anchor.id;
    ({GrenadeCluster cluster, double distanceSq})? nearest;

    for (final cluster in _clusters) {
      if (ignoreCurrent &&
          _suppressedSnapGrenadeId == null &&
          currentClusterAnchorId == cluster.anchor.id) {
        continue;
      }
      if (_isClusterSuppressed(cluster)) {
        continue;
      }

      final distanceSq = _distanceSqToCluster(cluster);
      if (nearest == null || distanceSq < nearest.distanceSq) {
        nearest = (cluster: cluster, distanceSq: distanceSq);
      }
    }

    return nearest;
  }

  double _distanceSqToCluster(GrenadeCluster cluster) {
    final dx = cluster.anchor.xRatio - _crosshairX;
    final dy = cluster.anchor.yRatio - _crosshairY;
    return dx * dx + dy * dy;
  }

  double get _snapAcquireRadiusSq {
    final radius = _snapThreshold * _snapAcquireRadiusMultiplier;
    return radius * radius;
  }

  double get _snapLockedReleaseRadiusSq {
    final radius = _snapThreshold * _snapLockedReleaseMultiplier;
    return radius * radius;
  }

  bool _isClusterSuppressed(GrenadeCluster cluster) {
    if (_suppressedSnapGrenadeId == null) return false;
    final distanceSq = _distanceSqToCluster(cluster);
    final releaseRadius = _snapThreshold * _snapReleaseMultiplier;
    return cluster.anchor.id == _suppressedSnapGrenadeId &&
        distanceSq < releaseRadius * releaseRadius;
  }

  void _updateSuppressedClusterState() {
    if (_suppressedSnapGrenadeId == null) return;
    final suppressedCluster = _findClusterByAnchorId(_suppressedSnapGrenadeId);
    if (suppressedCluster == null) {
      _suppressedSnapGrenadeId = null;
      _suppressedSnapTimer?.cancel();
      return;
    }

    final releaseRadius = _snapThreshold * _snapReleaseMultiplier;
    if (_distanceSqToCluster(suppressedCluster) >
        releaseRadius * releaseRadius) {
      _suppressedSnapGrenadeId = null;
      _suppressedSnapTimer?.cancel();
    }
  }

  void _applyLockedCluster(
    GrenadeCluster cluster, {
    bool preserveCurrentSelection = false,
  }) {
    final wasSnapped = _isSnapped;
    final previousGrenadeId = currentGrenade?.id;

    _crosshairX = cluster.anchor.xRatio;
    _crosshairY = cluster.anchor.yRatio;
    _lockedClusterAnchorId = cluster.anchor.id;
    _candidateClusterAnchorId = null;
    _candidateSince = null;
    _snapState = _SnapState.locked;

    final current = currentGrenade;
    final targetGrenade = preserveCurrentSelection &&
            current != null &&
            cluster.containsGrenade(current.id)
        ? current
        : cluster.anchor;
    final globalIdx = _filteredGrenades
        .indexWhere((grenade) => grenade.id == targetGrenade.id);
    if (globalIdx >= 0) {
      _currentGrenadeIndex = globalIdx;
    }
    _currentStepIndex = 0;
    _isSnapped = true;
    _suppressedSnapGrenadeId = null;
    _suppressedSnapTimer?.cancel();

    if (!wasSnapped || previousGrenadeId != targetGrenade.id) {
      _isSnapConfirmed = false;
      _snapConfirmTimer?.cancel();
      _snapConfirmTimer = Timer(const Duration(milliseconds: 100), () {
        if (_isSnapped && _lockedClusterAnchorId == cluster.anchor.id) {
          _isSnapConfirmed = true;
          notifyListeners();
        }
      });
    }
  }

  void _setUnsnappedState(_SnapState state) {
    _snapState = state;
    if (state != _SnapState.candidate) {
      _candidateClusterAnchorId = null;
      _candidateSince = null;
    }
    _isSnapped = false;
    _isSnapConfirmed = false;
    _snapConfirmTimer?.cancel();
  }

  void _resetSnapState() {
    _snapState = _SnapState.free;
    _candidateClusterAnchorId = null;
    _candidateSince = null;
    _lockedClusterAnchorId = null;
    _suppressedSnapGrenadeId = null;
    _suppressedSnapTimer?.cancel();
    _isSnapped = false;
    _isSnapConfirmed = false;
    _snapConfirmTimer?.cancel();
  }

  void _syncSnapStateWithClusters() {
    final currentCluster = _currentCluster;
    if (_suppressedSnapGrenadeId != null &&
        _findClusterByAnchorId(_suppressedSnapGrenadeId) == null) {
      _suppressedSnapGrenadeId = null;
      _suppressedSnapTimer?.cancel();
    }
    if (_candidateClusterAnchorId != null &&
        _findClusterByAnchorId(_candidateClusterAnchorId) == null) {
      _candidateClusterAnchorId = null;
      _candidateSince = null;
      if (_snapState == _SnapState.candidate) {
        _setUnsnappedState(_SnapState.free);
      }
    }
    if (_lockedClusterAnchorId != null &&
        _findClusterByAnchorId(_lockedClusterAnchorId) == null) {
      _lockedClusterAnchorId = null;
      if (_snapState == _SnapState.locked) {
        _setUnsnappedState(_SnapState.free);
      }
    }
    if (_isSnapped && currentCluster != null) {
      _lockedClusterAnchorId = currentCluster.anchor.id;
      _snapState = _SnapState.locked;
    }
  }

  void setGrenadeIndex(int index) {
    if (index >= 0 && index < _filteredGrenades.length) {
      _currentGrenadeIndex = index;
      _currentStepIndex = 0;
      notifyListeners();
    }
  }
}

enum NavigationDirection { up, down, left, right }

enum _SnapState { free, candidate, locked }
