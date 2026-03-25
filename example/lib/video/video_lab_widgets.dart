import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media/media.dart';
import 'package:example/utils/file_utils.dart';
import 'package:example/video/video_player_screen.dart';
import 'video_lab_view_model.dart';

class FilePickerWidget extends StatelessWidget {
  final VideoLabViewModel viewModel;

  const FilePickerWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: viewModel.isInfoLoading || viewModel.isCompressing ? null : viewModel.pickVideoFile,
          icon: const Icon(Icons.video_library),
          label: const Text('Pick Video File'),
        ),
        const SizedBox(height: 20),
        if (viewModel.isInfoLoading)
          const Center(child: CircularProgressIndicator())
        else if (viewModel.selectedPath != null) ...[
          Text('Selected: ${viewModel.selectedPath}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoPath: viewModel.selectedPath!)),
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => showInExplorer(viewModel.selectedPath!),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Show in Explorer'),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class VideoMetadataWidget extends StatelessWidget {
  final VideoInfo? videoInfo;

  const VideoMetadataWidget({super.key, this.videoInfo});

  @override
  Widget build(BuildContext context) {
    if (videoInfo == null) return const SizedBox.shrink();
    final BigInt size = videoInfo!.sizeBytes;
    final String sizeStringBytes = '$size bytes';
    final String sizeStringKB = '${size.kb} KB';
    final String sizeStringMB = '${size.mb} MB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original Duration: ${videoInfo!.durationMs} ms'),
            Text('Original Resolution: ${videoInfo!.width}x${videoInfo!.height}'),
            Text('Original Size: $sizeStringBytes / $sizeStringKB / $sizeStringMB'),
            const Divider(height: 24),
            const Text(
              'Delivery estimates (analytic HD / SD)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'HD ~${videoInfo!.delivery.hd720.estimatedSizeBytes} bytes '
              '(${videoInfo!.delivery.hd720.width}x${videoInfo!.delivery.hd720.height}, '
              '${videoInfo!.delivery.hd720.videoBitrateKbps} kbps video)',
            ),
            Text(
              'SD ~${videoInfo!.delivery.sd480.estimatedSizeBytes} bytes '
              '(${videoInfo!.delivery.sd480.width}x${videoInfo!.delivery.sd480.height}, '
              '${videoInfo!.delivery.sd480.videoBitrateKbps} kbps video)',
            ),
          ],
        ),
      ),
    );
  }
}

class CompressionWidget extends StatelessWidget {
  final VideoLabViewModel viewModel;

  const CompressionWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.videoInfo == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preset Dropdown
        if (viewModel.videoInfo!.suggestions.isNotEmpty) ...[
          DropdownButtonFormField<ResolutionPreset?>(
            initialValue: viewModel.selectedPreset,
            decoration: const InputDecoration(labelText: "Quality Preset", border: OutlineInputBorder()),
            items: [
              ...viewModel.videoInfo!.suggestions.map((preset) {
                return DropdownMenuItem(
                  value: preset,
                  child: Text("${preset.name} (${preset.width}x${preset.height})"),
                );
              }),
              const DropdownMenuItem(value: null, child: Text("Custom")),
            ],
            onChanged: viewModel.onPresetChanged,
          ),
          const SizedBox(height: 10),
        ],

