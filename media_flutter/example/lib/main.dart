import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_flutter/media_flutter.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'image_tab.dart';
import 'video_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AssetPicker.registerObserve();
  await Media.init();
  runApp(const MediaExampleApp());
}

class MediaExampleApp extends StatelessWidget {
  const MediaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'media',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _cacheClearBusy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _clearAppCache() async {
    setState(() => _cacheClearBusy = true);
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final roots = <Directory>[cacheDir];
      if (Platform.isAndroid || Platform.isIOS) {
        roots.add(await getTemporaryDirectory());
      }

      for (final dir in roots) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          try {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else {
              await entity.delete();
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cache cleared. Re-open tabs and pick files again if copies were removed.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clear cache failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cacheClearBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('media'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Video', icon: Icon(Icons.videocam_outlined)),
            Tab(text: 'Image', icon: Icon(Icons.image_outlined)),
          ],
        ),
        actions: [
          IconButton(
            tooltip:
                'Clear app cache (picker copies, transcode outputs, thumbnails)',
            onPressed: _cacheClearBusy ? null : _clearAppCache,
            icon: _cacheClearBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          VideoExampleTab(),
          ImageExampleTab(),
        ],
      ),
    );
  }
}
