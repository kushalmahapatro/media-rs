import 'package:flutter/material.dart';
import 'video_lab_view_model.dart';
import 'video_lab_widgets.dart';

class VideoLabScreen extends StatefulWidget {
  const VideoLabScreen({super.key});

  @override
  State<VideoLabScreen> createState() => _VideoLabScreenState();
}

class _VideoLabScreenState extends State<VideoLabScreen> {
  final VideoLabViewModel _viewModel = VideoLabViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Lab')),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, child) {
          return Stack(
            children: [
              // Main Content
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilePickerWidget(viewModel: _viewModel),
                    const SizedBox(height: 20),

                    // Show metadata only if path is selected
                    if (_viewModel.videoInfo != null) ...[
                      VideoMetadataWidget(videoInfo: _viewModel.videoInfo),
                      const SizedBox(height: 20),

                      CompressionWidget(viewModel: _viewModel),
                      TimelineWidget(viewModel: _viewModel),
                      ThumbnailSeekerWidget(viewModel: _viewModel),
                    ],

                    const SizedBox(height: 50),
                  ],
                ),
              ),

              // Error Overlay
              if (_viewModel.activeError != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    elevation: 4,
                    color: Colors.red.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_viewModel.activeError!, style: const TextStyle(color: Colors.red)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: _viewModel.dismissError,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
