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

class ImageExampleTab extends StatefulWidget {
  const ImageExampleTab({super.key});

  @override
  State<ImageExampleTab> createState() => _ImageExampleTabState();
}

class _ImageExampleTabState extends State<ImageExampleTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _path;
  VideoProbe? _probe;
  Uint8List? _thumbBytes;
  String? _thumbPath;
  String? _error;

  ThumbnailFormat _thumbFormat = ThumbnailFormat.png;
  ThumbnailWidthPreset _widthPreset = ThumbnailWidthPreset.medium;
  final TextEditingController _customWidthCtrl = TextEditingController(text: '720');

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void dispose() {
    _customWidthCtrl.dispose();
    super.dispose();
  }

  void _clearAfterPick() {
    _probe = null;
    _thumbBytes = null;
    _thumbPath = null;
    _error = null;
  }

  int? _resolvedMaxEdge() {
    return resolveThumbnailMaxEdge(
      preset: _widthPreset,
      probe: _probe,
      customPixelsText: _customWidthCtrl.text,
    );
  }

  Widget _memoryImagePreview(Uint8List bytes, {double? height, BoxFit? fit}) {
    return Image.memory(
      bytes,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Preview could not decode (${_thumbFormat.name}). Try PNG or JPEG.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      ),
    );
  }

  Future<String?> _pickGalleryAssetPath() async {
    if (!mounted) return null;
    final List<AssetEntity>? picked = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(maxAssets: 1, requestType: RequestType.image),
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

  Future<void> _pickImage() async {
    String? path;
    if (_isMobile) {
      path = await _pickGalleryAssetPath();
    } else {
      final r = await FilePicker.platform.pickFiles(type: FileType.image);
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
    final maxEdge = _resolvedMaxEdge();
    if (maxEdge == null) {
      setState(() {
        _error = _widthPreset == ThumbnailWidthPreset.original
            ? 'Original width needs probe dimensions, or pick Custom with a pixel value.'
            : 'Invalid custom width (use a positive integer).';
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
        timeSec: 0,
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

  void _openOriginalViewer() {
    final path = _path;
    if (path == null) return;
    showImageFileViewer(
      context,
      filePath: path,
      title: 'Original image',
      onExport: () => shareOrRevealFile(context, path, subject: 'Original image'),
    );
  }

  Widget _imagePathPreviewRow({
    required BuildContext context,
    required String label,
    required String path,
    bool pathIsPlaceholder = false,
    String? fileSizeLine,
    required Widget child,
    VoidCallback? onPreviewTap,
    VoidCallback? onExport,
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
              pathIsPlaceholder
                  ? Text(
                      path,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.outline,
                          ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    )
                  : revealableFilePathText(
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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPreviewTap,
                child: SizedBox(width: 76, height: 76, child: child),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Preview',
                  icon: const Icon(Icons.zoom_in, size: 20),
                  onPressed: onPreviewTap,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: _isMobile ? 'Export' : 'Show in explorer',
                  icon: const Icon(Icons.ios_share_outlined, size: 20),
                  onPressed: onExport,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _openThumbViewer() {
    final b = _thumbBytes;
    if (b == null) return;
    showImageBytesViewer(
      context,
      bytes: b,
      title: 'Transcoded thumbnail (${thumbnailWidthPresetLabel(_widthPreset)})',
      format: _thumbFormat,
      onExport: () => shareOrRevealBytes(
        context,
        bytes: b,
        basename: 'image_thumb',
        format: _thumbFormat,
        dialogTitle: 'Thumbnail export',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final probe = _probe;
    final path = _path;
    final originalSizeLine = path != null ? tryFileSizeLabel(path) : null;
    final thumbSizeLine =
        _thumbPath != null ? tryFileSizeLabel(_thumbPath!) : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _isMobile
              ? 'Still images: generate a downscaled thumbnail with the same width presets as the Video tab. Pinch-zoom in preview; export shares on mobile or reveals files on desktop.'
              : 'Pick an image, choose a thumbnail width tier (documented below), then compare the original file with the generated thumbnail side by side.',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _pickImage,
          child: const Text('Pick image'),
        ),
        if (path != null || _error != null || probe != null)
          const ExampleSectionDivider(),
        if (path != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Path: ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Expanded(
                child: revealableFilePathText(
                  context,
                  path: path,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 5,
                ),
              ),
            ],
          ),
          if (originalSizeLine != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                originalSizeLine,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 11,
                    ),
              ),
            ),
        ],
        if (_error != null)
          Text(
            'Error: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (probe != null) ...[
          if (path != null || _error != null) const ExampleSectionDivider(),
          Text(
            'Size: ${probe.width ?? "?"}x${probe.height ?? "?"} '
            '(source long edge: ${sourceLongEdge(probe)} px)',
          ),
          Text('Kind: ${probe.videoCodec ?? "image"}'),
        ],
        if (path != null) ...[
          const ExampleSectionDivider(),
          Text('Thumbnail', style: Theme.of(context).textTheme.titleSmall),
          Text(
            'Width presets match the Video tab. [Original] uses the probed long edge so the raster is not scaled below the source (when dimensions are known).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
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
          DropdownButton<ThumbnailWidthPreset>(
            isExpanded: true,
            value: _widthPreset,
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
              if (v != null) setState(() => _widthPreset = v);
            },
          ),
          if (_widthPreset == ThumbnailWidthPreset.custom)
            TextField(
              controller: _customWidthCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Custom max long edge (px)',
                isDense: true,
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _runThumb,
            child: const Text('Generate thumbnail'),
          ),
          const ExampleSectionDivider(),
          Text('Compare', style: Theme.of(context).textTheme.titleSmall),
          Text(
            'Path on the left, preview on the right. Tap the image or zoom to open pinch-zoom.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          _imagePathPreviewRow(
            context: context,
            label: 'Original file',
            path: path,
            fileSizeLine: originalSizeLine,
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              width: 76,
              height: 76,
              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
            ),
            onPreviewTap: _openOriginalViewer,
            onExport: () => shareOrRevealFile(
              context,
              path,
              subject: 'Original image',
            ),
          ),
          const SizedBox(height: 12),
          _imagePathPreviewRow(
            context: context,
            label: 'Generated thumbnail',
            path: _thumbPath ?? 'Generate a thumbnail to see the output path.',
            pathIsPlaceholder: _thumbPath == null,
            fileSizeLine: thumbSizeLine,
            child: _thumbBytes == null
                ? Center(
                    child: Text(
                      '—',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  )
                : _memoryImagePreview(_thumbBytes!, fit: BoxFit.cover),
            onPreviewTap: _thumbBytes == null ? null : _openThumbViewer,
            onExport: _thumbPath == null
                ? null
                : () => shareOrRevealFile(
                      context,
                      _thumbPath!,
                      subject: 'Thumbnail file',
                    ),
          ),
        ],
      ],
    );
  }
}
