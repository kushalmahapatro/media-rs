import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart'; // For Utf8
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media/media.dart';
import 'package:media/src/bindings/ffi.g.dart'; // For CVideoInfo type

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  String? _selectedPath;
  CVideoInfo? _videoInfo;
  Uint8List? _thumbnail;
  bool _loading = false;
  String? _error;
  late final MediaService mediaService;

  @override
  void initState() {
    super.initState();
    mediaService = MediaService();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedPath = result.files.single.path;
          _videoInfo = null;
          _thumbnail = null;
          _error = null;
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
      final info = await mediaService.getVideoInfo(_selectedPath!);
      setState(() {
        _videoInfo = info;
        if (_videoInfo?.codec_name == nullptr) {
          _videoInfo?.codec_name = calloc<Char>();
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
    });

    try {
      final bytes = await mediaService.generateThumbnail(
        _selectedPath!,
        timeMs: 130000,
        maxWidth: 300,
        maxHeight: 300,
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
                        Text('Duration: ${_videoInfo!.duration_ms} ms'),
                        Text(
                          'Resolution: ${_videoInfo!.width}x${_videoInfo!.height}',
                        ),
                        Text('Size: ${_videoInfo!.size_bytes} bytes'),
                        // Text(
                        //   'Codec: ${_videoInfo?.codec_name.cast<Utf8>().toDartString() ?? ""}',
                        // ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _generateThumbnail,
                  child: const Text('Generate Thumbnail @ 2s'),
                ),
              ],
              if (_thumbnail != null) ...[
                const SizedBox(height: 20),
                Image.memory(_thumbnail!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
