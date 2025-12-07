import 'dart:io';

import 'package:example/image/image_lab_view_model.dart';
import 'package:example/utils/file_utils.dart';
import 'package:flutter/material.dart';
import 'package:media/media.dart';

class FilePickerWidget extends StatelessWidget {
  final ImageLabViewModel viewModel;

  const FilePickerWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: viewModel.pickFile,
          icon: const Icon(Icons.photo_library),
          label: const Text('Pick Image File'),
        ),
        const SizedBox(height: 20),
        if (viewModel.selectedPath != null) ...[
          Text(
            'Selected: ${viewModel.selectedPath}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => showInExplorer(viewModel.selectedPath!),
            child: Image.file(
              File(viewModel.selectedPath!),
              height: 200,
              fit: BoxFit.contain,
            ),
          ),

          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => showInExplorer(viewModel.selectedPath!),
            icon: const Icon(Icons.folder_open),
            label: const Text('Show in Explorer'),
          ),
        ],
      ],
    );
  }
}

class ImageLabOptionsWidget extends StatelessWidget {
  final ImageLabViewModel viewModel;

  const ImageLabOptionsWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Configuration',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<OutputFormat>(
          decoration: const InputDecoration(labelText: 'Output Format'),
          initialValue: viewModel.outputFormat,
          items: viewModel.availableFormats.map((f) {
            return DropdownMenuItem(
              value: f,
              child: Text(f.toString().split('.').last.toUpperCase()),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) viewModel.setOutputFormat(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ThumbnailSizeType>(
          decoration: const InputDecoration(labelText: 'Size Type'),
          initialValue: viewModel.thumbnailSizeType,
          items: viewModel.availableSizeTypes.map((s) {
            return DropdownMenuItem(value: s, child: Text(s.label));
          }).toList(),
          onChanged: (v) {
            if (v != null) viewModel.setThumbnailSizeType(v);
          },
        ),
        if (viewModel.thumbnailSizeType is ThumbnailSizeType_Custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Width'),
                  keyboardType: TextInputType.number,
                  initialValue: viewModel.customWidth?.toString() ?? '',
                  onChanged: (v) {
                    final w = int.tryParse(v);
                    viewModel.setCustomDimensions(w, viewModel.customHeight);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Height'),
                  keyboardType: TextInputType.number,
                  initialValue: viewModel.customHeight?.toString() ?? '',
                  onChanged: (v) {
                    final h = int.tryParse(v);
                    viewModel.setCustomDimensions(viewModel.customWidth, h);
                  },
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: viewModel.isThumbnailLoading
              ? null
              : viewModel.generateThumbnail,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: viewModel.isThumbnailLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate Thumbnail'),
        ),
      ],
    );
  }
}

class ImageLabResultWidget extends StatelessWidget {
  final ImageLabViewModel viewModel;

  const ImageLabResultWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.thumbnailPath == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 10),
        const Text(
          'Result:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
            child: InkWell(
              onTap: () => showInExplorer(viewModel.thumbnailPath!),
              child: Image.file(
                File(viewModel.thumbnailPath!),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Saved to: ${viewModel.thumbnailPath}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
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
