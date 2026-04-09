import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? imageProviderFromPath(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('assets/')) return AssetImage(normalized);

  final file = File(normalized);
  if (!file.existsSync()) return null;
  return FileImage(file);
}
