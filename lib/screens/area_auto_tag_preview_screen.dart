import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:photo_view/photo_view.dart';
import '../models.dart';
import '../models/map_area.dart';
import '../providers.dart';
import '../services/area_service.dart';

class AreaAutoTagPreviewScreen extends ConsumerStatefulWidget {
  final GameMap gameMap;
  final MapArea area;

  const AreaAutoTagPreviewScreen({
    super.key,
    required this.gameMap,
    required this.area,
  });

  @override
  ConsumerState<AreaAutoTagPreviewScreen> createState() =>
      _AreaAutoTagPreviewScreenState();
}

class _AreaAutoTagPreviewScreenState
    extends ConsumerState<AreaAutoTagPreviewScreen> {
  late final PhotoViewController _photoViewController;
  late final AreaService _areaService;

  bool _isLoading = true;
  bool _isSyncing = false;
  bool _showImpact = false;
  bool _tagByImpact = false;
  bool _showOnlyMatched = false;

  MapLayer? _layer;
  List<Grenade> _grenades = [];
  Set<int> _inAreaThrowIds = {};
  Set<int> _inAreaImpactIds = {};
  List<List<Offset>> _strokes = [];

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    final isar = ref.read(isarProvider);
    _areaService = AreaService(isar);
    _strokes = _parseStrokes(widget.area.strokes);
    _loadData();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final isar = ref.read(isarProvider);

    MapLayer? layer;
    if (widget.area.layerId != null) {
      layer = await isar.mapLayers.get(widget.area.layerId!);
    } else {
      widget.gameMap.layers.loadSync();
      if (widget.gameMap.layers.isNotEmpty) {
        layer = widget.gameMap.layers.first;
      }
    }

    if (layer == null) {
      if (!mounted) return;
      setState(() {
        _layer = null;
        _grenades = [];
        _inAreaThrowIds = {};
        _inAreaImpactIds = {};
        _isLoading = false;
      });
      return;
    }

    final grenades = await isar.grenades
        .filter()
        .layer((q) => q.idEqualTo(layer!.id))
        .findAll();

    final inAreaThrowIds = <int>{};
    final inAreaImpactIds = <int>{};
    for (final g in grenades) {
      if (_areaService.isPointInArea(g.xRatio, g.yRatio, widget.area)) {
        inAreaThrowIds.add(g.id);
      }
      if (g.impactXRatio != null &&
          g.impactYRatio != null &&
          _areaService.isPointInArea(
              g.impactXRatio!, g.impactYRatio!, widget.area)) {
        inAreaImpactIds.add(g.id);
      }
    }

    if (!mounted) return;
    setState(() {
      _layer = layer;
      _grenades = grenades;
      _inAreaThrowIds = inAreaThrowIds;
      _inAreaImpactIds = inAreaImpactIds;
      _isLoading = false;
    });
  }

  Future<void> _syncAreaTag() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final result = await _areaService.syncAreaTag(widget.area,
        useImpactPoint: _tagByImpact);

    if (!mounted) return;
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${_tagByImpact ? "按爆点" : "按站位"}同步：处理${result.processedGrenades}个，命中${result.matchedGrenades}个，新增${result.addedLinks}条，移除${result.removedLinks}条'),
      backgroundColor: Colors.green,
    ));
  }

  ({double width, double height, double offsetX, double offsetY})
      _getImageBounds(double containerWidth, double containerHeight) {
    const double imageAspectRatio = 1.0;
    final containerAspectRatio = containerWidth / containerHeight;

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

  List<List<Offset>> _parseStrokes(String json) {
    try {
      final data = jsonDecode(json) as List;
      return data.map((stroke) {
        final points = stroke as List;
        return points
            .map((p) =>
                Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList();
      }).toList();
    } catch (_) {
      return [];
    }
  }

  int get _displayTotal {
    if (_showImpact) {
      return _grenades
          .where((g) => g.impactXRatio != null && g.impactYRatio != null)
          .length;
    }
    return _grenades.length;
  }

  int get _displayMatched =>
      _showImpact ? _inAreaImpactIds.length : _inAreaThrowIds.length;

  Future<void> _showGrenadeListForPoint(Grenade anchor) async {
    final matchedSet = _showImpact ? _inAreaImpactIds : _inAreaThrowIds;
    if (!matchedSet.contains(anchor.id)) return;

    final group = _grenades.where((g) {
      if (!matchedSet.contains(g.id)) return false;
      if (_showImpact) {
        if (anchor.impactXRatio == null ||
            anchor.impactYRatio == null ||
            g.impactXRatio == null ||
            g.impactYRatio == null) {
          return false;
        }
        return (g.impactXRatio! - anchor.impactXRatio!).abs() < 1e-6 &&
            (g.impactYRatio! - anchor.impactYRatio!).abs() < 1e-6;
      }
      return (g.xRatio - anchor.xRatio).abs() < 1e-6 &&
          (g.yRatio - anchor.yRatio).abs() < 1e-6;
    }).toList();

    final items = group.isEmpty ? [anchor] : group;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '命中道具（${items.length}）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final g = items[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          g.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle:
                            g.description == null || g.description!.isEmpty
                                ? null
                                : Text(
                                    g.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('区域可视化标注 - ${widget.area.name}'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新数据',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _layer == null
              ? const Center(child: Text('区域关联楼层不存在，无法预览'))
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(child: _buildMapPreview()),
                    _buildBottomActions(),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '楼层：${_layer!.name}    当前模式命中：$_displayMatched / $_displayTotal',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.place_outlined, size: 16),
                      label: Text('站位'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.adjust, size: 16),
                      label: Text('爆点'),
                    ),
                  ],
                  selected: {_showImpact},
                  onSelectionChanged: (value) {
                    setState(() => _showImpact = value.first);
                  },
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.touch_app_outlined, size: 16),
                      label: Text('按站位打标签'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.gps_fixed, size: 16),
                      label: Text('按爆点打标签'),
                    ),
                  ],
                  selected: {_tagByImpact},
                  onSelectionChanged: (value) {
                    setState(() => _tagByImpact = value.first);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('仅显示命中'),
                selected: _showOnlyMatched,
                onSelected: (v) => setState(() => _showOnlyMatched = v),
                showCheckmark: false,
              ),
              const Spacer(),
              _buildLegendDot('命中', Colors.greenAccent),
              const SizedBox(width: 10),
              _buildLegendDot('未命中', Colors.white54),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMapPreview() {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageBounds =
              _getImageBounds(constraints.maxWidth, constraints.maxHeight);
          return PhotoView.customChild(
            controller: _photoViewController,
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 4.0,
            initialScale: PhotoViewComputedScale.contained,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            child: Stack(
              children: [
                Image.asset(
                  _layer!.assetPath,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.contain,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _AreaScopePainter(
                        strokes: _strokes,
                        color: Color(widget.area.colorValue),
                        imageBounds: imageBounds,
                      ),
                    ),
                  ),
                ),
                ..._buildMarkers(imageBounds),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildMarkers(
      ({
        double width,
        double height,
        double offsetX,
        double offsetY
      }) imageBounds) {
    const markerSize = 14.0;
    final widgets = <Widget>[];

    for (final g in _grenades) {
      double? x;
      double? y;
      bool matched;
      IconData icon;

      if (_showImpact) {
        if (g.impactXRatio == null || g.impactYRatio == null) continue;
        x = g.impactXRatio!;
        y = g.impactYRatio!;
        matched = _inAreaImpactIds.contains(g.id);
        icon = Icons.adjust;
      } else {
        x = g.xRatio;
        y = g.yRatio;
        matched = _inAreaThrowIds.contains(g.id);
        icon = Icons.place;
      }

      final color = matched ? Colors.greenAccent : Colors.white54;
      if (_showOnlyMatched && !matched) {
        continue;
      }
      widgets.add(Positioned(
        left: imageBounds.offsetX + x * imageBounds.width - markerSize / 2,
        top: imageBounds.offsetY + y * imageBounds.height - markerSize / 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: matched ? () => _showGrenadeListForPoint(g) : null,
          child: Container(
            width: markerSize,
            height: markerSize,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.4),
            ),
            child: Icon(icon, size: 10, color: color),
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildBottomActions() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('重新计算'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _syncAreaTag,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('同步该区域标签'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaScopePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;
  final ({
    double width,
    double height,
    double offsetX,
    double offsetY
  }) imageBounds;

  _AreaScopePainter({
    required this.strokes,
    required this.color,
    required this.imageBounds,
  });

  Offset _toScreen(Offset ratio) => Offset(
        imageBounds.offsetX + ratio.dx * imageBounds.width,
        imageBounds.offsetY + ratio.dy * imageBounds.height,
      );

  Path _buildPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    final screenPoints = points.map(_toScreen).toList();
    path.moveTo(screenPoints.first.dx, screenPoints.first.dy);
    if (screenPoints.length < 3) {
      for (int i = 1; i < screenPoints.length; i++) {
        path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
      }
    } else {
      for (int i = 1; i < screenPoints.length - 1; i++) {
        final p1 = screenPoints[i];
        final p2 = screenPoints[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      final last = screenPoints.last;
      path.lineTo(last.dx, last.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.24)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;

    for (final stroke in strokes) {
      if (stroke.length < 3) continue;
      final path = _buildPath(stroke);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaScopePainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.color != color;
  }
}
