import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../services/area_service.dart';
import '../widgets/color_picker_widget.dart';

/// 区域绘制界面
class AreaDrawScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  final MapLayer layer;
  
  const AreaDrawScreen({super.key, required this.gameMap, required this.layer});
  
  @override
  ConsumerState<AreaDrawScreen> createState() => _AreaDrawScreenState();
}

class _AreaDrawScreenState extends ConsumerState<AreaDrawScreen> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  final _nameController = TextEditingController();
  int _selectedColor = 0xFF4CAF50;
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
  
  void _onPanStart(DragStartDetails details, Size imageSize) {
    final localPos = details.localPosition;
    final ratio = Offset(localPos.dx / imageSize.width, localPos.dy / imageSize.height);
    setState(() {
      _currentStroke = [ratio];
    });
  }
  
  void _onPanUpdate(DragUpdateDetails details, Size imageSize) {
    final localPos = details.localPosition;
    final ratio = Offset(
      (localPos.dx / imageSize.width).clamp(0.0, 1.0),
      (localPos.dy / imageSize.height).clamp(0.0, 1.0),
    );
    setState(() {
      _currentStroke.add(ratio);
    });
  }
  
  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.length > 2) {
      setState(() {
        _strokes.add(List.from(_currentStroke));
        _currentStroke = [];
      });
    }
  }
  
  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    }
  }
  
  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }
  
  String _strokesAsJson() {
    final data = _strokes.map((stroke) => 
      stroke.map((p) => {'x': p.dx, 'y': p.dy}).toList()
    ).toList();
    return jsonEncode(data);
  }
  
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入区域名称'), backgroundColor: Colors.orange)
      );
      return;
    }
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请绘制区域范围'), backgroundColor: Colors.orange)
      );
      return;
    }
    
    final isar = ref.read(isarProvider);
    final areaService = AreaService(isar);
    
    await areaService.createArea(
      name: name,
      colorValue: _selectedColor,
      strokes: _strokesAsJson(),
      mapId: widget.gameMap.id,
      layerId: widget.layer.id,
    );
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('区域 "$name" 创建成功'), backgroundColor: Colors.green)
    );
    Navigator.pop(context, true);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D21),
      appBar: AppBar(
        title: Text('绘制区域 - ${widget.layer.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _strokes.isEmpty ? null : _undo, tooltip: '撤销'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _strokes.isEmpty ? null : _clear, tooltip: '清除'),
        ],
      ),
      body: Column(
        children: [
          // 输入区域名称和颜色
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF2A2D33),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '区域名称',
                      hintText: '如: A大, 中路...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () async {
                    final color = await showTagColorPickerDialog(context, initialColor: _selectedColor);
                    if (color != null) setState(() => _selectedColor = color);
                  },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Color(_selectedColor),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.palette, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // 地图绘制区域
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return GestureDetector(
                onPanStart: (d) => _onPanStart(d, constraints.biggest),
                onPanUpdate: (d) => _onPanUpdate(d, constraints.biggest),
                onPanEnd: _onPanEnd,
                child: Stack(
                  children: [
                    // 地图底图
                    Image.asset(
                      widget.layer.assetPath,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.contain,
                    ),
                    // 已绘制笔画
                    CustomPaint(
                      size: constraints.biggest,
                      painter: _StrokePainter(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                        color: Color(_selectedColor),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          // 提示和保存按钮
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF2A2D33),
            child: Row(
              children: [
                const Expanded(
                  child: Text('用手指或鼠标绘制区域边界', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('保存区域'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 笔画绘制器
class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color color;
  
  _StrokePainter({required this.strokes, required this.currentStroke, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    
    // 绘制已完成的笔画
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      final first = Offset(stroke.first.dx * size.width, stroke.first.dy * size.height);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < stroke.length; i++) {
        final p = Offset(stroke[i].dx * size.width, stroke[i].dy * size.height);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, paint);
    }
    
    // 绘制当前笔画
    if (currentStroke.length >= 2) {
      final path = Path();
      final first = Offset(currentStroke.first.dx * size.width, currentStroke.first.dy * size.height);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < currentStroke.length; i++) {
        final p = Offset(currentStroke[i].dx * size.width, currentStroke[i].dy * size.height);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint..color = color);
    }
  }
  
  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
