import 'dart:async';
import 'package:flutter/material.dart';

/// 底部弹出式摇杆组件
/// 用于在编辑模式下控制标点移动
class JoystickBottomSheet extends StatefulWidget {
  /// 摇杆透明度 (0.1-1.0)
  final double opacity;

  /// 移动速度档位 (1-5)
  final int speedLevel;

  /// 方向回调，返回标准化方向向量 (x: -1到1, y: -1到1)
  final Function(Offset direction) onMove;

  /// 确认移动回调
  final VoidCallback onConfirm;

  /// 取消移动回调
  final VoidCallback onCancel;

  /// 标点名称（用于显示）
  final String? clusterName;

  const JoystickBottomSheet({
    super.key,
    required this.opacity,
    required this.speedLevel,
    required this.onMove,
    required this.onConfirm,
    required this.onCancel,
    this.clusterName,
  });

  @override
  State<JoystickBottomSheet> createState() => _JoystickBottomSheetState();
}

class _JoystickBottomSheetState extends State<JoystickBottomSheet> {
  Offset _knobPosition = Offset.zero;
  bool _isDragging = false;
  Timer? _moveTimer;

  // 摇杆尺寸
  static const double _baseRadius = 60.0;
  static const double _knobRadius = 25.0;

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    // 使用 16ms (约60fps) 的定时器触发移动
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_knobPosition == Offset.zero) return;

      final maxDistance = _baseRadius - _knobRadius;
      // 计算标准化方向向量 (-1 到 1)
      final normalizedDirection = Offset(
        _knobPosition.dx / maxDistance,
        _knobPosition.dy / maxDistance,
      );

      // 只有在有明显移动时才触发回调
      if (normalizedDirection.distance > 0.1) {
        // 调用回调，因为是高频调用，外层处理时可能需要考虑性能，
        // 但在这里我们直接传出方向，由 map_screen 决定怎么根据 step 移动
        widget.onMove(normalizedDirection);
      }
    });
  }

  void _stopTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2126).withValues(alpha: widget.opacity),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gamepad,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20),
                      const SizedBox(width: 8),
                      Text(
                        widget.clusterName != null
                            ? '移动: ${widget.clusterName}'
                            : '摇杆移动',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '速度: ${widget.speedLevel}档',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 摇杆区域
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 摇杆
                  GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: Container(
                      width: _baseRadius * 2,
                      height: _baseRadius * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.3),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.1),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 方向指示线
                          ..._buildDirectionLines(),
                          // 中心点
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[600],
                            ),
                          ),
                          // 摇杆把手
                          Transform.translate(
                            offset: _knobPosition,
                            child: Container(
                              width: _knobRadius * 2,
                              height: _knobRadius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[700], // 纯灰色
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.control_camera,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '按住拖动持续移动',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 20),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Colors.grey.withValues(alpha: widget.opacity),
                        side: BorderSide(
                          color: Colors.grey[600]!
                              .withValues(alpha: widget.opacity),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: widget.opacity),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: widget.opacity),
                        foregroundColor:
                            Colors.white.withValues(alpha: widget.opacity),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        '确认',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: widget.opacity),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDirectionLines() {
    return [
      // 上
      Positioned(
        top: 8,
        child: Icon(Icons.arrow_drop_up, color: Colors.grey[700], size: 20),
      ),
      // 下
      Positioned(
        bottom: 8,
        child: Icon(Icons.arrow_drop_down, color: Colors.grey[700], size: 20),
      ),
      // 左
      Positioned(
        left: 8,
        child: Icon(Icons.arrow_left, color: Colors.grey[700], size: 20),
      ),
      // 右
      Positioned(
        right: 8,
        child: Icon(Icons.arrow_right, color: Colors.grey[700], size: 20),
      ),
    ];
  }

  void _onPanStart(DragStartDetails details) {
    setState(() => _isDragging = true);
    _startTimer(); // 开始持续移动
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final newPosition = _knobPosition + details.delta;
    final distance = newPosition.distance;
    final maxDistance = _baseRadius - _knobRadius;

    setState(() {
      if (distance <= maxDistance) {
        _knobPosition = newPosition;
      } else {
        // 限制在圆形范围内
        _knobPosition = Offset.fromDirection(
          newPosition.direction,
          maxDistance,
        );
      }
    });
    // 注意：不再在 onPanUpdate 中直接调用 onMove，而是由定时器调用
  }

  void _onPanEnd(DragEndDetails details) {
    _stopTimer(); // 停止移动
    setState(() {
      _isDragging = false;
      _knobPosition = Offset.zero;
    });
  }
}

/// 显示摇杆底部弹窗
Future<void> showJoystickBottomSheet({
  required BuildContext context,
  required double opacity,
  required int speedLevel,
  required Function(Offset direction) onMove,
  required VoidCallback onConfirm,
  required VoidCallback onCancel,
  String? clusterName,
  Color barrierColor = Colors.black54, // 添加 barrierColor 参数，默认还是半透明
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => JoystickBottomSheet(
      opacity: opacity,
      speedLevel: speedLevel,
      onMove: onMove,
      onConfirm: () {
        Navigator.pop(ctx);
        onConfirm();
      },
      onCancel: () {
        Navigator.pop(ctx);
        onCancel();
      },
      clusterName: clusterName,
    ),
  );
}
