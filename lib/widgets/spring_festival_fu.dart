import 'package:flutter/material.dart';

/// 一个正式的中国“福”字贴组件
/// 设计：钻石型（旋转45度）红底，金色“福”字，带质感阴影
class SpringFestivalFu extends StatelessWidget {
  final double size;
  const SpringFestivalFu({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: 0.785398, // 45 度 (pi / 4)
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE54848), Color(0xFFB71C1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                // 移除 borderRadius 以实现有棱角的方形
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(5, 5),
                  ),
                ],
              ),
            ),
          ),
          // “福”字
          Positioned(
            child: Text(
              '福',
              style: TextStyle(
                fontSize: size * 0.75,
                fontWeight: FontWeight.w500,
                fontFamily: 'STKaiti', // 华文楷体
                color: const Color(0xFFFFD700),
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    offset: const Offset(3, 3),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
