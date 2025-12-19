import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../services/settings_service.dart';
import '../providers.dart';
import '../main.dart' show sendOverlayCommand;

/// 设置页面
class SettingsScreen extends ConsumerStatefulWidget {
  final SettingsService? settingsService;
  final void Function(HotkeyAction, HotkeyConfig)? onHotkeyChanged;

  const SettingsScreen({
    super.key,
    this.settingsService,
    this.onHotkeyChanged,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Map<HotkeyAction, HotkeyConfig> _hotkeys;
  late double _overlayOpacity;
  late bool _closeToTray;
  late int _overlayNavSpeed; // 悬浮窗导航速度 (1-5)
  // 摇杆相关设置（仅移动端）
  late int _markerMoveMode;
  late double _joystickOpacity;
  late int _joystickSpeed;
  // 数据存储路径（仅桌面端）
  String _currentDataPath = '';
  String _defaultDataPath = '';

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
    // 每次设置界面重新激活时重新加载设置，确保显示最新值
    _loadSettings();
  }

  void _loadSettings() {
    if (widget.settingsService != null) {
      // 重新从设置服务加载，确保获取最新值
      widget.settingsService!.reload();
      _hotkeys = widget.settingsService!.getHotkeys();
      _overlayOpacity = widget.settingsService!.getOverlayOpacity();
      _closeToTray = widget.settingsService!.getCloseToTray();
      _overlayNavSpeed = widget.settingsService!.getOverlayNavSpeed();
      _markerMoveMode = widget.settingsService!.getMarkerMoveMode();
      _joystickOpacity = widget.settingsService!.getJoystickOpacity();
      _joystickSpeed = widget.settingsService!.getJoystickSpeed();
      // 加载数据路径（异步）
      if (_isDesktop) {
        _loadDataPath();
      }
    } else {
      // 默认值
      _hotkeys = {};
      _overlayOpacity = 0.9;
      _closeToTray = true;
      _overlayNavSpeed = 3;
      _markerMoveMode = 0;
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
      body: _isDesktop ? _buildDesktopSettings() : _buildMobileSettings(),
    );
  }

  Widget _buildMobileSettings() {
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSection(
          title: '🎨 外观设置',
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
                      value: 1,
                      icon: Icon(Icons.light_mode),
                      label: Text('浅色')),
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
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: '📍 标点操作',
          children: [
            ListTile(
              title: const Text('移动模式'),
              subtitle:
                  Text(_markerMoveMode == 0 ? '长按选定后点击目标位置' : '长按选定后使用摇杆'),
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('长按选定')),
                  ButtonSegment(value: 1, label: Text('摇杆移动')),
                ],
                selected: {_markerMoveMode},
                onSelectionChanged: (value) async {
                  setState(() => _markerMoveMode = value.first);
                  if (widget.settingsService != null) {
                    await widget.settingsService!
                        .setMarkerMoveMode(value.first);
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
        ),
      ],
    );
  }

  Widget _buildDesktopSettings() {
    if (widget.settingsService == null) {
      return const Center(child: Text('设置服务未初始化'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSection(
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
            const Divider(height: 1),
            _buildHotkeyTile(HotkeyAction.increaseNavSpeed, '增加导航速度'),
            _buildHotkeyTile(HotkeyAction.decreaseNavSpeed, '减少导航速度'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
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
                    // 通知悬浮窗刷新透明度（直接传递值）
                    sendOverlayCommand('update_opacity', {'opacity': value});
                  },
                ),
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
                    // 使用 round() 避免浮点精度问题（如 0.999... -> 1）
                    final speedLevel = value.round();
                    setState(() => _overlayNavSpeed = speedLevel);
                    await widget.settingsService!
                        .setOverlayNavSpeed(speedLevel);
                    // 通知悬浮窗刷新导航速度
                    sendOverlayCommand(
                        'update_nav_speed', {'speed': speedLevel});
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: '⚙️ 通用设置',
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
                      value: 1,
                      icon: Icon(Icons.light_mode),
                      label: Text('浅色')),
                  ButtonSegment(
                      value: 2, icon: Icon(Icons.dark_mode), label: Text('深色')),
                ],
                selected: {ref.watch(themeModeProvider)},
                onSelectionChanged: (value) async {
                  ref.read(themeModeProvider.notifier).state = value.first;
                  await widget.settingsService!.setThemeMode(value.first);
                },
              ),
            ),
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
        ),
        const SizedBox(height: 16),
        _buildSection(
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
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.amber[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '更改目录后需要手动重启应用。现有数据不会自动迁移，请手动复制数据文件到新目录。',
                        style:
                            TextStyle(fontSize: 12, color: Colors.amber[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 更改数据目录
  Future<void> _changeDataDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择数据存储目录',
    );
    if (result == null) return;

    await widget.settingsService!.setCustomDataPath(result);
    setState(() => _currentDataPath = result);

    if (mounted) {
      _showRestartDialog();
    }
  }

  /// 恢复默认路径
  Future<void> _resetToDefaultPath() async {
    await widget.settingsService!.setCustomDataPath(null);
    setState(() => _currentDataPath = _defaultDataPath);

    if (mounted) {
      _showRestartDialog();
    }
  }

  /// 显示重启提示对话框
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
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
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
          setState(() => _hotkeys[action] = newConfig);
          await widget.settingsService!.saveHotkey(action, newConfig);
          widget.onHotkeyChanged?.call(action, newConfig);

          // 通知悬浮窗重新加载热键配置，传递完整的热键配置
          final hotkeys = widget.settingsService!.getHotkeys();
          final hotkeysJson = <String, dynamic>{};
          for (final entry in hotkeys.entries) {
            hotkeysJson[entry.key.name] = entry.value.toJson();
          }
          sendOverlayCommand('reload_hotkeys', {'hotkeys': hotkeysJson});
          print('[Settings] Hotkey changed, notified overlay to reload');
        },
      ),
    );
  }
}

/// 快捷键编辑对话框
class _HotkeyEditorDialog extends StatefulWidget {
  final HotkeyAction action;
  final String label;
  final HotkeyConfig? currentConfig;
  final void Function(HotkeyConfig) onSave;

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
                });
              }
            },
            child: GestureDetector(
              onTap: () {
                setState(() => _isListening = true);
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _newConfig != null
              ? () {
                  widget.onSave(_newConfig!);
                  Navigator.pop(context);
                }
              : null,
          child: const Text('保存'),
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
