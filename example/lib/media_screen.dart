import 'dart:io';

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media/media.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  String? _selectedPath;
  String? _thumbnailOutputPath;
  String? _compressedOutputPath;
  VideoInfo? _videoInfo;
  String? _thumbnailPath;
  bool _loading = false;
  String? _error;
  CompressionEstimate? _estimate;
  bool _compressing = false;
  String? _compressionResult;
  double _value = 0;
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  ResolutionPreset? _selectedPreset;
  bool _isCustom = false;
  int? _targetBitrateKbps;
  int? _targetCrf;

  // Timeline State
  final TextEditingController _numThumbnailsController = TextEditingController(
    text: "10",
  );
  final List<String> _timelineThumbnails = [];
  bool _generatingTimeline = false;
  StreamSubscription<String>? _timelineSubscription;

  @override
  void initState() {
    super.initState();
    Media.init();

    getApplicationDocumentsDirectory().then((value) {
      setState(() {
        _thumbnailOutputPath = join(value.path, 'thumbnails');
        _compressedOutputPath = join(value.path, 'compressed');
      });
    });
  }

  @override
  void dispose() {
    _numThumbnailsController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _timelineSubscription?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedPath = result.files.single.path;
          _videoInfo = null;
          _thumbnailPath = null;
          _error = null;
          _value = 0;
          _estimate = null;
          _estimate = null;
          _compressionResult = null;
          _selectedPreset = null;
          _isCustom = false;
          _timelineThumbnails.clear();
          _generatingTimeline = false;
          _targetBitrateKbps = null;
          _targetCrf = null;
          _widthController.clear();
          _heightController.clear();
        });
        await _loadInfo();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _loadInfo() async {
    if (_selectedPath == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final VideoInfo info = await getVideoInfo(path: _selectedPath!);
      setState(() {
        _videoInfo = info;
        if (info.suggestions.isNotEmpty) {
          _selectedPreset = info.suggestions.first;
          _widthController.text = _selectedPreset!.width.toString();
          _heightController.text = _selectedPreset!.height.toString();
          _targetBitrateKbps = (_selectedPreset!.bitrate ~/ BigInt.from(1000))
              .toInt();
          _targetCrf = _selectedPreset!.crf;
          _isCustom = false;
        }
      });
    } catch (e) {
      print(e);
      setState(() {
        _error = "Error loading info: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _generateThumbnail() async {
    if (_selectedPath == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _thumbnailPath = null;
    });

    try {
      final bytes = await generateVideoThumbnail(
        path: _selectedPath!,
        outputPath: _thumbnailOutputPath!,
        params: VideoThumbnailParams(timeMs: BigInt.from(_value)),
      );
      setState(() {
        _thumbnailPath = bytes;
      });
    } catch (e) {
      setState(() {
        _error = "Error generating thumbnail: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _runEstimation() async {
    if (_selectedPath == null || _videoInfo == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _estimate = null;
    });

    final int? width = int.tryParse(_widthController.text);
    final int? height = int.tryParse(_heightController.text);
    // Use target bitrate from state, default to 1000 if null
    final int targetBitrateKbps = _targetBitrateKbps ?? 1000;
    final int targetCrf = _targetCrf ?? 28;
    final String preset = "veryfast";

    try {
      final estimate = await estimateCompression(
        path: _selectedPath!,
        tempOutputPath: _compressedOutputPath!,
        params: CompressParams(
          targetBitrateKbps: targetBitrateKbps,
          width: width,
          height: height,
          preset: preset,
          crf: targetCrf,
        ),
      );
      setState(() {
        _estimate = estimate;
      });
    } catch (e) {
      setState(() {
        _error = "Estimation failed: $e";
        print(_error);
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _runCompression() async {
    if (_selectedPath == null) return;
    setState(() {
      _compressing = true;
      _error = null;
      _compressionResult = null;
    });

    int? w = int.tryParse(_widthController.text);
    int? h = int.tryParse(_heightController.text);
    final int targetBitrateKbps = _targetBitrateKbps ?? 1000;
    final int targetCrf = _targetCrf ?? 28;

    try {
      final outputPath = await compressVideo(
        path: _selectedPath!,
        outputPath: _compressedOutputPath!,
        params: CompressParams(
          targetBitrateKbps: targetBitrateKbps,
          preset: "veryfast",
          crf: targetCrf,
          width: w,
          height: h,
        ),
      );

      setState(() {
        _compressionResult = "Success! Saved to $outputPath";
      });
    } catch (e) {
      setState(() {
        _error = "Compression failed: $e";
        print(_error);
      });
    } finally {
      setState(() {
        _compressing = false;
      });
    }
  }

  Future<void> _runTimelineGeneration() async {
    if (_selectedPath == null || _generatingTimeline) return;

    final int? numThumbnails = int.tryParse(_numThumbnailsController.text);
    if (numThumbnails == null || numThumbnails <= 0) {
      setState(() {
        _error = "Invalid number of thumbnails";
      });
      return;
    }

    setState(() {
      _generatingTimeline = true;
      _timelineThumbnails.clear();
      _error = null;
    });

    try {
      final stream = generateVideoTimelineThumbnails(
        path: _selectedPath!,
        outputPath: _thumbnailOutputPath!,
        numThumbnails: numThumbnails,
        params: const ImageThumbnailParams(
          sizeType: ThumbnailSizeType.small(),
          format: OutputFormat.webp,
        ),
      );

      _timelineSubscription = stream.listen(
        (path) {
          setState(() {
            _timelineThumbnails.add(path);
          });
        },
        onError: (e) {
          setState(() {
            _error = "Timeline generation error: $e";
            _generatingTimeline = false;
          });
        },
        onDone: () {
          setState(() {
            _generatingTimeline = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = "Failed to start timeline generation: $e";
        _generatingTimeline = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media Lab')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: (_loading || _compressing) ? null : _pickFile,
              icon: const Icon(Icons.video_library),
              label: const Text('Pick Video File'),
            ),
            const SizedBox(height: 20),
            if (_loading || _compressing)
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(
                      _compressing
                          ? "Compressing... (this may take a while)"
                          : "Loading...",
                    ),
                  ],
                ),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (!(_loading || _compressing) && _error == null) ...[
              if (_selectedPath != null) ...[
                Text(
                  'Selected: $_selectedPath',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // Preset Dropdown
                if (_videoInfo != null &&
                    _videoInfo!.suggestions.isNotEmpty) ...[
                  DropdownButtonFormField<ResolutionPreset?>(
                    initialValue: _selectedPreset,
                    decoration: const InputDecoration(
                      labelText: "Quality Preset",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      // Presets
                      ..._videoInfo!.suggestions.map((preset) {
                        return DropdownMenuItem(
                          value: preset,
                          child: Text(
                            "${preset.name} (${preset.width}x${preset.height})",
                          ),
                        );
                      }),
                      // Custom Option
                      const DropdownMenuItem(
                        value: null,
                        child: Text("Custom"),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value != null) {
                          // Preset Selected
                          _selectedPreset = value;
                          _isCustom = false;
                          _widthController.text = value.width.toString();
                          _heightController.text = value.height.toString();
                          // Handle BigInt bitrate
                          _targetBitrateKbps =
                              (value.bitrate ~/ BigInt.from(1000)).toInt();
                          _targetCrf = value.crf;
                        } else {
                          // Custom Selected
                          _selectedPreset = null;
                          _isCustom = true;
                          if (_widthController.text.isEmpty) {
                            _widthController.text = _videoInfo!.width
                                .toString();
                            _heightController.text = _videoInfo!.height
                                .toString();
                            _targetBitrateKbps = 1000;
                            _targetCrf = 28;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 10),

                // Resolution Inputs
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _widthController,
                        decoration: const InputDecoration(
                          labelText: "Target Width",
                        ),
                        keyboardType: TextInputType.number,
                        enabled: _isCustom,
                        onChanged: (val) {
                          if (val.isNotEmpty && _videoInfo != null) {
                            final w = int.tryParse(val);
                            if (w != null && w > 0) {
                              // Calculate height to maintain aspect ratio
                              final ratio =
                                  _videoInfo!.height / _videoInfo!.width;
                              final h = (w * ratio).round();
                              // Ensure even
                              _heightController.text = (h & ~1).toString();
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(
                      width: 10,
                    ), // Added spacing between text fields
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        decoration: const InputDecoration(
                          labelText: "Target Height",
                        ),
                        keyboardType: TextInputType.number,
                        enabled: _isCustom,
                        onChanged: (val) {
                          if (val.isNotEmpty && _videoInfo != null) {
                            final h = int.tryParse(val);
                            if (h != null && h > 0) {
                              // Calculate width to maintain aspect ratio
                              final ratio =
                                  _videoInfo!.width / _videoInfo!.height;
                              final w = (h * ratio).round();
                              // Ensure even
                              _widthController.text = (w & ~1).toString();
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (_videoInfo != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Original Duration: ${_videoInfo!.durationMs} ms'),
                        Text(
                          'Original Resolution: ${_videoInfo!.width}x${_videoInfo!.height}',
                        ),
                        Text('Original Size: ${_videoInfo!.sizeBytes} bytes'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Compression Controls
                const Divider(),
                const Text(
                  "Compression Controls",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_targetBitrateKbps != null)
                  Text("Target: $_targetBitrateKbps kbps"),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _runEstimation,
                      child: const Text("Estimate Size"),
                    ),
                    ElevatedButton(
                      onPressed: _runCompression,
                      child: const Text("Compress Video"),
                    ),
                  ],
                ),

                if (_estimate != null) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Estimated New Size: ${_estimate!.estimatedSizeBytes} bytes",
                          ),
                          Text(
                            "Estimated Duration: ${_estimate!.estimatedDurationMs} ms",
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_compressionResult != null) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _compressionResult!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                const Divider(),

                // Timeline Generation
                const Text(
                  "Timeline Generation",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _numThumbnailsController,
                        decoration: const InputDecoration(
                          labelText: "Number of Thumbnails",
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_generatingTimeline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: (_generatingTimeline)
                          ? null
                          : _runTimelineGeneration,
                      child: Text(
                        _generatingTimeline
                            ? "Generating..."
                            : "Generate Timeline",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_timelineThumbnails.isNotEmpty)
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _timelineThumbnails.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                ),
                                child: Image.file(
                                  File(_timelineThumbnails[index]),
                                  height: 100,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const Divider(),

                // Slider and Thumbnail
                const SizedBox(height: 20),
                if (_videoInfo!.durationMs > BigInt.zero) ...[
                  Text("Seek Value: ${_value.toInt()} ms"),
                  Slider(
                    value: _value,
                    min: 0,
                    max: _videoInfo!.durationMs.toDouble(),
                    onChanged: (v) {
                      setState(() {
                        _value = v;
                      });
                    },
                    onChangeEnd: (v) {
                      _generateThumbnail();
                    },
                  ),
                ],
                if (_thumbnailPath != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Image.file(
                      File(_thumbnailPath!),
                      height: 200,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
                const SizedBox(height: 50),
              ], // Closes _videoInfo loop
            ],
          ],
        ),
      ),
    );
  }
}
