import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isar_community/isar.dart';
import '../services/settings_service.dart';
import '../services/seasonal_theme_service.dart';
import '../services/data_service.dart';
import '../services/map_management_service.dart';
import '../services/lan_sync/lan_sync_local_store.dart';
import '../services/tag_service.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/map_icon.dart';
import '../main.dart' show sendOverlayCommand;
import 'grenade_select_delete_screen.dart';

/// 设置
class SettingsScreen extends ConsumerStatefulWidget {
  final SettingsService? settingsService;
  final Future<void> Function(HotkeyAction, HotkeyConfig)? onHotkeyChanged;
  final Future<void> Function()? onHotkeysReset;

  const SettingsScreen({
    super.key,
    this.settingsService,
    this.onHotkeyChanged,
    this.onHotkeysReset,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const Map<HotkeyAction, String> _hotkeyActionLabels = {
    HotkeyAction.toggleOverlay: '显示/隐藏悬浮窗',
    HotkeyAction.navigateUp: '向上导航点位',
    HotkeyAction.navigateDown: '向下导航点位',
    HotkeyAction.navigateLeft: '向左导航点位',
    HotkeyAction.navigateRight: '向右导航点位',
    HotkeyAction.prevGrenade: '上一个道具',
    HotkeyAction.nextGrenade: '下一个道具',
    HotkeyAction.prevStep: '上一个步骤',
    HotkeyAction.nextStep: '下一个步骤',
    HotkeyAction.toggleSmoke: '烟雾弹过滤开关',
    HotkeyAction.toggleFlash: '闪光弹过滤开关',
    HotkeyAction.toggleMolotov: '燃烧弹过滤开关',
    HotkeyAction.toggleHE: '手雷过滤开关',
    HotkeyAction.toggleWallbang: '穿点过滤开关',
    HotkeyAction.hideOverlay: '隐藏悬浮窗',
    HotkeyAction.togglePlayPause: '悬浮窗播放/暂停视频',
    HotkeyAction.toggleMediaFullscreenPreview: '媒体全屏预览',
    HotkeyAction.increaseNavSpeed: '增加导航速度',
    HotkeyAction.decreaseNavSpeed: '减少导航速度',
    HotkeyAction.scrollUp: '向上滚动',
    HotkeyAction.scrollDown: '向下滚动',
  };

  late Map<HotkeyAction, HotkeyConfig> _hotkeys;
  late double _overlayOpacity;
  late int _overlaySize; // 悬浮窗尺寸
  late bool _closeToTray;
  late int _overlayNavSpeed; // 导航速度
  // 连线设置
  late int _mapLineColor;
  late double _mapLineOpacity;
  late double _impactAreaOpacity;
  // 摇杆设置
  late int _markerMoveMode;
  late int _grenadeCreateMode;
  late bool _showMapGrenadeList;
  late bool _highDensityClusterMode;
  late double _joystickOpacity;
  late int _joystickSpeed;
  // 存储路径
  String _currentDataPath = '';
  String _defaultDataPath = '';
  bool _isLoadingLanSyncDebug = false;
  LanSyncTombstoneStats _lanSyncTombstoneStats =
      const LanSyncTombstoneStats(grenadeCount: 0, entityCount: 0);

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 激活时重载
    _loadSettings();
  }

  void _loadSettings() {
    if (widget.settingsService != null) {
      // 重载设置
      widget.settingsService!.reload();
      _hotkeys = widget.settingsService!.getHotkeys();
      _overlayOpacity = widget.settingsService!.getOverlayOpacity();
      _overlaySize = widget.settingsService!.getOverlaySize();
      _closeToTray = widget.settingsService!.getCloseToTray();
      _overlayNavSpeed = widget.settingsService!.getOverlayNavSpeed();
      _mapLineColor = widget.settingsService!.getMapLineColor();
      _mapLineOpacity = widget.settingsService!.getMapLineOpacity();
      _impactAreaOpacity = widget.settingsService!.getImpactAreaOpacity();
      // 同步Provider
      ref.read(impactAreaOpacityProvider.notifier).state = _impactAreaOpacity;

      _markerMoveMode = widget.settingsService!.getMarkerMoveMode();
      _grenadeCreateMode = widget.settingsService!.getGrenadeCreateMode();
      _showMapGrenadeList = widget.settingsService!.getShowMapGrenadeList();
      _highDensityClusterMode =
          widget.settingsService!.getHighDensityClusterMode();
      _joystickOpacity = widget.settingsService!.getJoystickOpacity();
      _joystickSpeed = widget.settingsService!.getJoystickSpeed();
      // 加载路径
      if (_isDesktop) {
        _loadDataPath();
      }
    } else {
      // 默认值
      _hotkeys = {};
      _overlayOpacity = 0.9;
      _overlaySize = 1;
      _closeToTray = true;
      _overlayNavSpeed = 3;
      _mapLineColor = 0xFFE040FB;
      _mapLineOpacity = 0.6;
      _impactAreaOpacity = 0.4;
      _markerMoveMode = 0;
      _grenadeCreateMode = 0;
      _showMapGrenadeList = false;
      _highDensityClusterMode = true;
      _joystickOpacity = 0.8;
      _joystickSpeed = 3;
    }
    // 更新UI
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDataPath() async {
    final effectivePath = await widget.settingsService!.getEffectiveDataPath();
    final defaultPath = await SettingsService.getDefaultDataPath();
    if (mounted) {
      setState(() {
        _currentDataPath = effectivePath;
        _defaultDataPath = defaultPath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _buildSettingsContent(),
    );
  }

  Widget _buildSettingsContent() {
    if (_isDesktop && widget.settingsService == null) {
      return const Center(child: Text('设置服务未初始化'));
    }
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isDesktop) ...[
          _buildDesktopHotkeySection(),
          const SizedBox(height: 16),
          _buildDesktopOverlaySection(),
          const SizedBox(height: 16),
        ],
        _buildGeneralAppearanceSection(themeMode),
        const SizedBox(height: 16),
        _buildMapDisplaySection(),
        const SizedBox(height: 16),
        _buildMarkerOperationSection(),
        if (_isDesktop) ...[
          const SizedBox(height: 16),
          _buildDesktopDataStorageSection(),
        ],
        const SizedBox(height: 16),
        _buildDataManagementSection(),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          _buildLanSyncDebugSection(),
        ],
      ],
    );
  }

