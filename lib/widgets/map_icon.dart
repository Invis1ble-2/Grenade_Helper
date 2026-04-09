import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MapIcon extends StatelessWidget {
  final String path;
  final double size;
  final Color fallbackColor;

  const MapIcon({
    super.key,
    required this.path,
    this.size = 20,
    this.fallbackColor = Colors.orange,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return Icon(Icons.map_outlined, size: size, color: fallbackColor);
    }

    final lower = normalized.toLowerCase();
    if (lower.endsWith('.svg')) {
      if (normalized.startsWith('assets/')) {
        return SvgPicture.asset(
          normalized,
          width: size,
          height: size,
          placeholderBuilder: (_) =>
              Icon(Icons.map_outlined, size: size, color: fallbackColor),
        );
      }
      final file = File(normalized);
      if (file.existsSync()) {
        return SvgPicture.file(
          file,
          width: size,
          height: size,
          placeholderBuilder: (_) =>
              Icon(Icons.map_outlined, size: size, color: fallbackColor),
        );
      }
      return Icon(Icons.map_outlined, size: size, color: fallbackColor);
    }

    if (normalized.startsWith('assets/')) {
      return Image.asset(
        normalized,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.map_outlined, size: size, color: fallbackColor),
      );
    }

    final file = File(normalized);
    if (!file.existsSync()) {
      return Icon(Icons.map_outlined, size: size, color: fallbackColor);
    }

    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.map_outlined, size: size, color: fallbackColor),
    );
  }
}
