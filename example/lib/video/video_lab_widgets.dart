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
          onPressed: viewModel.isInfoLoading || viewModel.isCompressing ? null : viewModel.pickFile,
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
        if (viewModel.targetBitrateKbps != null) Text("Target: ${viewModel.targetBitrateKbps} kbps"),
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
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        "Estimated New Size: $estimateSizeStringBytes / $estimateSizeStringKB / $estimateSizeStringMB",
                      ),
                      Text("Estimated Duration: $estimateDurationString / $estimateDurationStringSec"),
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

              final String compressedDurationString = '${viewModel.compressedDuration!} ms';
              final String compressedDurationStringSec = '${viewModel.compressedDuration! / BigInt.from(1000)} sec';

              return Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: .start,
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
                      Text("Compressed Duration: $compressedDurationString / $compressedDurationStringSec"),
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
        Visibility(
          visible: viewModel.isThumbnailLoading,
          child: const Center(child: CircularProgressIndicator()),
        ),

        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
          child: InkWell(
            onTap: () => viewModel.thumbnailPath != null ? showInExplorer(viewModel.thumbnailPath!) : null,
            child: SizedBox(
              height: 200,
              child: viewModel.thumbnailPath != null
                  ? Image.file(File(viewModel.thumbnailPath!), height: 200, fit: BoxFit.contain)
                  : const SizedBox.shrink(),
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
