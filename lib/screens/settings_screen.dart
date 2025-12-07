import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

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
  late int _overlaySize;
  late bool _closeToTray;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    if (widget.settingsService != null) {
      _hotkeys = widget.settingsService!.getHotkeys();
      _overlayOpacity = widget.settingsService!.getOverlayOpacity();
      _overlaySize = widget.settingsService!.getOverlaySize();
      _closeToTray = widget.settingsService!.getCloseToTray();
    } else {
      // 默认值
      _hotkeys = {};
      _overlayOpacity = 0.9;
      _overlaySize = 1;
      _closeToTray = true;
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.desktop_windows,
              size: 80,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 24),
            Text(
              '桌面端专属功能',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '快捷键配置、悬浮窗等功能仅在\nWindows / macOS / Linux 上可用',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
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
                  },
                ),
              ),
            ),
            ListTile(
              title: const Text('尺寸'),
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('小')),
                  ButtonSegment(value: 1, label: Text('中')),
                  ButtonSegment(value: 2, label: Text('大')),
                ],
                selected: {_overlaySize},
                onSelectionChanged: (value) async {
                  setState(() => _overlaySize = value.first);
                  await widget.settingsService!.setOverlaySize(value.first);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: '⚙️ 通用设置',
          children: [
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
      ],
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
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isListening ? Colors.orange : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isListening ? Icons.keyboard : Icons.touch_app,
                      size: 40,
                      color: _isListening ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isListening
                          ? '请按下新的快捷键组合...'
                          : _newConfig?.toDisplayString() ?? '点击此处开始设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isListening ? Colors.orange : null,
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
