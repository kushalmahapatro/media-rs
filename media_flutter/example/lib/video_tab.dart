import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:media_flutter/media_flutter.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart'
    hide ThumbnailFormat;

import 'example_file_size.dart';
import 'example_section_divider.dart';
import 'media_example_actions.dart';
import 'thumbnail_width_presets.dart';
import 'video_player_launcher.dart';

class VideoExampleTab extends StatefulWidget {
  const VideoExampleTab({super.key});

  @override
  State<VideoExampleTab> createState() => _VideoExampleTabState();
}

class _VideoExampleTabState extends State<VideoExampleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _path;
  VideoProbe? _probe;
  Uint8List? _thumbBytes;
  String? _thumbPath;
  String? _error;
  double _progress = 0;
  String _progressMsg = '';
  bool _busy = false;

  /// Wall-clock estimate for the in-flight transcode; `null` when idle.
  EncodeTimeEstimate? _transcodeEta;

  /// When [true], elapsed time passed [EncodeTimeEstimate.estimated] but transcode is still running.
  bool _transcodePastEstimate = false;

  Timer? _transcodeProgressTimer;

  ThumbnailFormat _thumbFormat = ThumbnailFormat.png;
  ThumbnailFormat _timelineFormat = ThumbnailFormat.jpeg;
  ThumbnailWidthPreset _thumbWidthPreset = ThumbnailWidthPreset.medium;
  final TextEditingController _thumbCustomWidthCtrl =
      TextEditingController(text: '720');
  ThumbnailWidthPreset _timelineWidthPreset = ThumbnailWidthPreset.small;
  final TextEditingController _timelineCustomWidthCtrl =
      TextEditingController(text: '320');
  final TextEditingController _timelineCountCtrl = TextEditingController(text: '10');

  VideoPreset? _selectedPreset;
  String? _lastTranscodePath;
  int? _lastTranscodeBytes;
  int? _lastTranscodeWallMs;

  final List<TimelineThumbnail> _timelineFrames = [];
  bool _timelineBusy = false;
  bool _timelineExportAllBusy = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void dispose() {
    _transcodeProgressTimer?.cancel();
    _thumbCustomWidthCtrl.dispose();
    _timelineCustomWidthCtrl.dispose();
    _timelineCountCtrl.dispose();
    super.dispose();
  }

  void _syncPresetWithProbe(VideoProbe probe) {
    final fitting = presetsFittingSource(probe).toList();
    if (fitting.isEmpty) {
      _selectedPreset = null;
      return;
    }
    final cur = _selectedPreset;
    if (cur == null || !fitting.contains(cur)) {
      _selectedPreset = fitting.reduce(
        (a, b) => presetMaxLongEdge(a) >= presetMaxLongEdge(b) ? a : b,
      );
    }
  }

  /// When source dimensions are unknown, any preset is allowed (encoder uses `min(cap, source)`).
  bool _transcodePresetEnabled(VideoProbe probe, VideoPreset pr) {
    final src = sourceLongEdge(probe);
    if (src == 0) return true;
    return presetMaxLongEdge(pr) <= src;
  }

  int? _resolvedThumbMaxEdge() {
    return resolveThumbnailMaxEdge(
      preset: _thumbWidthPreset,
      probe: _probe,
      customPixelsText: _thumbCustomWidthCtrl.text,
    );
  }

  int? _resolvedTimelineMaxEdge() {
    return resolveThumbnailMaxEdge(
      preset: _timelineWidthPreset,
      probe: _probe,
      customPixelsText: _timelineCustomWidthCtrl.text,
    );
  }

  static String _formatShortLabel(ThumbnailFormat f) =>
      f.name.toUpperCase();

  Widget _memoryImagePreview(
    Uint8List bytes, {
    double? height,
    BoxFit? fit,
    required ThumbnailFormat imageFormat,
  }) {
    return Image.memory(
      bytes,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Preview could not decode (${imageFormat.name}). Try PNG or JPEG.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      ),
    );
  }

  void _clearAfterPick() {
    _probe = null;
    _thumbBytes = null;
    _thumbPath = null;
    _error = null;
    _progress = 0;
    _selectedPreset = null;
    _lastTranscodePath = null;
    _lastTranscodeBytes = null;
    _lastTranscodeWallMs = null;
    _timelineFrames.clear();
  }

  Future<String?> _pickGalleryAssetPath() async {
    if (!mounted) return null;
    final List<AssetEntity>? picked = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(maxAssets: 1, requestType: RequestType.video),
    );
    if (picked == null || picked.isEmpty) return null;
    return _assetEntityToPath(picked.first);
  }

  Future<String?> _assetEntityToPath(AssetEntity entity) async {
    try {
      final File? origin = await entity.originFile;
      if (origin != null && await origin.exists()) {
        return origin.path;
      }
      final File? copy = await entity.file;
      if (copy != null && await copy.exists()) {
        return copy.path;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not resolve a file path for this asset.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery file error: $e')),
        );
      }
    }
    return null;
  }

  Future<void> _pickVideo() async {
    String? path;
    if (_isMobile) {
      path = await _pickGalleryAssetPath();
    } else {
      final r = await FilePicker.platform.pickFiles(type: FileType.video);
      path = r?.files.single.path;
    }
    if (path == null) return;
    setState(() {
      _path = path;
      _clearAfterPick();
    });
    await _runProbe();
  }

  Future<void> _runProbe() async {
    final path = _path;
    if (path == null) return;
    try {
      final probe = await Media.probe(path);
      setState(() {
        _probe = probe;
        _error = null;
        _syncPresetWithProbe(probe);
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<String> _thumbnailOutputPath(String sourcePath) async {
    final ext = thumbnailFormatFileExt(_thumbFormat);
    final base = p.basenameWithoutExtension(sourcePath);
    if (_isMobile) {
      final dir = await getTemporaryDirectory();
      return p.join(dir.path, '${base}_thumb.$ext');
    }
    return p.join(p.dirname(sourcePath), '${base}_thumb.$ext');
  }

  Future<void> _runThumb() async {
    final path = _path;
    if (path == null) return;
    final maxEdge = _resolvedThumbMaxEdge();
    if (maxEdge == null) {
      setState(() {
        _error = _thumbWidthPreset == ThumbnailWidthPreset.original
            ? 'Thumbnail: original width needs probe dimensions, or pick Custom with a pixel value.'
            : 'Thumbnail: invalid custom width (use a positive integer).';
      });
      return;
    }
    final out = await _thumbnailOutputPath(path);
    try {
      final f = File(out);
      if (await f.exists()) await f.delete();
      final saved = await Media.thumbnailSaveToPath(
        path: path,
        outputPath: out,
        timeSec: 1.0,
        maxEdge: maxEdge,
        format: _thumbFormat,
      );
      final bytes = await File(saved).readAsBytes();
      setState(() {
        _thumbPath = saved;
        _thumbBytes = bytes;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<String> _transcodeOutputPath(String sourcePath, VideoPreset preset) async {
    var base = p.basenameWithoutExtension(sourcePath);
    if (base.isEmpty) base = 'out';
    if (_isMobile || sourcePath.startsWith('content://')) {
      final dir = await getTemporaryDirectory();
      return p.join(dir.path, '${base}_${preset.name}.mp4');
    }
    return p.join(p.dirname(sourcePath), '${base}_${preset.name}.mp4');
  }

  Future<void> _runTranscode() async {
    final path = _path;
    final probe = _probe;
    final preset = _selectedPreset;
    if (path == null || probe == null || preset == null) return;
    final out = await _transcodeOutputPath(path, preset);
    if (File(out).existsSync()) await File(out).delete();

    _transcodeProgressTimer?.cancel();
    final eta = estimateEncodeWallClock(probe: probe, preset: preset);
    final estimateMs = eta.estimated.inMilliseconds;
    final useTimeBasedProgress = estimateMs > 0;

    setState(() {
      _busy = true;
      _progress = 0;
      _progressMsg = '';
      _error = null;
      _transcodeEta = eta;
      _transcodePastEstimate = false;
    });

    final sw = Stopwatch()..start();

    if (useTimeBasedProgress) {
      void tickTimeProgress() {
        if (!mounted || !_busy) return;
        final elapsed = sw.elapsedMilliseconds;
        if (elapsed >= estimateMs) {
          if (!_transcodePastEstimate) {
            setState(() => _transcodePastEstimate = true);
          }
        } else {
          setState(() {
            _transcodePastEstimate = false;
            _progress = (elapsed / estimateMs).clamp(0.0, 1.0);
          });
        }
      }

      _transcodeProgressTimer = Timer.periodic(
        const Duration(milliseconds: 120),
        (_) => tickTimeProgress(),
      );
      tickTimeProgress();
    }

    try {
      final stream = Media.transcodeVideoStream(
        inputPath: path,
        outputPath: out,
        videoBitrateKbps: presetVideoBitrateBps(preset) ~/ 1000,
        maxWidth: presetMaxLongEdge(preset),
      );
      DateTime? lastUi;
      await for (final TranscodeProgress ev in stream) {
        if (useTimeBasedProgress) {
          if (mounted) {
            setState(() => _progressMsg = ev.message ?? '');
          }
        } else {
          final now = DateTime.now();
          final prevUi = lastUi;
          final dt = prevUi == null ? 9999 : now.difference(prevUi).inMilliseconds;
          if (dt >= 120 || ev.fraction >= 0.999) {
            lastUi = now;
            if (mounted) {
              setState(() {
                _progress = ev.fraction;
                _progressMsg = ev.message ?? '';
              });
              await Future<void>.delayed(Duration.zero);
            }
          }
        }
      }
      sw.stop();
      _transcodeProgressTimer?.cancel();
      _transcodeProgressTimer = null;
      final len = await File(out).length();
      if (mounted) {
        if (!mounted) return;
        setState(() {
          _progress = 1.0;
          _transcodePastEstimate = false;
          _lastTranscodePath = out;
          _lastTranscodeBytes = len;
          _lastTranscodeWallMs = sw.elapsedMilliseconds;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wrote $out')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _progress = 0;
          _transcodePastEstimate = false;
        });
      }
    } finally {
      _transcodeProgressTimer?.cancel();
      _transcodeProgressTimer = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _transcodeEta = null;
          _transcodePastEstimate = false;
        });
      }
    }
  }

  Future<void> _runTimeline() async {
    final path = _path;
    if (path == null) return;
    final maxEdge = _resolvedTimelineMaxEdge();
    if (maxEdge == null) {
      setState(() {
        _error = _timelineWidthPreset == ThumbnailWidthPreset.original
            ? 'Timeline: original width needs probe dimensions, or pick Custom with a pixel value.'
            : 'Timeline: invalid custom width (use a positive integer).';
      });
      return;
    }
    final n = int.tryParse(_timelineCountCtrl.text.trim());
    if (n == null || n < 1) {
      setState(() => _error = 'Timeline: need a positive frame count.');
      return;
    }
    setState(() {
      _timelineBusy = true;
      _timelineFrames.clear();
      _error = null;
    });
    try {
      final stream = Media.timelineThumbnailsStream(
        path: path,
        frameCount: n,
        maxEdge: maxEdge,
        format: _timelineFormat,
      );
      DateTime? lastTimelineUi;
      await for (final TimelineThumbnail frame in stream) {
        if (!mounted) break;
        _timelineFrames.add(frame);
        final now = DateTime.now();
        final prevTl = lastTimelineUi;
        final dt = prevTl == null ? 9999 : now.difference(prevTl).inMilliseconds;
        if (dt >= 80) {
          lastTimelineUi = now;
          setState(() {});
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _timelineBusy = false);
    }
  }

  void _openThumbViewer() {
    final b = _thumbBytes;
    if (b == null) return;
    showImageBytesViewer(
      context,
      bytes: b,
      title: 'Thumbnail (${thumbnailWidthPresetLabel(_thumbWidthPreset)})',
      format: _thumbFormat,
      onExport: () => shareOrRevealBytes(
        context,
        bytes: b,
        basename: 'video_thumb',
        format: _thumbFormat,
        dialogTitle: 'Thumbnail export',
      ),
    );
  }

  String _presetCompressedSizeLine(VideoProbe probe, VideoPreset pr) {
    final est = estimateCompressedSize(probe: probe, preset: pr);
    return '$pr → ~${formatAdaptiveFileSize(est.estimatedBytes)} (${est.confidence.name})';
  }

  void _openTimelineFrameViewer(TimelineThumbnail frame) {
    showImageBytesViewer(
      context,
      bytes: frame.imageBytes,
      title:
          'Timeline #${frame.index} @ ${frame.timeSec.toStringAsFixed(2)} s '
          '· ${formatAdaptiveFileSize(frame.imageBytes.length)} · '
          '${_formatShortLabel(_timelineFormat)}',
      format: _timelineFormat,
      onExport: () => shareOrRevealBytes(
        context,
        bytes: frame.imageBytes,
        basename: 'timeline_${frame.index}',
        format: _timelineFormat,
        dialogTitle: 'Timeline frame ${frame.index}',
      ),
    );
  }

  Future<void> _exportAllTimelineFrames() async {
    if (_timelineFrames.isEmpty) return;
    setState(() {
      _timelineExportAllBusy = true;
      _error = null;
    });
    try {
      final baseDir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final folder = Directory(p.join(baseDir.path, 'media_timeline_$stamp'));
      await folder.create(recursive: true);
      final ext = thumbnailFormatFileExt(_timelineFormat);
      final paths = <String>[];
      for (final fr in _timelineFrames) {
        final safeT = fr.timeSec.toStringAsFixed(2).replaceAll('.', '_');
        final name = 'frame_${fr.index}_${safeT}s.$ext';
        final file = File(p.join(folder.path, name));
        await file.writeAsBytes(fr.imageBytes);
        paths.add(file.path);
      }
      if (!mounted) return;
      await shareOrRevealFilesBatch(
        context,
        filePaths: paths,
        subject: '${paths.length} timeline frames',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isMobile
                  ? 'Sharing ${paths.length} frames…'
                  : 'Opened folder with ${paths.length} frames: ${folder.path}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Export all timeline frames failed: $e');
    } finally {
      if (mounted) setState(() => _timelineExportAllBusy = false);
    }
  }

  Widget _pathAndPlayRow({
    required BuildContext context,
    required String label,
    required String path,
    String? fileSizeLine,
    required VoidCallback onPlay,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              revealableFilePathText(
                context,
                path: path,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (fileSizeLine != null) ...[
                const SizedBox(height: 4),
                Text(
                  fileSizeLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                        fontSize: 11,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        VideoPlayLaunchTile(
          videoPath: path,
          enabled: true,
          onOpen: onPlay,
        ),
      ],
    );
  }

  Widget _thumbnailOutputRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thumbSizeLine =
        _thumbPath != null ? tryFileSizeLabel(_thumbPath!) : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saved thumbnail path',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 2),
              _thumbPath == null
                  ? Text(
                      'Generate a thumbnail to see the file path.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.outline,
                          ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    )
                  : revealableFilePathText(
                      context,
                      path: _thumbPath!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 4,
                    ),
              if (thumbSizeLine != null) ...[
                const SizedBox(height: 4),
                Text(
                  thumbSizeLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                        fontSize: 11,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (_thumbBytes != null) ...[
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openThumbViewer,
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: _memoryImagePreview(
                      _thumbBytes!,
                      fit: BoxFit.cover,
                      imageFormat: _thumbFormat,
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Preview',
                    icon: const Icon(Icons.zoom_in, size: 20),
                    onPressed: _openThumbViewer,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: _isMobile ? 'Export' : 'Show in explorer',
                    icon: const Icon(Icons.ios_share_outlined, size: 20),
                    onPressed: _thumbPath == null
                        ? null
                        : () => shareOrRevealFile(
                              context,
                              _thumbPath!,
                              subject: 'Saved thumbnail file',
                            ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final probe = _probe;
    final fittingPresets =
        probe == null ? <VideoPreset>[] : presetsFittingSource(probe).toList();
    final videoPath = _path;
    final originalVideoSizeLine =
        videoPath != null ? tryFileSizeLabel(videoPath) : null;
    final transcodedFileSizeLine = _lastTranscodePath != null
        ? (_lastTranscodeBytes != null
            ? 'File size: ${formatAdaptiveFileSize(_lastTranscodeBytes!)}'
            : tryFileSizeLabel(_lastTranscodePath!))
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _isMobile
              ? 'Pick a video. Use Play to open fullscreen (bottom sheet). Thumbnail vs timeline each have their own format and width.'
              : 'Pick a video. Play opens a full player in a new window; on phones it opens as a bottom sheet.',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _pickVideo,
          child: const Text('Pick video'),
        ),
        if (_path != null || _error != null || probe != null)
          const ExampleSectionDivider(),
        if (_path != null) ...[
          const SizedBox(height: 10),
          _pathAndPlayRow(
            context: context,
            label: 'Original file',
            path: _path!,
            fileSizeLine: originalVideoSizeLine,
            onPlay: () => presentLocalVideoPlayer(
              context,
              path: _path!,
              title: 'Original video',
            ),
          ),
        ],
        if (_error != null)
          Text(
            'Error: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (probe != null) ...[
          if (_path != null || _error != null) const ExampleSectionDivider(),
          Text(
            'Selected video & preset estimates',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final useRow = constraints.maxWidth >= 520;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Source',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Duration: ${probe.durationMs != null ? "${probe.durationMs} ms" : "—"}',
                  ),
                  Text(
                    'Size: ${probe.width ?? "?"}x${probe.height ?? "?"} '
                    '(source long edge: ${sourceLongEdge(probe)} px)',
                  ),
                  Text('Video bitrate (bps): ${probe.videoBitrate ?? "unknown"}'),
                  Text('Video codec: ${probe.videoCodec ?? "?"}'),
                  Text('Audio codec: ${probe.audioCodec ?? "?"}'),
                ],
              );
              final estimates = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimates (all presets)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  for (final pr in VideoPreset.values)
                    Text(_presetCompressedSizeLine(probe, pr)),
                ],
              );
              if (useRow) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 20),
                    Expanded(child: estimates),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 12),
                  estimates,
                ],
              );
            },
          ),
        ],
        if (_path != null) ...[
          const ExampleSectionDivider(),
          Text('Thumbnail', style: Theme.of(context).textTheme.titleSmall),
          Row(
            children: [
              const Text('Format: '),
              DropdownButton<ThumbnailFormat>(
                value: _thumbFormat,
                items: const [
                  DropdownMenuItem(value: ThumbnailFormat.png, child: Text('PNG')),
                  DropdownMenuItem(value: ThumbnailFormat.jpeg, child: Text('JPEG')),
                  DropdownMenuItem(value: ThumbnailFormat.webp, child: Text('WebP')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _thumbFormat = v);
                },
              ),
            ],
          ),
          Text(
            'Thumbnail width (max long edge)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          DropdownButton<ThumbnailWidthPreset>(
            isExpanded: true,
            value: _thumbWidthPreset,
            items: [
              for (final wp in ThumbnailWidthPreset.values)
                DropdownMenuItem(
                  value: wp,
                  child: Text(
                    thumbnailWidthPresetLabel(wp),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _thumbWidthPreset = v);
            },
          ),
          if (_thumbWidthPreset == ThumbnailWidthPreset.custom)
            TextField(
              controller: _thumbCustomWidthCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Thumbnail custom max long edge (px)',
                isDense: true,
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _runThumb,
            child: const Text('Save thumbnail'),
          ),
          const SizedBox(height: 10),
          _thumbnailOutputRow(context),
        ],
        if (probe != null) ...[
          const ExampleSectionDivider(),
          Text(
            'Transcode preset (downscale only)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Larger targets are listed for reference but cannot be selected.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 6),
          DropdownButton<VideoPreset>(
            isExpanded: true,
            hint: Text(
              fittingPresets.isEmpty
                  ? 'No preset ≤ source long edge — source is smaller than 360p cap'
                  : 'Choose preset',
            ),
            value: _selectedPreset != null && fittingPresets.contains(_selectedPreset!)
                ? _selectedPreset
                : null,
            items: [
              for (final pr in VideoPreset.values)
                DropdownMenuItem(
                  value: pr,
                  enabled: _transcodePresetEnabled(probe, pr),
                  child: Text(
                    '$pr · max ${presetMaxLongEdge(pr)} px · '
                    '${presetVideoBitrateBps(pr) ~/ 1000} kb/s video'
                    '${_transcodePresetEnabled(probe, pr) ? '' : ' · would upscale'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null &&
                  fittingPresets.isNotEmpty &&
                  _transcodePresetEnabled(probe, v)) {
                setState(() => _selectedPreset = v);
              }
            },
          ),
          if (_selectedPreset != null) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final est = estimateCompressedSize(
                  probe: probe,
                  preset: _selectedPreset!,
                );
                return Text(
                  'Estimated output size: ~${formatAdaptiveFileSize(est.estimatedBytes)} '
                  '(${est.confidence.name})',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final eta = estimateEncodeWallClock(
                  probe: probe,
                  preset: _selectedPreset!,
                );
                return Text(
                  'ETA for this preset: ~${eta.estimatedSeconds.toStringAsFixed(0)} s wall time '
                  '(${eta.confidence.name} confidence)',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
          ],
          if (Platform.isAndroid) ...[
            const SizedBox(height: 4),
            Text(
              'Android: Media3 re-encode when the media plugin is present; otherwise remux fallback.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: (_busy || _selectedPreset == null) ? null : _runTranscode,
            child: Text('Transcode (${_selectedPreset?.name ?? "—"})'),
          ),
          if (_lastTranscodePath != null) ...[
            const SizedBox(height: 8),
            if (_lastTranscodeBytes != null && _lastTranscodeWallMs != null)
              Text(
                'Last transcode: ${formatAdaptiveFileSize(_lastTranscodeBytes!)} · '
                'wall ${_lastTranscodeWallMs!} ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 10),
            _pathAndPlayRow(
              context: context,
              label: 'Transcoded file',
              path: _lastTranscodePath!,
              fileSizeLine: transcodedFileSizeLine,
              onPlay: () => presentLocalVideoPlayer(
                context,
                path: _lastTranscodePath!,
                title: 'Transcoded video',
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final eta = _transcodeEta;
                final timeBased =
                    eta != null && eta.estimated.inMilliseconds > 0;
                if (timeBased) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_transcodePastEstimate)
                        const LinearProgressIndicator()
                      else
                        LinearProgressIndicator(
                          value: _progress.clamp(0.0, 1.0),
                        ),
                      Text(
                        _transcodePastEstimate
                            ? 'Past ~${eta.estimatedSeconds.toStringAsFixed(0)} s estimate — still encoding…'
                            : '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}% of ~${eta.estimatedSeconds.toStringAsFixed(0)} s '
                                '(${eta.confidence.name} confidence)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_progressMsg.isNotEmpty) Text(_progressMsg),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                    ),
                    Text(
                      'No time estimate (unknown duration) — native progress when available.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    if (_progressMsg.isNotEmpty) Text(_progressMsg),
                  ],
                );
              },
            ),
          ],
          const ExampleSectionDivider(),
          Text(
            'Timeline (streamed thumbnails)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Timeline encoding is independent of the single-frame thumbnail above. Format and max long edge are on one row; each tile shows encoded size and format.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Format',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<ThumbnailFormat>(
                      isExpanded: true,
                      value: _timelineFormat,
                      items: const [
                        DropdownMenuItem(
                          value: ThumbnailFormat.png,
                          child: Text('PNG'),
                        ),
                        DropdownMenuItem(
                          value: ThumbnailFormat.jpeg,
                          child: Text('JPEG'),
                        ),
                        DropdownMenuItem(
                          value: ThumbnailFormat.webp,
                          child: Text('WebP'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _timelineFormat = v;
                          _timelineFrames.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Max long edge',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<ThumbnailWidthPreset>(
                      isExpanded: true,
                      value: _timelineWidthPreset,
                      items: [
                        for (final wp in ThumbnailWidthPreset.values)
                          DropdownMenuItem(
                            value: wp,
                            child: Text(
                              thumbnailWidthPresetLabel(wp),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _timelineWidthPreset = v;
                          _timelineFrames.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_timelineWidthPreset == ThumbnailWidthPreset.custom)
            TextField(
              controller: _timelineCustomWidthCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Timeline custom max long edge (px)',
                isDense: true,
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Frame count: '),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _timelineCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _timelineBusy ? null : _runTimeline,
                child: const Text('Generate timeline'),
              ),
            ],
          ),
          if (_timelineBusy) const LinearProgressIndicator(),
          if (_timelineFrames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final totalBytes = _timelineFrames.fold<int>(
                  0,
                  (a, f) => a + f.imageBytes.length,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_timelineFrames.length} frames',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                                Text(
                                  ' · ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                                Text(
                                  _formatShortLabel(_timelineFormat),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                                Text(
                                  ' · ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                                Text(
                                  'total ${formatAdaptiveFileSize(totalBytes)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: (_timelineBusy || _timelineExportAllBusy)
                              ? null
                              : _exportAllTimelineFrames,
                          child: _timelineExportAllBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _isMobile
                                      ? 'Export all'
                                      : 'Export all (open folder)',
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 124,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _timelineFrames.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final fr = _timelineFrames[i];
                          final sz = formatAdaptiveFileSize(fr.imageBytes.length);
                          final fmt = _formatShortLabel(_timelineFormat);
                          return SizedBox(
                            width: 100,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Material(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => _openTimelineFrameViewer(fr),
                                      child: Tooltip(
                                        message:
                                            '#${fr.index} @ ${fr.timeSec.toStringAsFixed(2)} s · $sz · $fmt — tap to preview',
                                        child: _memoryImagePreview(
                                          fr.imageBytes,
                                          fit: BoxFit.cover,
                                          imageFormat: _timelineFormat,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        sz,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      ' · ',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                          ),
                                    ),
                                    Text(
                                      fmt,
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ],
    );
  }
}
