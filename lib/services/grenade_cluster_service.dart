import '../models.dart';

class GrenadeCluster {
  const GrenadeCluster(this.members);

  final List<Grenade> members;

  Grenade get anchor => members.first;

  bool containsGrenade(int grenadeId) {
    return members.any((grenade) => grenade.id == grenadeId);
  }
}

class GrenadeClusterService {
  static const double defaultThreshold = 0.03;

  static int compareGrenades(Grenade a, Grenade b) {
    final byY = a.yRatio.compareTo(b.yRatio);
    if (byY != 0) return byY;

    final byX = a.xRatio.compareTo(b.xRatio);
    if (byX != 0) return byX;

    return a.id.compareTo(b.id);
  }

  static List<Grenade> sortGrenades(Iterable<Grenade> grenades) {
    final sorted = grenades.toList();
    sorted.sort(compareGrenades);
    return sorted;
  }

  static List<GrenadeCluster> buildClusters(
    Iterable<Grenade> grenades, {
    double threshold = defaultThreshold,
  }) {
    final sorted = sortGrenades(grenades);
    if (sorted.isEmpty) return const [];

    final thresholdSq = threshold * threshold;
    final clusters = <GrenadeCluster>[];
    final used = List<bool>.filled(sorted.length, false);

    for (var i = 0; i < sorted.length; i++) {
      if (used[i]) continue;

      final anchor = sorted[i];
      final members = <Grenade>[anchor];
      used[i] = true;

      for (var j = i + 1; j < sorted.length; j++) {
        if (used[j]) continue;

        final candidate = sorted[j];
        final dx = anchor.xRatio - candidate.xRatio;
        final dy = anchor.yRatio - candidate.yRatio;
        if (dx * dx + dy * dy < thresholdSq) {
          members.add(candidate);
          used[j] = true;
        }
      }

      members.sort(compareGrenades);
      clusters.add(GrenadeCluster(List.unmodifiable(members)));
    }

    return List.unmodifiable(clusters);
  }

  static GrenadeCluster? findClusterForGrenade(
    Iterable<GrenadeCluster> clusters,
    Grenade? grenade,
  ) {
    if (grenade == null) return null;
    for (final cluster in clusters) {
      if (cluster.containsGrenade(grenade.id)) {
        return cluster;
      }
    }
    return null;
  }
}
