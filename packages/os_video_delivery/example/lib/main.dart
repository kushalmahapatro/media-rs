import 'dart:io';

import 'package:flutter/material.dart';
import 'package:os_video_delivery/os_video_delivery.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const _OsVideoDeliveryExampleApp());

class _OsVideoDeliveryExampleApp extends StatelessWidget {
  const _OsVideoDeliveryExampleApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'OS Video Delivery',
      home: _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final _pathController = TextEditingController();
  String _log = 'Enter an absolute video path, then Run.';
  VideoSourceInfo? _probe;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _runPipeline() async {
    if (!OsVideoDelivery.isSupported) {
      setState(() => _log = 'Supported on Android, iOS, and macOS only.');
      return;
    }
    final path = _pathController.text.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() => _log = 'File does not exist: $path');
      return;
    }

    setState(() => _log = 'Working…');
    try {
      final probe = await OsVideoDelivery.instance.probe(path);
      final est = await OsVideoDelivery.instance.estimateDelivery(
        path: path,
        profiles: const [VideoDeliveryProfile.hd720, VideoDeliveryProfile.sd480],
      );
      final dir = await getTemporaryDirectory();
      final thumbPath = '${dir.path}/osvd_thumb.jpg';
      await File(thumbPath).writeAsBytes(
        await OsVideoDelivery.instance.videoThumbnail(
          path: path,
          timeMs: 0,
          maxWidth: 320,
          maxHeight: 320,
          format: ThumbnailImageFormat.jpeg,
        ),
      );
      final outPath = '${dir.path}/osvd_out.mp4';
      await OsVideoDelivery.instance.transcode(
        inputPath: path,
        outputPath: outPath,
        profile: VideoDeliveryProfile.sd480,
      );
      final outSize = await File(outPath).length();
      final hd = est.firstWhere((e) => e.profileId == 'hd720');
      final sd = est.firstWhere((e) => e.profileId == 'sd480');
      if (!mounted) return;
      setState(() {
        _probe = probe;
        _log =
            'Probe: ${probe.durationMs}ms, ${probe.displayWidth}x${probe.displayHeight}, rot=${probe.rotationDegrees}°\n'
            'HD est: ${hd.estimatedSizeBytes} bytes (${hd.width}x${hd.height})\n'
            'SD est: ${sd.estimatedSizeBytes} bytes (${sd.width}x${sd.height})\n'
            'Thumb: $thumbPath\n'
            'Transcoded: $outPath ($outSize bytes)';
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _log = 'Error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OS Video Delivery Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Absolute path to video',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _runPipeline,
              child: const Text('Probe → estimate → thumbnail → transcode'),
            ),
            const SizedBox(height: 12),
            if (_probe != null)
              Text(
                'Display ${_probe!.displayWidth}x${_probe!.displayHeight}, '
                'rotation ${_probe!.rotationDegrees}°',
              ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(child: SelectableText(_log)),
            ),
          ],
        ),
      ),
    );
  }
}
