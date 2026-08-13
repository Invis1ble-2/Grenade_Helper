import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';

/// 统一的道具类型图标，避免不同页面使用不同 emoji。
class GrenadeTypeIcon extends StatelessWidget {
  final int type;
  final double size;
  final Color? color;

  const GrenadeTypeIcon({
    super.key,
    required this.type,
    this.size = 22,
    this.color,
  });

  static String assetForType(int type) {
    switch (type) {
      case GrenadeType.smoke:
        return 'assets/icons/grenade_smoke.svg';
      case GrenadeType.flash:
        return 'assets/icons/grenade_flash.svg';
      case GrenadeType.molotov:
        return 'assets/icons/grenade_molotov.svg';
      case GrenadeType.he:
        return 'assets/icons/grenade_he.svg';
      case GrenadeType.wallbang:
        return 'assets/icons/grenade_wallbang.svg';
      default:
        return 'assets/icons/grenade_unknown.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? _defaultColor(context);
    return SvgPicture.asset(
      assetForType(type),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      semanticsLabel: _label,
    );
  }

  String get _label {
    switch (type) {
      case GrenadeType.smoke:
        return '烟雾弹';
      case GrenadeType.flash:
        return '闪光弹';
      case GrenadeType.molotov:
        return '燃烧弹';
      case GrenadeType.he:
        return '手雷';
      case GrenadeType.wallbang:
        return '穿点';
      default:
        return '未知道具';
    }
  }

  Color _defaultColor(BuildContext context) {
    switch (type) {
      case GrenadeType.smoke:
        return Colors.blueGrey;
      case GrenadeType.flash:
        return Colors.amber.shade700;
      case GrenadeType.molotov:
        return Colors.deepOrange;
      case GrenadeType.he:
        return Colors.redAccent;
      case GrenadeType.wallbang:
        return Theme.of(context).colorScheme.primary;
      default:
        return Colors.grey;
    }
  }
}
