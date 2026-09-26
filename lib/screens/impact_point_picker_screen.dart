import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/path_image_provider.dart';

/// 爆点坐标选择/查看页面
class ImpactPointPickerScreen extends ConsumerStatefulWidget {
  final int grenadeId;
  final double? initialX;
  final double? initialY;
  final double throwX;
  final double throwY;
  final int layerId;
  final String? existingStrokes;
  final int grenadeType;
  final bool readOnly;

  const ImpactPointPickerScreen({
    super.key,
    required this.grenadeId,
    this.initialX,
    this.initialY,
    required this.throwX,
    required this.throwY,
    required this.layerId,
    this.existingStrokes,
    this.grenadeType = GrenadeType.smoke,
    this.readOnly = false,
  });

  @override
  ConsumerState<ImpactPointPickerScreen> createState() =>
      _ImpactPointPickerScreenState();
}

class _ImpactPointPickerScreenState
    extends ConsumerState<ImpactPointPickerScreen> {
  late final PhotoViewController _photoViewController;
  final GlobalKey _stackKey = GlobalKey();

  double? _selectedX;
  double? _selectedY;
  MapLayer? _layer;
  List<Map<String, dynamic>> _drawingStrokes = [];

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    _selectedX = widget.initialX;
    _selectedY = widget.initialY;
    _loadLayer();

    if (widget.readOnly && widget.existingStrokes != null) {
      try {
        final parsed = jsonDecode(widget.existingStrokes!) as List;
        _drawingStrokes =
            parsed.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  Future<void> _loadLayer() async {
    final isar = ref.read(isarProvider);
    _layer = await isar.mapLayers.get(widget.layerId);
    if (mounted) setState(() {});
  }

  ({double width, double height, double offsetX, double offsetY})
      _getImageBounds(double containerWidth, double containerHeight) {
    const double imageAspectRatio = 1.0;
    final double containerAspectRatio = containerWidth / containerHeight;

    if (containerAspectRatio > imageAspectRatio) {
      final imageHeight = containerHeight;
      final imageWidth = containerHeight * imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: (containerWidth - imageWidth) / 2,
        offsetY: 0.0,
      );
    } else {
      final imageWidth = containerWidth;
      final imageHeight = containerWidth / imageAspectRatio;
      return (
        width: imageWidth,
        height: imageHeight,
        offsetX: 0.0,
        offsetY: (containerHeight - imageHeight) / 2,
      );
    }
  }

  Offset? _getLocalPosition(Offset globalPosition) {
    final RenderBox? box =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final localPosition = box.globalToLocal(globalPosition);
    final size = box.size;
    final bounds = _getImageBounds(size.width, size.height);

    final tapX = localPosition.dx - bounds.offsetX;
    final tapY = localPosition.dy - bounds.offsetY;

    return Offset(tapX / bounds.width, tapY / bounds.height);
  }

  void _handleTap(TapUpDetails details) {
    final localRatio = _getLocalPosition(details.globalPosition);
    if (localRatio == null) return;

    if (localRatio.dx < 0 ||
        localRatio.dx > 1 ||
        localRatio.dy < 0 ||
        localRatio.dy > 1) {
      return;
    }

    setState(() {
      _selectedX = localRatio.dx;
      _selectedY = localRatio.dy;
    });
  }

  void _confirmSelection() {
    if (_selectedX != null && _selectedY != null) {
      Navigator.pop(context, Offset(_selectedX!, _selectedY!));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击地图选择爆点位置')),
      );
    }
  }

  void _handleMouseWheelZoom(
      PointerScrollEvent event, BoxConstraints constraints) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    final double zoomFactor = scrollDelta > 0 ? 0.9 : 1.1;
    final double currentScale = _photoViewController.scale ?? 1.0;
    final Offset currentPosition = _photoViewController.position;

    const minScale = 0.8;
    const maxScale = 5.0;
    final double newScale =
        (currentScale * zoomFactor).clamp(minScale, maxScale);

    if ((newScale - currentScale).abs() < 0.0001) return;

    final Size size = renderBox.size;
    final Offset viewportCenter = size.center(Offset.zero);
    final Offset cursorPosition = event.localPosition - viewportCenter;

    final double scaleRatio = newScale / currentScale;
    final Offset newPosition =
        cursorPosition * (1 - scaleRatio) + currentPosition * scaleRatio;

    _photoViewController.scale = newScale;
    _photoViewController.position = newPosition;
  }

  Color _getTypeColor() {
    switch (widget.grenadeType) {
      case GrenadeType.molotov:
        return Colors.orange;
      case GrenadeType.smoke:
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_layer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.readOnly ? '查看爆点位置' : '选择爆点位置'),
        centerTitle: true,
        actions: [
          if (!widget.readOnly)
            TextButton(
              onPressed: _confirmSelection,
              child: Text(
                '确认',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imageBounds = _getImageBounds(
                      constraints.maxWidth, constraints.maxHeight);

                  return Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _handleMouseWheelZoom(event, constraints);
                      }
                    },
                    child: PhotoView.customChild(
                      controller: _photoViewController,
                      backgroundDecoration:
                          const BoxDecoration(color: Colors.black),
                      minScale: PhotoViewComputedScale.contained * 0.8,
                      maxScale: PhotoViewComputedScale.covered * 3,
                      initialScale: PhotoViewComputedScale.contained,
                      child: StreamBuilder<PhotoViewControllerValue>(
                        stream: _photoViewController.outputStateStream,
                        builder: (context, snapshot) {
                          final double scale = snapshot.data?.scale ?? 1.0;
                          final double markerScale = 1.0 / scale;

                          return Stack(
                            key: _stackKey,
                            children: [
                              GestureDetector(
                                onTapUp: widget.readOnly ? null : _handleTap,
                                child: Builder(builder: (context) {
                                  final provider =
                                      imageProviderFromPath(_layer!.assetPath);
                                  if (provider == null) {
                                    return Container(
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      color: Colors.black,
                                    );
                                  }
                                  return Image(
                                    image: provider,
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                    fit: BoxFit.contain,
                                  );
                                }),
                              ),
                              ..._buildPickerLayers(imageBounds, markerScale),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (!widget.readOnly) _buildPickerFooter(),
        ],
      ),
    );
  }

  List<Widget> _buildPickerLayers(
    ({double width, double height, double offsetX, double offsetY}) imageBounds,
    double markerScale,
  ) {
    final color = _getTypeColor();

    return [
      _buildThrowPointMarker(imageBounds, markerScale),
      if (_selectedX != null && _selectedY != null)
        _buildConnectionLine(imageBounds),
      if (_selectedX != null && _selectedY != null)
        _buildImpactMarker(imageBounds, markerScale),
      if (widget.readOnly && _drawingStrokes.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ImpactAreaPainter(
                strokes: _drawingStrokes,
                color: color,
                imageBounds: imageBounds,
                opacity: 0.6,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildPickerFooter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = colorScheme.surfaceContainerHighest;
    final textColor = colorScheme.onSurfaceVariant;
    final markerColor = colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: bgColor,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: markerColor, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '投掷点',
                style: TextStyle(color: textColor, fontSize: 12),
              ),
              const SizedBox(width: 24),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.purpleAccent, width: 2),
                ),
                child: const Icon(Icons.close,
                    size: 8, color: Colors.purpleAccent),
              ),
              const SizedBox(width: 8),
              Text(
                '爆点',
                style: TextStyle(color: textColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_selectedX == null) ...[
                AppSvgIcon(
                  asset: 'assets/icons/ui_hint.svg',
                  size: 17,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  semanticsLabel: '提示',
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  _selectedX != null ? '已选择爆点，点击确认保存' : '点击地图任意位置设置爆点',
                  style: TextStyle(
                    color: _selectedX != null
                        ? theme.colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThrowPointMarker(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds,
      double markerScale) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + widget.throwX * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + widget.throwY * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.place, size: 12, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildImpactMarker(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds,
      double markerScale) {
    const double baseHalfSize = 10.0;
    final left =
        imageBounds.offsetX + _selectedX! * imageBounds.width - baseHalfSize;
    final top =
        imageBounds.offsetY + _selectedY! * imageBounds.height - baseHalfSize;

    return Positioned(
      left: left,
      top: top,
      child: Transform.scale(
        scale: markerScale,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.purpleAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withValues(alpha: 0.4),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 12, color: Colors.purpleAccent),
        ),
      ),
    );
  }

  Widget _buildConnectionLine(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    final startX = imageBounds.offsetX + widget.throwX * imageBounds.width;
    final startY = imageBounds.offsetY + widget.throwY * imageBounds.height;
    final endX = imageBounds.offsetX + _selectedX! * imageBounds.width;
    final endY = imageBounds.offsetY + _selectedY! * imageBounds.height;

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DashedLinePainter(
            start: Offset(startX, startY),
            end: Offset(endX, endY),
            color: Colors.purpleAccent.withValues(alpha: 0.7),
            strokeWidth: 2,
            dashLength: 5,
            gapLength: 5,
          ),
        ),
      ),
    );
  }
}

class _ImpactAreaPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final Color color;
  final double opacity;
  final ({
    double width,
    double height,
    double offsetX,
    double offsetY
  }) imageBounds;

  _ImpactAreaPainter({
    required this.strokes,
    required this.color,
    required this.imageBounds,
    required this.opacity,
  });

  List<Offset> _extractPoints(dynamic rawPoints) {
    if (rawPoints is! List) return const [];
    final points = <Offset>[];
    for (final p in rawPoints) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
        points.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      } else if (p is Map && p['x'] is num && p['y'] is num) {
        points.add(
            Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
      }
    }
    return points;
  }

  double _extractStrokeWidth(Map<String, dynamic> stroke) {
    final widthRatio =
        ((stroke['widthRatio'] as num?) ?? (stroke['w'] as num?))?.toDouble();
    if (widthRatio != null) {
      final normalized = widthRatio > 1.0 ? widthRatio / 1000.0 : widthRatio;
      return (normalized * imageBounds.width).clamp(3.0, 120.0);
    }
    final strokeWidth = (stroke['strokeWidth'] as num?)?.toDouble();
    return strokeWidth ?? 15.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: opacity));

    for (final stroke in strokes) {
      final points = _extractPoints(stroke['points'] ?? stroke['p']);
      if (points.isEmpty) continue;
      final width = _extractStrokeWidth(stroke);
      final isEraser = stroke['isEraser'] == true || stroke['e'] == 1;
      final isShape = stroke['isShape'] == true || stroke['s'] == 1;
      _drawStroke(canvas, points, width, isEraser, isShape);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, List<Offset> points, double width,
      bool isEraser, bool isShape) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = isEraser ? Colors.transparent : color.withValues(alpha: 1.0)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isShape ? PaintingStyle.fill : PaintingStyle.stroke;

    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    final path = Path();
    final start = _limitPoint(points[0]);
    path.moveTo(start.dx, start.dy);

    if (points.length == 1) {
      path.lineTo(start.dx, start.dy);
    }

    for (int i = 1; i < points.length; i++) {
      final p = _limitPoint(points[i]);
      path.lineTo(p.dx, p.dy);
    }

    if (isShape) {
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  Offset _limitPoint(Offset ratio) {
    return Offset(
      imageBounds.offsetX + ratio.dx * imageBounds.width,
      imageBounds.offsetY + ratio.dy * imageBounds.height,
    );
  }

  @override
  bool shouldRepaint(covariant _ImpactAreaPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.opacity != opacity ||
        oldDelegate.color != color;
  }
}

class _DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedLinePainter({
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashLength = 4,
    this.gapLength = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final totalLength = (end - start).distance;
    if (totalLength == 0) return;

    final direction = (end - start) / totalLength;

    double currentLength = 0;
    bool draw = true;

    path.moveTo(start.dx, start.dy);

    while (currentLength < totalLength) {
      final segmentLength = draw ? dashLength : gapLength;
      final nextLength =
          (currentLength + segmentLength).clamp(0.0, totalLength);
      final nextPoint = start + direction * nextLength;

      if (draw) {
        path.lineTo(nextPoint.dx, nextPoint.dy);
      } else {
        path.moveTo(nextPoint.dx, nextPoint.dy);
      }

      currentLength = nextLength;
      draw = !draw;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return start != oldDelegate.start ||
        end != oldDelegate.end ||
        color != oldDelegate.color;
  }
}
