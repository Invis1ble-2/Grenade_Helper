import 'package:flutter/material.dart';

/// 预设颜色列表
const List<int> presetColors = [
  0xFFE91E63, // Pink
  0xFFF44336, // Red
  0xFFFF9800, // Orange
  0xFFFFEB3B, // Yellow
  0xFF4CAF50, // Green
  0xFF00BCD4, // Cyan
  0xFF2196F3, // Blue
  0xFF3F51B5, // Indigo
  0xFF9C27B0, // Purple
  0xFF795548, // Brown
  0xFF607D8B, // BlueGrey
  0xFF9E9E9E, // Grey
];

/// 标签颜色选择器
class TagColorPicker extends StatefulWidget {
  final int initialColor;
  final ValueChanged<int> onColorSelected;
  final bool showPreview;

  const TagColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
    this.showPreview = true,
  });

  @override
  State<TagColorPicker> createState() => _TagColorPickerState();
}

class _TagColorPickerState extends State<TagColorPicker> {
  late int _selectedColor;
  late double _hue;
  late double _saturation;
  late double _lightness;
  bool _showHSLPicker = false;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _initHSL();
  }

  void _initHSL() {
    final color = Color(_selectedColor);
    final hslColor = HSLColor.fromColor(color);
    _hue = hslColor.hue;
    _saturation = hslColor.saturation;
    _lightness = hslColor.lightness;
  }

  void _updateColorFromHSL() {
    final hslColor = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness);
    setState(() {
      _selectedColor = hslColor.toColor().value;
    });
    widget.onColorSelected(_selectedColor);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showPreview) ...[
          _buildColorPreview(),
          const SizedBox(height: 12),
        ],
        _buildPresetColors(),
        const SizedBox(height: 12),
        _buildToggleButton(),
        if (_showHSLPicker) ...[
          const SizedBox(height: 12),
          _buildHSLSliders(),
        ],
      ],
    );
  }

  Widget _buildColorPreview() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Color(_selectedColor),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: [
              BoxShadow(
                color: Color(_selectedColor).withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前颜色', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              '#${_selectedColor.toRadixString(16).substring(2).toUpperCase()}',
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetColors() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presetColors.map((color) {
        final isSelected = color == _selectedColor;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedColor = color;
              _initHSL();
            });
            widget.onColorSelected(color);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color(color),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Color(color).withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: () => setState(() => _showHSLPicker = !_showHSLPicker),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showHSLPicker ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 18,
            color: Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            _showHSLPicker ? '收起自定义' : '自定义颜色',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHSLSliders() {
    return Column(
      children: [
        _buildSlider('色相', _hue, 0, 360, (val) {
          setState(() => _hue = val);
          _updateColorFromHSL();
        }, _buildHueGradient()),
        const SizedBox(height: 8),
        _buildSlider('饱和度', _saturation, 0, 1, (val) {
          setState(() => _saturation = val);
          _updateColorFromHSL();
        }, _buildSaturationGradient()),
        const SizedBox(height: 8),
        _buildSlider('亮度', _lightness, 0, 1, (val) {
          setState(() => _lightness = val);
          _updateColorFromHSL();
        }, _buildLightnessGradient()),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, Gradient gradient) {
    return Row(
      children: [
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 24,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackShape: const RoundedRectSliderTrackShape(),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  LinearGradient _buildHueGradient() {
    return LinearGradient(
      colors: List.generate(7, (i) => HSLColor.fromAHSL(1, i * 60.0, _saturation, _lightness).toColor()),
    );
  }

  LinearGradient _buildSaturationGradient() {
    return LinearGradient(
      colors: [
        HSLColor.fromAHSL(1, _hue, 0, _lightness).toColor(),
        HSLColor.fromAHSL(1, _hue, 1, _lightness).toColor(),
      ],
    );
  }

  LinearGradient _buildLightnessGradient() {
    return LinearGradient(
      colors: [
        HSLColor.fromAHSL(1, _hue, _saturation, 0).toColor(),
        HSLColor.fromAHSL(1, _hue, _saturation, 0.5).toColor(),
        HSLColor.fromAHSL(1, _hue, _saturation, 1).toColor(),
      ],
    );
  }
}

/// 显示颜色选择器对话框
Future<int?> showTagColorPickerDialog(BuildContext context, {int? initialColor}) async {
  int selectedColor = initialColor ?? presetColors.first;
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('选择颜色'),
      content: TagColorPicker(
        initialColor: selectedColor,
        onColorSelected: (color) => selectedColor = color,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(onPressed: () => Navigator.pop(context, selectedColor), child: const Text('确定')),
      ],
    ),
  );
}
