import 'package:flutter/material.dart';

import '../models.dart';
import 'grenade_type_icon.dart';

class SelectableGrenadeListItem extends StatelessWidget {
  final Grenade grenade;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPreview;
  final VoidCallback? onTap;
  final Color accentColor;

  const SelectableGrenadeListItem({
    super.key,
    required this.grenade,
    required this.selected,
    required this.onChanged,
    required this.onPreview,
    this.onTap,
    this.accentColor = Colors.orange,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    grenade.layer.loadSync();
    final layer = grenade.layer.value;
    layer?.map.loadSync();
    final layerName = layer?.name ?? '-';
    final mapName = layer?.map.value?.name ?? '-';
    final hasImpact = hasValidImpactPoint(grenade);
    final hasWallbang = hasValidWallbangLine(grenade);
    final showPointBadge = hasImpact || hasWallbang;
    final badgeColor = hasWallbang ? Colors.cyan : Colors.green;
    final badgeIcon =
        hasWallbang ? Icons.north_east_rounded : Icons.my_location;
    final badgeLabel = hasWallbang ? '穿线' : '爆点';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: selected
          ? accentColor.withValues(alpha: 0.14)
          : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: selected
            ? BorderSide(color: accentColor, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
                activeColor: accentColor,
              ),
              GrenadeTypeIcon(type: grenade.type, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            grenade.title.isEmpty ? '(未命名道具)' : grenade.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showPointBadge)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(badgeIcon, size: 10, color: badgeColor),
                                const SizedBox(width: 2),
                                Text(
                                  badgeLabel,
                                  style: TextStyle(
                                      fontSize: 10, color: badgeColor),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _MetaText(icon: Icons.map_outlined, text: mapName),
                        _MetaText(icon: Icons.layers_outlined, text: layerName),
                        if (grenade.author != null &&
                            grenade.author!.trim().isNotEmpty)
                          _MetaText(
                            icon: Icons.person_outline,
                            text: grenade.author!.trim(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onPreview,
                icon: Icon(Icons.visibility_outlined, color: accentColor),
                tooltip: '预览',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[600]),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }
}
