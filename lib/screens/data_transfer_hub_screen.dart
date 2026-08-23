import 'package:flutter/material.dart';

import '../theme/app_design_system.dart';
import 'import_screen.dart';
import 'lan_sync_screen.dart';
import 'share_screen.dart';

class DataTransferHubScreen extends StatelessWidget {
  const DataTransferHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_TransferItem>[
      const _TransferItem(
        title: '导入道具包',
        description: '从文件、链接或云端仓库添加道具数据',
        icon: Icons.download_rounded,
        color: Color(0xFF2877C7),
        destination: ImportScreen(),
      ),
      const _TransferItem(
        title: '导出与分享',
        description: '选择地图或道具，生成可分享的数据包',
        icon: Icons.ios_share_rounded,
        color: Color(0xFFC65D00),
        destination: ShareScreen(),
      ),
      const _TransferItem(
        title: '局域网同步',
        description: '在同一网络的电脑与手机之间直接同步',
        icon: Icons.sync_rounded,
        color: Color(0xFF258A49),
        destination: LanSyncScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('数据传输')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 3
              : (constraints.maxWidth >= 720 ? 2 : 1);
          return GridView.builder(
            padding: AppBreakpoints.isMobile(context)
                ? AppBreakpoints.withMobileBottomBarClearance(
                    context, const EdgeInsets.all(24))
                : const EdgeInsets.all(24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 180,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _TransferTile(item: items[index]),
          );
        },
      ),
    );
  }
}

class _TransferItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final Widget destination;

  const _TransferItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.destination,
  });
}

class _TransferTile extends StatefulWidget {
  final _TransferItem item;
  const _TransferTile({required this.item});

  @override
  State<_TransferTile> createState() => _TransferTileState();
}

class _TransferTileState extends State<_TransferTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: AppMotion.quick,
        curve: AppMotion.enter,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => widget.item.destination),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.item.icon, color: widget.item.color),
                  ),
                  const Spacer(),
                  Text(widget.item.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(widget.item.description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.appTheme.mutedText)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
