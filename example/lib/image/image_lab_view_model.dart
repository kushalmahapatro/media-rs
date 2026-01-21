import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media/media.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class ImageLabViewModel extends ChangeNotifier {
  // Picked file directory
  Directory? _pickedFileDirectory;

  // --- Global / File State ---
  String? _selectedPath;
  String? get selectedPath => _selectedPath;

  String? _thumbnailOutputPath;

  // --- Thumbnail State ---
  String? _thumbnailPath;
  String? get thumbnailPath => _thumbnailPath;

  bool _isThumbnailLoading = false;
  bool get isThumbnailLoading => _isThumbnailLoading;

  String? _thumbnailError;
  String? get thumbnailError => _thumbnailError;

  // Defaults
  ThumbnailSizeType _thumbnailSizeType = const ThumbnailSizeType.medium();
  ThumbnailSizeType get thumbnailSizeType => _thumbnailSizeType;

  OutputFormat _outputFormat = OutputFormat.png;
  OutputFormat get outputFormat => _outputFormat;

  // Custom Dimensions
  int? _customWidth;
  int? get customWidth => _customWidth;
  int? _customHeight;
  int? get customHeight => _customHeight;

  // Dropdown options
  List<ThumbnailSizeType> get availableSizeTypes => [
    const ThumbnailSizeType.icon(),
    const ThumbnailSizeType.small(),
    const ThumbnailSizeType.medium(),
    const ThumbnailSizeType.large(),
    const ThumbnailSizeType.larger(),
    const ThumbnailSizeType.custom((
      0,
      0,
    )), // Placeholder for "Custom" option logic in UI
  ];

  List<OutputFormat> get availableFormats => OutputFormat.values;

  void setThumbnailSizeType(ThumbnailSizeType size) {
    _thumbnailSizeType = size;
    notifyListeners();
  }

  void setOutputFormat(OutputFormat format) {
    _outputFormat = format;
    notifyListeners();
  }

  void setCustomDimensions(int? width, int? height) {
    _customWidth = width;
    _customHeight = height;
    notifyListeners();
  }

  // --- Initialization ---
  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _thumbnailOutputPath = join(directory.path, 'image_labs_thumbnails');
  }

  @override
  void dispose() {
    _selectedPath = null;
    super.dispose();
  }

  Future<void> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        initialDirectory: _pickedFileDirectory?.path,
        // type: FileType.image,
      );

      if (result != null && result.files.single.path != null) {
        _pickedFileDirectory = Directory(result.files.single.path!).parent;
        _selectedPath = result.files.single.path;
        // Reset all states
        _thumbnailPath = null;
        _thumbnailError = null;

        notifyListeners();
      }
    } catch (e) {
      _thumbnailError = e.toString();
      notifyListeners();
    }
  }

  Future<void> generateThumbnail() async {
    if (_selectedPath == null || _thumbnailOutputPath == null) return;

    _thumbnailError = null;
    _thumbnailPath = null;
    _isThumbnailLoading = true;
    notifyListeners();

    try {
      ThumbnailSizeType sizeToUse = _thumbnailSizeType;
      if (_thumbnailSizeType is ThumbnailSizeType_Custom) {
        if (_customWidth == null ||
            _customHeight == null ||
            _customWidth! <= 0 ||
            _customHeight! <= 0) {
          _thumbnailError = "Please enter valid custom dimensions";
          _isThumbnailLoading = false;
          notifyListeners();
          return;
        }
        sizeToUse = ThumbnailSizeType.custom((_customWidth!, _customHeight!));
      }

      final path = await generateImageThumbnail(
        path: _selectedPath!,
        outputPath: _thumbnailOutputPath!,
        params: ImageThumbnailParams(
          sizeType: sizeToUse,
          format: _outputFormat,
        ),
        suffix: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      _thumbnailPath = path;
    } catch (e) {
      _thumbnailError = "Error generating thumbnail: $e";
      debugPrint(_thumbnailError);
    } finally {
      _isThumbnailLoading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _thumbnailError = null;
    notifyListeners();
  }
}

extension ThumbnailSizeTypeExt on ThumbnailSizeType {
  String get label {
    if (this is ThumbnailSizeType_Custom) {
      return "Custom";
    } else {
      final lable = toString().split('.').last.replaceAll('()', '');
      return lable[0].toUpperCase() + lable.substring(1);
    }
  }
}
