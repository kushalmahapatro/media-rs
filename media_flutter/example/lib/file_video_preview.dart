import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays a local file with [VideoPlayerController.file]; play/pause and optional export.
class FileVideoPreview extends StatefulWidget {
  const FileVideoPreview({
    super.key,
    required this.path,
    required this.title,
    this.onExport,
    this.emptyHint,
    this.showTitleRow = true,

    /// When true, the widget must sit inside a parent with a **bounded height** (e.g. [Expanded]).
    /// The video letterboxes to fit that height and play/scrub stays **fixed below** the video
    /// (no nested scrolling).
    this.expandToFill = false,
  });

  final String path;
  final String title;
  final VoidCallback? onExport;
  final String? emptyHint;

  /// When false, only the video surface and transport are shown (parent supplies a title bar).
  final bool showTitleRow;

  /// See [FileVideoPreview.expandToFill].
  final bool expandToFill;

  @override
  State<FileVideoPreview> createState() => _FileVideoPreviewState();
}

class _FileVideoPreviewState extends State<FileVideoPreview> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _open(widget.path);
  }

  @override
  void didUpdateWidget(covariant FileVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _open(widget.path);
    }
  }

  Future<void> _open(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _controller?.dispose();
    _controller = null;
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() {
        _controller = c;
        _loading = false;
      });
    } catch (e) {
      await c.dispose();
      if (mounted) {
        setState(() {
          _controller = null;
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double _displayAspectRatio(VideoPlayerController c) {
    final ar = c.value.aspectRatio;
    return ar == 0 ? 16 / 9 : ar;
  }

  /// Letterboxed [VideoPlayer] inside [constraints] (portrait/tall video shrinks to fit height).
  Widget _letterboxedVideo(
    VideoPlayerController c,
    BoxConstraints constraints,
  ) {
    final ar = _displayAspectRatio(c);
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;
    var w = maxW;
    var h = w / ar;
    if (h > maxH) {
      h = maxH;
      w = h * ar;
    }
    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: VideoPlayer(c),
      ),
    );
  }

  Widget _transportRow(VideoPlayerController c) {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            c.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
          onPressed: () {
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
            setState(() {});
          },
        ),
        Expanded(
          child: VideoProgressIndicator(
            c,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    if (widget.expandToFill) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showTitleRow)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (widget.onExport != null)
                      IconButton(
                        tooltip: 'Export original / share, or reveal on desktop',
                        icon: const Icon(Icons.ios_share_outlined),
                        onPressed: widget.onExport,
                      ),
                  ],
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                        : c != null && c.value.isInitialized
                            ? LayoutBuilder(
                                builder: (context, constraints) =>
                                    _letterboxedVideo(c, constraints),
                              )
                            : Center(
                                child: Text(widget.emptyHint ?? 'No video'),
                              ),
              ),
              if (!_loading &&
                  _error == null &&
                  c != null &&
                  c.value.isInitialized)
                _transportRow(c),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showTitleRow)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (widget.onExport != null)
                    IconButton(
                      tooltip: 'Export original / share, or reveal on desktop',
                      icon: const Icon(Icons.ios_share_outlined),
                      onPressed: widget.onExport,
                    ),
                ],
              ),
            if (_loading)
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              )
            else if (c != null && c.value.isInitialized) ...[
              AspectRatio(
                aspectRatio: _displayAspectRatio(c),
                child: VideoPlayer(c),
              ),
              _transportRow(c),
            ]
            else
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(
                  child: Text(widget.emptyHint ?? 'No video'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
