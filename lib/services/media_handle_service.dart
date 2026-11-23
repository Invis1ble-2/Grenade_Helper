import 'dart:io';
import 'package:path/path.dart' as p;

typedef MediaHandleReleaser = Future<void> Function();
typedef ExternalMediaHandleReleaser = Future<void> Function(List<String> paths);

class _RegisteredReleaser {
  final String normalizedPath;
  final MediaHandleReleaser releaser;

  const _RegisteredReleaser(this.normalizedPath, this.releaser);
}

class MediaHandleService {
  static final Map<Object, _RegisteredReleaser> _releasers = {};
  static ExternalMediaHandleReleaser? externalReleaser;

  static String normalizePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    final normalized = p.normalize(File(trimmed).absolute.path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static void register(
    Object token,
    String filePath,
    MediaHandleReleaser releaser,
  ) {
    final normalized = normalizePath(filePath);
    if (normalized.isEmpty) {
      _releasers.remove(token);
      return;
    }
    _releasers[token] = _RegisteredReleaser(normalized, releaser);
  }

  static void unregister(Object token) {
    _releasers.remove(token);
  }

  static Future<void> releaseLocalPaths(Iterable<String> paths) async {
    final targetPaths =
        paths.map(normalizePath).where((path) => path.isNotEmpty).toSet();
    if (targetPaths.isEmpty) return;

    final matches = _releasers.values
        .where((entry) => targetPaths.contains(entry.normalizedPath))
        .map((entry) => entry.releaser)
        .toList(growable: false);
    if (matches.isEmpty) return;

    await Future.wait(matches.map((release) async {
      try {
        await release();
      } catch (_) {}
    }));
  }

  static Future<void> releasePaths(Iterable<String> paths) async {
    final uniquePaths = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniquePaths.isEmpty) return;

    await releaseLocalPaths(uniquePaths);
    final external = externalReleaser;
    if (external != null) {
      await external(uniquePaths);
    }
  }
}
