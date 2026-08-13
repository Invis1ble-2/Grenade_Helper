import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppSvgIcon extends StatelessWidget {
  final String asset;
  final double size;
  final Color? color;
  final String? semanticsLabel;

  const AppSvgIcon({
    super.key,
    required this.asset,
    this.size = 20,
    this.color,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? IconTheme.of(context).color ?? Colors.grey,
        BlendMode.srcIn,
      ),
      semanticsLabel: semanticsLabel,
    );
  }
}
