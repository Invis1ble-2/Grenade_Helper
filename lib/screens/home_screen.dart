import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import '../models.dart';
import '../providers.dart';
import '../main.dart';
import 'map_screen.dart';
import 'grenade_detail_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'share_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';

// 全局搜索逻辑
class GlobalSearchDelegate extends SearchDelegate {
  final WidgetRef ref;
  GlobalSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);
  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    if (query.isEmpty) return const SizedBox();

    final isar = ref.read(isarProvider);
    // 模糊搜索：标题包含 query
    final results = isar.grenades
        .filter()
        .titleContains(query, caseSensitive: false)
        .findAllSync();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (ctx, index) {
        final g = results[index];
        g.layer.loadSync();
        g.layer.value?.map.loadSync();
        final mapName = g.layer.value?.map.value?.name ?? "";
        return ListTile(
          leading: const Icon(Icons.ads_click),
          title: Text(g.title),
          subtitle: Text(mapName, style: const TextStyle(color: Colors.orange)),
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => GrenadeDetailScreen(
                        grenadeId: g.id, isEditing: false)));
          },
        );
      },
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isar = ref.watch(isarProvider);
    final maps = isar.gameMaps.where().findAllSync();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () =>
              showSearch(context: context, delegate: GlobalSearchDelegate(ref)),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: Colors.white10, borderRadius: BorderRadius.circular(20)),
            child: const Row(
              children: [
                Icon(Icons.search, color: Colors.grey),
                SizedBox(width: 8),
                Text("搜索道具...",
                    style: TextStyle(color: Colors.grey, fontSize: 14))
              ],
            ),
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text("Grenade Helper",
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            )),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text("分享 / 导入"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ShareScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("设置"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      settingsService: globalSettingsService,
                      onHotkeyChanged: (action, config) {
                        globalHotkeyService?.updateHotkey(action, config);
                      },
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text("关于"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: maps.length,
        itemBuilder: (ctx, index) {
          final map = maps[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => MapScreen(gameMap: map))),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                    image: DecorationImage(
                  image: AssetImage(map.backgroundPath),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.4), BlendMode.darken),
                )),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        map.iconPath,
                        width: 40,
                        height: 40,
                      ),
                      const SizedBox(width: 16),
                      Text(map.name,
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