        // Resolution Inputs
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: viewModel.widthController,
                decoration: const InputDecoration(labelText: "Target Width"),
                keyboardType: TextInputType.number,
                enabled: viewModel.isCustom,
                onChanged: viewModel.onWidthChanged,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: viewModel.heightController,
                decoration: const InputDecoration(labelText: "Target Height"),
                keyboardType: TextInputType.number,
                enabled: viewModel.isCustom,
                onChanged: viewModel.onHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const Divider(),
        const Text("Compression Controls", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (VideoLabViewModel.platformBackendAvailable) ...[
          const Text('Processing backend', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<VideoLabBackend>(
            segments: const [
              ButtonSegment<VideoLabBackend>(
                value: VideoLabBackend.rustMedia,
                label: Text('Rust / FFmpeg'),
                icon: Icon(Icons.terminal, size: 18),
              ),
              ButtonSegment<VideoLabBackend>(
                value: VideoLabBackend.platformOs,
                label: Text('OS codecs'),
                icon: Icon(Icons.smartphone, size: 18),
              ),
            ],
            selected: {viewModel.backend},
            onSelectionChanged: (Set<VideoLabBackend> next) {
              if (next.isEmpty) return;
              viewModel.setBackend(next.first);
            },
          ),
          const SizedBox(height: 12),
        ] else
          const Text(
            'OS codec backend is available on Android, iOS, and macOS only. This device uses Rust / FFmpeg.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        if (viewModel.targetBitrateKbps != null) Text("Target: ${viewModel.targetBitrateKbps} kbps"),
        Text(
          viewModel.backend == VideoLabBackend.platformOs
              ? 'Platform path: analytic delivery estimate + Media3 (Android) / AVFoundation (Apple) transcode. '
                  'Target long edge and video bitrate match the fields above; CRF is ignored.'
              : 'Rust path: sample FFmpeg encode (bitrate-only, CRF cleared for estimate) + AAC 128k; '
                  'full encode uses your CRF when set.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: viewModel.isEstimationLoading || viewModel.isCompressing ? null : viewModel.runEstimation,
              child: viewModel.isEstimationLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Estimate Size"),
            ),
            ElevatedButton(
              onPressed: viewModel.isCompressing ? null : viewModel.runCompression,
              child: viewModel.isCompressing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Compress Video"),
            ),
          ],
        ),

        if (viewModel.estimate != null) ...[
          const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final BigInt size = viewModel.estimate!.estimatedSizeBytes;
              final String estimateSizeStringBytes = '$size bytes';
              final String estimateSizeStringKB = '${size.kb} KB';
              final String estimateSizeStringMB = '${size.mb} MB';

              final String estimateDurationString = '${viewModel.estimate!.estimatedDurationMs} ms';
              final String estimateDurationStringSec =
                  '${viewModel.estimate!.estimatedDurationMs / BigInt.from(1000)} sec';

              return Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        viewModel.backend == VideoLabBackend.platformOs
                            ? 'Estimate (platform analytic)'
                            : 'Estimate (Rust / FFmpeg sample)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Estimated New Size: $estimateSizeStringBytes / $estimateSizeStringKB / $estimateSizeStringMB",
                      ),
                      Text(
                        "Source duration (for size math): $estimateDurationString / $estimateDurationStringSec",
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],

        if (viewModel.compressionResult != null) ...[
          const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final BigInt size = viewModel.compressedSize!;
              final String compressedSizeStringBytes = '$size bytes';
              final String compressedSizeStringKB = '${size.kb} KB';
              final String compressedSizeStringMB = '${size.mb} MB';

              final outMs = viewModel.compressedOutputDurationMs!;
              final encMs = viewModel.compressionEncodeTimeMs!;
              final outSec = '${outMs / BigInt.from(1000)} sec';
              final encSec = '${encMs / BigInt.from(1000)} sec';

              return Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              viewModel.compressionResult!,
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (viewModel.compressedVideoPath != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VideoPlayerScreen(videoPath: viewModel.compressedVideoPath!),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play'),
                          ),
                          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () {
                                if (viewModel.compressedVideoPath != null) {
                                  showInExplorer(viewModel.compressedVideoPath!);
                                }
                              },
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Show in Explorer'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(),
                      Text(
                        "Compressed Size: $compressedSizeStringBytes / $compressedSizeStringKB / $compressedSizeStringMB",
                      ),
                      const SizedBox(height: 8),
                      Text("Output duration (file): $outMs ms / $outSec"),
                      Text("Encode time (wall clock): $encMs ms / $encSec"),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class TimelineWidget extends StatelessWidget {
  final VideoLabViewModel viewModel;

  const TimelineWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.videoInfo == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text("Timeline Generation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: viewModel.numThumbnailsController,
                decoration: const InputDecoration(labelText: "Number of Thumbnails"),
                keyboardType: TextInputType.number,
                enabled: !viewModel.generatingTimeline,
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: viewModel.generatingTimeline ? null : viewModel.runTimelineGeneration,
              child: viewModel.generatingTimeline
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Generate Timeline"),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (viewModel.timelineThumbnails.isNotEmpty)
          Column(
            children: [
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: viewModel.timelineThumbnails.length,
                  itemBuilder: (context, index) {
                    final path = viewModel.timelineThumbnails[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => showInExplorer(path), // Tap to open
                        onSecondaryTap: () => showInExplorer(path), // Right click
                        onLongPress: () => showInExplorer(path), // Long press
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                              child: Image.file(File(path), height: 100, fit: BoxFit.contain),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  // Open the folder containing the first thumbnail
                  if (viewModel.timelineThumbnails.isNotEmpty) {
                    showInExplorer(viewModel.timelineThumbnails.first);
                  }
                },
                icon: const Icon(Icons.folder),
                label: const Text("Show Output Folder"),
              ),
            ],
          ),
      ],
    );
  }
}

class ThumbnailSeekerWidget extends StatelessWidget {
  final VideoLabViewModel viewModel;

  const ThumbnailSeekerWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.videoInfo == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 20),
        if (viewModel.videoInfo!.durationMs > BigInt.zero) ...[
          Text("Generate thumbnail at: ${viewModel.value.toInt()} ms"),
          Slider(
            value: viewModel.value,
            min: 0,
            max: viewModel.videoInfo!.durationMs.toDouble(),
            onChanged: (v) {
              viewModel.value = v;
            },
            onChangeEnd: (v) {
              viewModel.generateThumbnail();
            },
          ),
        ],

        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
          child: InkWell(
            onTap: () => viewModel.thumbnailPath != null ? showInExplorer(viewModel.thumbnailPath!) : null,
            child: SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (viewModel.thumbnailPath != null)
                    Image.file(File(viewModel.thumbnailPath!), height: 200, fit: BoxFit.contain),
                  if (viewModel.isThumbnailLoading) const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => showInExplorer(viewModel.thumbnailPath!),
          icon: const Icon(Icons.folder_open),
          label: const Text('Show in Explorer'),
        ),
      ],
    );
  }
}
