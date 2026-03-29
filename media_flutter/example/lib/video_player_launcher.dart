import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_flutter/media_flutter.dart';

import 'file_video_preview.dart';
import 'media_example_actions.dart';

/// Opens a full player: bottom sheet on mobile, pushed route on desktop.
Future<void> presentLocalVideoPlayer(
  BuildContext context, {
  required String path,
  required String title,
}) async {
  final mobile = Platform.isAndroid || Platform.isIOS;

  void export() {
    shareOrRevealFile(context, path, subject: title);
  }

  if (mobile) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.82;
        return SizedBox(
          height: h,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Export / share',
                      icon: const Icon(Icons.ios_share_outlined),
                      onPressed: () {
                        shareOrRevealFile(ctx, path, subject: title);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Expanded(
                  child: FileVideoPreview(
                    path: path,
                    title: title,
                    showTitleRow: false,
                    expandToFill: true,
                    onExport: () =>
                        shareOrRevealFile(ctx, path, subject: title),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  } else {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'Reveal in file manager',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: export,
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: FileVideoPreview(
                      path: path,
                      title: title,
                      showTitleRow: false,
                      expandToFill: true,
                      onExport: export,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact tile: small video frame as background, tap to open [presentLocalVideoPlayer].
class VideoPlayLaunchTile extends StatefulWidget {
  const VideoPlayLaunchTile({
    super.key,
    required this.videoPath,
    required this.enabled,
    required this.onOpen,
    this.subtitle,
    this.timeSec = 1.0,
    this.maxThumbEdge = 128,
  });

  final String videoPath;
  final bool enabled;
  final VoidCallback onOpen;
  final String? subtitle;

  /// Sample time for [Media.thumbnailImage].
  final double timeSec;

  /// Long-edge cap for the background still (keeps decode work small).
  final int maxThumbEdge;

  @override
  State<VideoPlayLaunchTile> createState() => _VideoPlayLaunchTileState();
}

class _VideoPlayLaunchTileState extends State<VideoPlayLaunchTile> {
  late Future<Uint8List?> _thumbFuture;

  @override
  void initState() {
    super.initState();
    _thumbFuture = _loadThumb();
  }

  @override
  void didUpdateWidget(covariant VideoPlayLaunchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath ||
        oldWidget.timeSec != widget.timeSec ||
        oldWidget.maxThumbEdge != widget.maxThumbEdge) {
      setState(() {
        _thumbFuture = _loadThumb();
      });
    }
  }

  Future<Uint8List?> _loadThumb() async {
    try {
      return await Media.thumbnailImage(
        path: widget.videoPath,
        timeSec: widget.timeSec,
        maxEdge: widget.maxThumbEdge,
        format: ThumbnailFormat.jpeg,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.enabled ? widget.onOpen : null,
        child: SizedBox(
          width: 88,
          height: 72,
          child: FutureBuilder<Uint8List?>(
            future: _thumbFuture,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: cs.surfaceContainerHighest),
                    )
                  else if (snapshot.connectionState == ConnectionState.waiting)
                    ColoredBox(color: cs.surfaceContainerHighest)
                  else
                    ColoredBox(color: cs.surfaceContainerHighest),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_circle_filled_rounded,
                        size: 34,
                        color: widget.enabled
                            ? Colors.white
                            : cs.outline.withValues(alpha: 0.7),
                        shadows: widget.enabled
                            ? const [
                                Shadow(
                                  blurRadius: 6,
                                  color: Colors.black54,
                                ),
                              ]
                            : null,
                      ),
                      Text(
                        widget.subtitle ?? 'Play',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: widget.enabled
                                  ? Colors.white.withValues(alpha: 0.95)
                                  : cs.outline,
                              shadows: widget.enabled
                                  ? const [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black54,
                                      ),
                                    ]
                                  : null,
                            ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