  Widget _buildDesktopHotkeySection() {
    return _buildSection(
      title: '🔧 快捷键配置',
      subtitle: '点击可自定义快捷键',
      children: [
        _buildHotkeyTile(HotkeyAction.toggleOverlay, '显示/隐藏悬浮窗'),
        const Divider(height: 1),
        _buildHotkeyTile(HotkeyAction.navigateUp, '向上导航点位'),
        _buildHotkeyTile(HotkeyAction.navigateDown, '向下导航点位'),
        _buildHotkeyTile(HotkeyAction.navigateLeft, '向左导航点位'),
        _buildHotkeyTile(HotkeyAction.navigateRight, '向右导航点位'),
        const Divider(height: 1),
        _buildHotkeyTile(HotkeyAction.prevGrenade, '上一个道具'),
        _buildHotkeyTile(HotkeyAction.nextGrenade, '下一个道具'),
        _buildHotkeyTile(HotkeyAction.prevStep, '上一个步骤'),
        _buildHotkeyTile(HotkeyAction.nextStep, '下一个步骤'),
        const Divider(height: 1),
        _buildHotkeyTile(HotkeyAction.toggleSmoke, '烟雾弹过滤开关'),
        _buildHotkeyTile(HotkeyAction.toggleFlash, '闪光弹过滤开关'),
        _buildHotkeyTile(HotkeyAction.toggleMolotov, '燃烧弹过滤开关'),
        _buildHotkeyTile(HotkeyAction.toggleHE, '手雷过滤开关'),
        _buildHotkeyTile(HotkeyAction.toggleWallbang, '穿点过滤开关'),
        const Divider(height: 1),
        _buildHotkeyTile(HotkeyAction.togglePlayPause, '悬浮窗播放/暂停视频'),
        _buildHotkeyTile(HotkeyAction.toggleMediaFullscreenPreview, '媒体全屏预览'),
        const Divider(height: 1),
        _buildHotkeyTile(HotkeyAction.increaseNavSpeed, '增加导航速度'),
        _buildHotkeyTile(HotkeyAction.decreaseNavSpeed, '减少导航速度'),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: _resetHotkeysToDefault,
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('恢复默认快捷键'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopOverlaySection() {
    return _buildSection(
      title: '🎨 悬浮窗设置',
      children: [
        ListTile(
          title: const Text('透明度'),
          subtitle: Text('${(_overlayOpacity * 100).toInt()}%'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: _overlayOpacity,
              min: 0.3,
              max: 1.0,
              divisions: 14,
              onChanged: (value) async {
                setState(() => _overlayOpacity = value);
                await widget.settingsService!.setOverlayOpacity(value);
                sendOverlayCommand('update_opacity', {'opacity': value});
              },
            ),
          ),
        ),
        ListTile(
          title: const Text('窗口尺寸'),
          subtitle:
              Text(['小 (500×800)', '中 (550×850)', '大 (600×950)'][_overlaySize]),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('小')),
              ButtonSegment(value: 1, label: Text('中')),
              ButtonSegment(value: 2, label: Text('大')),
            ],
            selected: {_overlaySize},
            onSelectionChanged: (value) async {
              final newSize = value.first;
              setState(() => _overlaySize = newSize);
              await widget.settingsService!.setOverlaySize(newSize);
              sendOverlayCommand('update_size', {'sizeIndex': newSize});
            },
          ),
        ),
        ListTile(
          title: const Text('导航速度'),
          subtitle: Text('$_overlayNavSpeed 档'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: _overlayNavSpeed.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_overlayNavSpeed 档',
              onChanged: (value) async {
                final speedLevel = value.round();
                setState(() => _overlayNavSpeed = speedLevel);
                await widget.settingsService!.setOverlayNavSpeed(speedLevel);
                sendOverlayCommand('update_nav_speed', {'speed': speedLevel});
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralAppearanceSection(int themeMode) {
    return _buildSection(
      title: _isDesktop ? '⚙️ 通用设置' : '🎨 外观设置',
      children: [
        ListTile(
          title: const Text('主题模式'),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('自动')),
              ButtonSegment(
                  value: 1, icon: Icon(Icons.light_mode), label: Text('浅色')),
              ButtonSegment(
                  value: 2, icon: Icon(Icons.dark_mode), label: Text('深色')),
            ],
            selected: {themeMode},
            onSelectionChanged: (value) async {
              ref.read(themeModeProvider.notifier).state = value.first;
              if (widget.settingsService != null) {
                await widget.settingsService!.setThemeMode(value.first);
              }
            },
          ),
        ),
        if (SeasonalThemeManager.getActiveTheme() != null)
          _buildSeasonalThemeToggle(),
        if (_isDesktop)
          SwitchListTile(
            title: const Text('关闭按钮最小化到托盘'),
            subtitle: const Text('关闭时隐藏到系统托盘，而非退出程序'),
            value: _closeToTray,
            onChanged: (value) async {
              setState(() => _closeToTray = value);
              await widget.settingsService!.setCloseToTray(value);
            },
          ),
      ],
    );
  }

  Widget _buildMapDisplaySection() {
    return _buildSection(
      title: '🗺️ 地图显示',
      children: [
        ListTile(
          title: const Text('连接线颜色'),
          subtitle: _isDesktop
              ? Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: _buildColorPickerRow(),
                )
              : _buildColorPickerRow(),
        ),
        ListTile(
          title: const Text('连接线透明度'),
          subtitle: Text('${(_mapLineOpacity * 100).toInt()}%'),
          trailing: SizedBox(
            width: _isDesktop ? 200 : 150,
            child: Slider(
              value: _mapLineOpacity,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: (value) async {
                setState(() => _mapLineOpacity = value);
                ref.read(mapLineOpacityProvider.notifier).state = value;
                if (widget.settingsService != null) {
                  await widget.settingsService!.setMapLineOpacity(value);
                }
              },
            ),
          ),
        ),
        if (_isDesktop)
          ListTile(
            title: const Text('爆点区域透明度'),
            subtitle: Text('${(_impactAreaOpacity * 100).toInt()}%'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _impactAreaOpacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                onChanged: (value) async {
                  setState(() => _impactAreaOpacity = value);
                  ref.read(impactAreaOpacityProvider.notifier).state = value;
                  if (widget.settingsService != null) {
                    await widget.settingsService!.setImpactAreaOpacity(value);
                  }
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMarkerOperationSection() {
    return _buildSection(
      title: '📍 标点操作',
      children: [
        ListTile(
          title: const Text('新增方式'),
          subtitle: Text(
            _grenadeCreateMode == 0
                ? '单点地图立即新增道具'
                : (_isDesktop ? '长按地图新增道具（鼠标左键按住）' : '长按地图新增道具'),
          ),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('单点新增')),
              ButtonSegment(value: 1, label: Text('长按新增')),
            ],
            selected: {_grenadeCreateMode},
            onSelectionChanged: (value) async {
              setState(() => _grenadeCreateMode = value.first);
              if (widget.settingsService != null) {
                await widget.settingsService!.setGrenadeCreateMode(value.first);
              }
            },
          ),
        ),
        SwitchListTile(
          title: const Text('地图界面显示道具列表'),
          subtitle: const Text('显示当前地图全部道具列表，便于管理和删除'),
          value: _showMapGrenadeList,
          onChanged: (value) async {
            setState(() => _showMapGrenadeList = value);
            if (widget.settingsService != null) {
              await widget.settingsService!.setShowMapGrenadeList(value);
            }
          },
        ),
        SwitchListTile(
          title: const Text('高密度模式（强聚合）'),
          subtitle: const Text('仅增大地图页聚合范围，帮助大量道具时提升流畅度'),
          value: _highDensityClusterMode,
          onChanged: (value) async {
            setState(() => _highDensityClusterMode = value);
            if (widget.settingsService != null) {
              await widget.settingsService!.setHighDensityClusterMode(value);
            }
          },
        ),
        if (!_isDesktop) ...[
          ListTile(
            title: const Text('移动模式'),
            subtitle: Text(_markerMoveMode == 0 ? '长按选定后点击目标位置' : '长按选定后使用摇杆'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('长按选定')),
                ButtonSegment(value: 1, label: Text('摇杆移动')),
              ],
              selected: {_markerMoveMode},
              onSelectionChanged: (value) async {
                setState(() => _markerMoveMode = value.first);
                if (widget.settingsService != null) {
                  await widget.settingsService!.setMarkerMoveMode(value.first);
                }
              },
            ),
          ),
          if (_markerMoveMode == 1) ...[
            ListTile(
              title: const Text('摇杆透明度'),
              subtitle: Text('${(_joystickOpacity * 100).toInt()}%'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: _joystickOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (value) async {
                    setState(() => _joystickOpacity = value);
                    if (widget.settingsService != null) {
                      await widget.settingsService!.setJoystickOpacity(value);
                    }
                  },
                ),
              ),
            ),
            ListTile(
              title: const Text('移动速度'),
              subtitle: Text('$_joystickSpeed 档'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: _joystickSpeed.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (value) async {
                    setState(() => _joystickSpeed = value.toInt());
                    if (widget.settingsService != null) {
                      await widget.settingsService!
                          .setJoystickSpeed(value.toInt());
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDesktopDataStorageSection() {
    return _buildSection(
      title: '💾 数据存储',
      subtitle: '更改数据目录需要重启应用',
      children: [
        ListTile(
          title: const Text('当前数据目录'),
          subtitle: Text(
            _currentDataPath.isEmpty ? '加载中...' : _currentDataPath,
            style: TextStyle(
              fontSize: 12,
              color: _currentDataPath == _defaultDataPath
                  ? Colors.grey
                  : Colors.orange,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentDataPath != _defaultDataPath &&
                  _currentDataPath.isNotEmpty)
                TextButton.icon(
                  onPressed: _resetToDefaultPath,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('恢复默认'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _changeDataDirectory,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('更改目录'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '更改目录后需要手动重启应用。您可以选择自动将现有数据迁移到新目录。\n\n注意：更改目录后卸载应用需要手动删除更改过后数据目录的所有数据。',
                    style: TextStyle(fontSize: 12, color: Colors.amber[700]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataManagementSection() {
    return _buildSection(
      title: '🗄️ 数据管理',
      children: [
        ListTile(
          leading: const Icon(Icons.playlist_add_check, color: Colors.teal),
          title: const Text('重导入默认区域标签/数据'),
          subtitle: const Text('一键补齐内置默认区域标签与区域几何数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _initializeBuiltinAreaMetadataForAllMaps(),
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
          title: const Text('清空地图道具'),
          subtitle: const Text('删除选定地图的所有道具数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDeleteMapGrenadesDialog(),
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('删除自定义地图'),
          subtitle: const Text('支持多选删除自定义地图及其关联数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDeleteCustomMapsDialog(),
        ),
        ListTile(
          leading: const Icon(Icons.checklist, color: Colors.orange),
          title: const Text('批量选择删除'),
          subtitle: const Text('精确选择要删除的道具，支持预览'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const GrenadeSelectDeleteScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services,
              color: Colors.lightBlueAccent),
          title: const Text('清理孤儿媒体文件'),
          subtitle: const Text('仅扫描常见图片/视频格式，删除未被任何道具引用的文件'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _scanAndCleanupOrphanMediaFiles(),
        ),
      ],
    );
  }

  Widget _buildLanSyncDebugSection() {
    return _buildSection(
      title: '🧪 调试信息',
      subtitle: '仅 Debug 构建显示',
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          title: const Text(
            '局域网同步删除日志',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _isLoadingLanSyncDebug
                ? '正在加载...'
                : '共 ${_lanSyncTombstoneStats.grenadeCount + _lanSyncTombstoneStats.entityCount} 条',
          ),
          trailing: IconButton(
            tooltip: '刷新',
            onPressed: _isLoadingLanSyncDebug ? null : _loadLanSyncDebugInfo,
            icon: const Icon(Icons.refresh),
          ),
        ),
        _buildLanSyncDebugExpandedContent(),
      ],
    );
  }

  Widget _buildLanSyncDebugExpandedContent() {
    if (_isLoadingLanSyncDebug) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('道具删除 ${_lanSyncTombstoneStats.grenadeCount}')),
          Chip(label: Text('其他删除 ${_lanSyncTombstoneStats.entityCount}')),
        ],
      ),
    );
  }

  Future<void> _loadLanSyncDebugInfo() async {
    if (_isLoadingLanSyncDebug) return;
    setState(() => _isLoadingLanSyncDebug = true);
    try {
      final store = LanSyncLocalStore();
      await store.cleanupLegacySyncState();
      await store.cleanupSyncTombstones();
      final stats = await store.loadTombstoneStats();
      if (!mounted) return;
      setState(() {
        _lanSyncTombstoneStats = stats;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingLanSyncDebug = false);
      }
    }
  }

  Future<void> _scanAndCleanupOrphanMediaFiles() async {
    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在扫描孤儿媒体文件...'),
          ],
        ),
      ),
    );

    late final OrphanMediaScanResult scanResult;
    try {
      scanResult = await dataService.scanOrphanMediaFiles();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    if (scanResult.orphanFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现可清理的孤儿媒体文件')),
      );
      return;
    }

    final previewItems = scanResult.orphanFiles.take(8).toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现孤儿媒体文件'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共发现 ${scanResult.orphanFiles.length} 个未被引用的媒体文件，预计可释放 ${_formatBytes(scanResult.totalSizeBytes)}。',
                ),
                const SizedBox(height: 12),
                const Text(
                  '示例文件：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...previewItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${File(item.path).uri.pathSegments.isEmpty ? item.path : File(item.path).uri.pathSegments.last} · ${_formatBytes(item.sizeBytes)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                if (scanResult.orphanFiles.length > previewItems.length)
                  Text(
                    '还有 ${scanResult.orphanFiles.length - previewItems.length} 个文件未展开显示。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在清理孤儿媒体文件...'),
          ],
        ),
      ),
    );

    late final OrphanMediaCleanupResult cleanupResult;
    try {
      cleanupResult =
          await dataService.cleanupOrphanMediaFiles(scanResult.orphanFiles);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清理失败: $e'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    final failedCount = cleanupResult.failedFiles.length;
    final successCount = cleanupResult.deletedFiles.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount == 0
              ? '已清理 $successCount 个孤儿媒体文件，释放 ${_formatBytes(cleanupResult.deletedBytes)}'
              : '已清理 $successCount 个，失败 $failedCount 个，释放 ${_formatBytes(cleanupResult.deletedBytes)}',
        ),
        backgroundColor: failedCount == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  /// 删除地图道具对话框
  Future<void> _showDeleteMapGrenadesDialog() async {
    final isar = ref.read(isarProvider);
    final maps = await isar.gameMaps.where().findAll();
    if (maps.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无地图数据')),
        );
      }
      return;
    }

    // 预加载数据
    final mapGrenadeCount = <int, int>{};
    for (final map in maps) {
      await map.layers.load();
      int count = 0;
      for (final layer in map.layers) {
        await layer.grenades.load();
        count += layer.grenades.length;
      }
      mapGrenadeCount[map.id] = count;
    }

    if (!mounted) return;
    GameMap? selectedMap;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.delete_sweep, color: Colors.redAccent),
              const SizedBox(width: 8),
              const Text('清空地图道具'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择要清空道具的地图：'),
              const SizedBox(height: 16),
              DropdownButtonFormField<GameMap>(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                hint: const Text('选择地图'),
                initialValue: selectedMap,
                items: maps.map((map) {
                  final count = mapGrenadeCount[map.id] ?? 0;
                  return DropdownMenuItem(
                    value: map,
                    child: _SettingsMapDropdownLabel(
                      iconPath: map.iconPath,
                      text: '${map.name} ($count 个道具)',
                    ),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => selectedMap = value),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red[400], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '此操作不可撤销！所有道具及其媒体文件将被永久删除。',
                        style: TextStyle(fontSize: 12, color: Colors.red[400]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selectedMap == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _performDeleteMapGrenades(selectedMap!);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteCustomMapsDialog() async {
    final isar = ref.read(isarProvider);
    final allMaps = await isar.gameMaps.where().findAll();
    final customMaps =
        allMaps.where(MapManagementService.isCustomMap).toList(growable: false);
    if (customMaps.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可删除的自定义地图')),
        );
      }
      return;
    }

    final selectedMapIds = <int>{};
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.map_outlined, color: Colors.red[400]),
              const SizedBox(width: 8),
              const Text('删除自定义地图'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('勾选要删除的自定义地图：'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 280,
                  child: ListView.builder(
                    itemCount: customMaps.length,
                    itemBuilder: (_, index) {
                      final map = customMaps[index];
                      final checked = selectedMapIds.contains(map.id);
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: checked,
                        title: _SettingsMapDropdownLabel(
                          iconPath: map.iconPath,
                          text: map.name,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedMapIds.add(map.id);
                            } else {
                              selectedMapIds.remove(map.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已选择 ${selectedMapIds.length} 张地图',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: selectedMapIds.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final targets = customMaps
                          .where((m) => selectedMapIds.contains(m.id))
                          .toList(growable: false);
                      await _performDeleteCustomMaps(targets);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('删除选中'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeBuiltinAreaMetadataForAllMaps() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重导入默认区域标签/数据？'),
        content: const Text('将为所有地图补齐内置默认区域标签与区域几何数据，不会删除你已有的自定义区域与标签。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('开始导入'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在导入默认区域标签与区域数据...'),
          ],
        ),
      ),
    );

    try {
      final isar = ref.read(isarProvider);
      final tagService = TagService(isar);
      final result = await tagService.initializeBuiltinAreaMetadataForAllMaps();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '已处理${result.processedMaps}张地图；标签预设${result.mapsWithPresets}张、区域预设${result.mapsWithAreaData}张；标签新增${result.addedTags}/更新${result.updatedTags}；区域新增${result.addedAreas}/更新${result.updatedAreas}/去重删除${result.removedDuplicateAreas}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重导入失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 执行删除操作
  Future<void> _performDeleteMapGrenades(GameMap map) async {
    final isar = ref.read(isarProvider);
    final dataService = DataService(isar);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('二次确认'),
        content: Text('确定要删除「${map.name}」地图的所有道具吗？\n\n此操作无法恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在删除...'),
          ],
        ),
      ),
    );

    try {
      final deletedCount = await dataService.deleteAllGrenadesForMap(map);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除「${map.name}」的 $deletedCount 个道具'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _performDeleteCustomMaps(List<GameMap> maps) async {
    if (maps.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('二次确认'),
        content: Text(
          '确定删除选中的 ${maps.length} 张自定义地图吗？\n\n这会删除地图及其所有关联数据，且不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在删除地图...'),
          ],
        ),
      ),
    );

    try {
      final isar = ref.read(isarProvider);
      final deletedCount =
          await MapManagementService(isar).deleteCustomMaps(maps);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 $deletedCount 张自定义地图'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 更改目录
  Future<void> _changeDataDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择数据存储目录',
    );
    if (result == null) return;

    final oldPath = _currentDataPath;
    final newPath = result;

    if (mounted && oldPath != newPath) {
      final shouldMigrate = await _showMigrationDialog();
      if (shouldMigrate == true) {
        // 执行迁移
        await SettingsService.moveData(oldPath, newPath);
      }
    }

    await widget.settingsService!.setCustomDataPath(result);
    setState(() => _currentDataPath = result);

    if (mounted) {
      _showRestartDialog();
    }
  }

  /// 恢复默认
  Future<void> _resetToDefaultPath() async {
    final oldPath = _currentDataPath;
    final newPath = _defaultDataPath;

    if (mounted && oldPath != newPath) {
      final shouldMigrate = await _showMigrationDialog();
      if (shouldMigrate == true) {
        // 执行迁移
        await SettingsService.moveData(oldPath, newPath);
      }
    }

    await widget.settingsService!.setCustomDataPath(null);
    setState(() => _currentDataPath = _defaultDataPath);

    if (mounted) {
      _showRestartDialog();
    }
  }

  /// 迁移对话框
  Future<bool?> _showMigrationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('迁移现有数据？'),
        content: const Text('检测到您更改了数据目录。是否将当前目录下的所有数据（数据库、设置、存档等）自动拷贝到新目录下？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('跳过'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('立即迁移'),
          ),
        ],
      ),
    );
  }

  /// 重启提示
  void _showRestartDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.restart_alt, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('需要重启'),
          ],
        ),
        content: const Text('数据目录已更改，请手动重启应用以使更改生效。'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 重置快捷键
  Future<void> _resetHotkeysToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认快捷键？'),
        content: const Text('这将重置所有快捷键为默认配置，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.settingsService != null) {
      await widget.settingsService!.resetHotkeys();
      setState(() {
        _hotkeys = widget.settingsService!.getHotkeys();
      });
      await widget.onHotkeysReset?.call();

      // 通知重载热键
      final hotkeysJson = <String, dynamic>{};
      for (final entry in _hotkeys.entries) {
        hotkeysJson[entry.key.name] = entry.value.toJson();
      }
      sendOverlayCommand('reload_hotkeys', {'hotkeys': hotkeysJson});
      debugPrint('[Settings] Hotkeys reset, notified overlay to reload');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('快捷键已恢复默认')),
        );
      }
    }
  }

  /// 节日开关组件
  Widget _buildSeasonalThemeToggle() {
    final seasonalTheme = SeasonalThemeManager.getActiveTheme();
    if (seasonalTheme == null) return const SizedBox.shrink();

    final enabled = ref.watch(seasonalThemeEnabledProvider);

    return SwitchListTile(
      title: Row(
        children: [
          Text(seasonalTheme.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text('${seasonalTheme.name}主题'),
        ],
      ),
      subtitle: Text(enabled ? '享受节日氛围吧！' : '已关闭节日装饰'),
      value: enabled,
      onChanged: (value) async {
        ref.read(seasonalThemeEnabledProvider.notifier).state = value;
        if (widget.settingsService != null) {
          await widget.settingsService!.setSeasonalThemeEnabled(value);
        }
      },
      activeThumbColor: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    var unitIndex = -1;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final fractionDigits = size >= 100 ? 0 : 1;
    return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  Widget _buildHotkeyTile(HotkeyAction action, String label) {
    final config = _hotkeys[action];
    final displayStr = config?.toDisplayString() ?? '未设置';

    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: Text(
              displayStr,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _showHotkeyEditor(action, label),
          ),
        ],
      ),
    );
  }

  void _showHotkeyEditor(HotkeyAction action, String label) {
    showDialog(
      context: context,
      builder: (context) => _HotkeyEditorDialog(
        action: action,
        label: label,
        currentConfig: _hotkeys[action],
        onSave: (newConfig) async {
          final conflictAction = _findConflictingAction(action, newConfig);
          if (conflictAction != null) {
            final conflictLabel = _hotkeyLabel(conflictAction);
            final conflictConfig = _hotkeys[conflictAction];
            final display = conflictConfig?.toDisplayString() ?? '';
            return display.isNotEmpty
                ? '与“$conflictLabel”（$display）冲突，请更换按键'
                : '与“$conflictLabel”冲突，请更换按键';
          }

          try {
            await widget.settingsService!.saveHotkey(action, newConfig);
            final hotkeys = widget.settingsService!.getHotkeys();

            if (mounted) {
              setState(() => _hotkeys = hotkeys);
            } else {
              _hotkeys = hotkeys;
            }

            if (widget.onHotkeyChanged != null) {
              await widget.onHotkeyChanged!(action, newConfig);
            }

            final hotkeysJson = <String, dynamic>{};
            for (final entry in hotkeys.entries) {
              hotkeysJson[entry.key.name] = entry.value.toJson();
            }
            sendOverlayCommand('reload_hotkeys', {'hotkeys': hotkeysJson});
            debugPrint('[Settings] Hotkey changed, notified overlay to reload');
            return null;
          } on HotkeyConflictException catch (e) {
            return '与“${_hotkeyLabel(e.conflictingAction)}”冲突，请更换按键';
          } catch (e) {
            debugPrint('[Settings] Failed to save hotkey: $e');
            return '保存失败，请重试';
          }
        },
      ),
    );
  }

  HotkeyAction? _findConflictingAction(
    HotkeyAction currentAction,
    HotkeyConfig newConfig,
  ) {
    for (final entry in _hotkeys.entries) {
      if (entry.key == currentAction) continue;
      if (entry.value.conflictsWith(newConfig)) {
        return entry.key;
      }
    }
    return null;
  }

  String _hotkeyLabel(HotkeyAction action) {
    return _hotkeyActionLabels[action] ?? action.name;
  }

  Widget _buildColorPickerRow() {
    final colors = [
      0xFFE040FB, // PurpleAccent (Default)
      0xFF448AFF, // BlueAccent
      0xFF18FFFF, // CyanAccent
      0xFF69F0AE, // GreenAccent
      0xFFFFAB40, // OrangeAccent
      0xFFFF5252, // RedAccent
      0xFFFFFFFF, // White
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: colors.map((colorValue) {
        final isSelected = _mapLineColor == colorValue;
        return GestureDetector(
          onTap: () async {
            setState(() => _mapLineColor = colorValue);
            ref.read(mapLineColorProvider.notifier).state = colorValue;
            if (widget.settingsService != null) {
              await widget.settingsService!.setMapLineColor(colorValue);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(colorValue),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Color(colorValue).withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.black54)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _SettingsMapDropdownLabel extends StatelessWidget {
  final String iconPath;
  final String text;

  const _SettingsMapDropdownLabel({
    required this.iconPath,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MapIcon(path: iconPath, size: 20),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 快捷键编辑对话框
class _HotkeyEditorDialog extends StatefulWidget {
  final HotkeyAction action;
  final String label;
  final HotkeyConfig? currentConfig;
  final Future<String?> Function(HotkeyConfig) onSave;

  const _HotkeyEditorDialog({
    required this.action,
    required this.label,
    required this.currentConfig,
    required this.onSave,
  });

  @override
  State<_HotkeyEditorDialog> createState() => _HotkeyEditorDialogState();
}

class _HotkeyEditorDialogState extends State<_HotkeyEditorDialog> {
  HotkeyConfig? _newConfig;
  final FocusNode _focusNode = FocusNode();
  bool _isListening = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _newConfig = widget.currentConfig;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('设置快捷键: ${widget.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '当前: ${widget.currentConfig?.toDisplayString() ?? "未设置"}',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is KeyDownEvent && _isListening) {
                // 过滤掉单独的修饰键
                if (_isModifierKey(event.logicalKey)) return;

                final modifiers = <LogicalKeyboardKey>{};
                if (HardwareKeyboard.instance.isAltPressed) {
                  modifiers.add(LogicalKeyboardKey.alt);
                }
                if (HardwareKeyboard.instance.isControlPressed) {
                  modifiers.add(LogicalKeyboardKey.control);
                }
                if (HardwareKeyboard.instance.isShiftPressed) {
                  modifiers.add(LogicalKeyboardKey.shift);
                }

                setState(() {
                  _newConfig = HotkeyConfig(
                    key: event.logicalKey,
                    modifiers: modifiers,
                  );
                  _isListening = false;
                  _errorText = null;
                });
              }
            },
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isListening = true;
                  _errorText = null;
                });
                _focusNode.requestFocus();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isListening
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isListening ? Icons.keyboard : Icons.touch_app,
                      size: 40,
                      color: _isListening
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isListening
                          ? '请按下新的快捷键组合...'
                          : _newConfig?.toDisplayString() ?? '点击此处开始设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isListening
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _newConfig != null && !_isSaving
              ? () async {
                  setState(() {
                    _isSaving = true;
                    _errorText = null;
                  });

                  final error = await widget.onSave(_newConfig!);
                  if (!mounted || !context.mounted) return;

                  if (error == null) {
                    Navigator.pop(context);
                    return;
                  }

                  setState(() {
                    _isSaving = false;
                    _errorText = error;
                  });
                }
              : null,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

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
}
