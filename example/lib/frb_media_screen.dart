import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media/media.dart';

class FrbMediaScreen extends StatefulWidget {
  const FrbMediaScreen({super.key});

  @override
  State<FrbMediaScreen> createState() => _FrbMediaScreenState();
}

class _FrbMediaScreenState extends State<FrbMediaScreen> {
  String? _selectedPath;
  VideoInfo? _videoInfo;
  Uint8List? _thumbnail;
  bool _loading = false;
  String? _error;
  late final FrbMediaService mediaService;
  double _value = 0;

  @override
  void initState() {
    super.initState();
    mediaService = FrbMediaService();
    mediaService.init();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedPath = result.files.single.path;
          _videoInfo = null;
          _thumbnail = null;
          _error = null;
          _value = 0;
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
      final info = await getVideoInfo(path: _selectedPath!);
      setState(() {
        _videoInfo = info;
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
      _thumbnail = null;
    });

    try {
      final bytes = await generateThumbnail(
        path: _selectedPath!,
        params: ThumbnailParams(
          timeMs: BigInt.from(_value),
          maxWidth: 300,
          maxHeight: 300,
        ),
      );
      setState(() {
        _thumbnail = bytes;
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
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.video_library),
              label: const Text('Pick Video File'),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else ...[
              if (_selectedPath != null) ...[
                Text(
                  'Selected: $_selectedPath',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
              ],
              if (_videoInfo != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Duration: ${_videoInfo!.durationMs} ms'),
                        Text(
                          'Resolution: ${_videoInfo!.width}x${_videoInfo!.height}',
                        ),
                        Text('Size: ${_videoInfo!.sizeBytes} bytes'),
                        Text('Codec: ${_videoInfo?.codecName ?? ""}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_videoInfo != null &&
                    _videoInfo!.durationMs > BigInt.zero) ...[
                  Row(
                    spacing: 10,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Slider(
                            max: _videoInfo!.durationMs.toDouble(),
                            value: _value,
                            label: '$_value ms',
                            onChanged: (value) {
                              setState(() {
                                _value = value;
                              });
                            },
                          ),

                          ElevatedButton(
                            onPressed: _generateThumbnail,
                            child: Text(
                              'Generate Thumbnail @ ${_value.toInt()} ms',
                            ),
                          ),
                        ],
                      ),
                      if (_thumbnail != null) ...[
                        Image.memory(_thumbnail!, fit: BoxFit.contain),
                      ],
                    ],
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
