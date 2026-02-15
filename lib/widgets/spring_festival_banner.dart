import 'package:flutter/material.dart';

/// 春节横联组件
/// 内容：“恭贺新年”，字体：行书
class SpringFestivalBanner extends StatelessWidget {
  const SpringFestivalBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFD72B2B), // 春节红
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            offset: Offset(0, 2),
            blurRadius: 4,
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 装饰边框（可选，增加正式感）
          Positioned(
            left: 10,
            right: 10,
            top: 4,
            bottom: 4,
            child: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          // 横联文字
          const Text(
            '恭 贺 新 年',
            style: TextStyle(
              color: Color(0xFFFFD700), // 金色
              fontSize: 22,
              fontWeight: FontWeight.normal,
              fontFamily: 'STXingkai', // 优先使用华文行书
              letterSpacing: 8,
              shadows: [
                Shadow(
                  color: Colors.black45,
                  offset: Offset(1, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
