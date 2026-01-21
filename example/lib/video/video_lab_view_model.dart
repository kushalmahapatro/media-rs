import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media/media.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class VideoLabViewModel extends ChangeNotifier {
  // Picked file directory
  Directory? _pickedFileDirectory;

  // --- Global / File State ---
  String? _selectedPath;
  String? get selectedPath => _selectedPath;

  String? _thumbnailOutputPath;
  String? _compressedOutputPath;
  String? _compressedVideoPath;
  String? get compressedVideoPath => _compressedVideoPath;

  // --- Video Info State ---
  VideoInfo? _videoInfo;
  VideoInfo? get videoInfo => _videoInfo;

  bool _isInfoLoading = false;
  bool get isInfoLoading => _isInfoLoading;

  String? _infoError;
  String? get infoError => _infoError;

  // --- Single Thumbnail State ---
  String? _thumbnailPath;
  String? get thumbnailPath => _thumbnailPath;

  bool _isThumbnailLoading = false;
  bool get isThumbnailLoading => _isThumbnailLoading;

  String? _thumbnailError;
  String? get thumbnailError => _thumbnailError;

  double _value = 0;
  double get value => _value;
  set value(double val) {
    _value = val;
    notifyListeners();
  }

  // --- Compression / Estimation State ---
  // Inputs
  final TextEditingController widthController = TextEditingController();
  final TextEditingController heightController = TextEditingController();

  ResolutionPreset? _selectedPreset;
  ResolutionPreset? get selectedPreset => _selectedPreset;

  bool _isCustom = false;
  bool get isCustom => _isCustom;

  int? _targetBitrateKbps;
  int? get targetBitrateKbps => _targetBitrateKbps;

  int? _targetCrf;
  int? get targetCrf => _targetCrf;

  // Estimation Output
  CompressionEstimate? _estimate;
  CompressionEstimate? get estimate => _estimate;

  bool _isEstimationLoading = false;
  bool get isEstimationLoading => _isEstimationLoading;

  String? _estimationError;
  String? get estimationError => _estimationError;

  // Compression Output
  String? _compressionResult;
  String? get compressionResult => _compressionResult;

  BigInt? _compressedSize;
  BigInt? get compressedSize => _compressedSize;

  BigInt? _compressedDuration;
  BigInt? get compressedDuration => _compressedDuration;

  bool _isCompressing = false;
  bool get isCompressing => _isCompressing;

  bool _isDownscaling = false;
  bool get isDownscaling => _isDownscaling;

  String? _compressionError;
  String? get compressionError => _compressionError;

  String? _downscaleError;
  String? get downscaleError => _downscaleError;

  // --- Timeline State ---
  final TextEditingController numThumbnailsController = TextEditingController(text: "10");
  final List<String> _timelineThumbnails = [];
  List<String> get timelineThumbnails => List.unmodifiable(_timelineThumbnails);

  bool _generatingTimeline = false;
  bool get generatingTimeline => _generatingTimeline;

  String? _timelineError;
  String? get timelineError => _timelineError;

  StreamSubscription<String>? _timelineSubscription;

  // --- Initialization ---
  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _thumbnailOutputPath = join(directory.path, 'video_labs_thumbnails');
    _compressedOutputPath = join(directory.path, 'video_labs_compressed');
  }

  @override
  void dispose() {
    numThumbnailsController.dispose();
    widthController.dispose();
    heightController.dispose();
    _timelineSubscription?.cancel();
    super.dispose();
  }

  // --- Methods ---

  // Aggregated Error Getter
  String? get activeError {
    return _infoError ?? _thumbnailError ?? _estimationError ?? _compressionError ?? _timelineError;
  }

  void dismissError() {
    _infoError = null;
    _thumbnailError = null;
    _estimationError = null;
    _compressionError = null;
    _timelineError = null;
    notifyListeners();
  }

  Future<void> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        initialDirectory: _pickedFileDirectory?.path,
      );

      if (result != null && result.files.single.path != null) {
        _pickedFileDirectory = Directory(result.files.single.path!).parent;
        _selectedPath = result.files.single.path;
        // Reset all states
        _videoInfo = null;
        _infoError = null;

        _thumbnailPath = null;
        _thumbnailError = null;
        _value = 0;

        _estimate = null;
        _estimationError = null;
        _compressedVideoPath = null;
        _compressionResult = null;
        _compressedSize = null;
        _compressedDuration = null;
        _compressionError = null;

        _selectedPreset = null;
        _isCustom = false;
        _targetBitrateKbps = null;
        _targetCrf = null;
        widthController.clear();
        heightController.clear();

        _timelineThumbnails.clear();
        _timelineError = null;
        _generatingTimeline = false;

        notifyListeners();

        await _loadInfo();
      }
    } catch (e) {
      // If picking fails, we might set a general error or just info error?
      // Since it's about loading the file, infoError seems appropriate or a snackbar.
      // But typically pickFiles doesn't throw unless something is very wrong.
      _infoError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _loadInfo() async {
    if (_selectedPath == null) return;

    _isInfoLoading = true;
    _infoError = null;
    notifyListeners();

    try {
      final VideoInfo info = await getVideoInfo(path: _selectedPath!);
      _videoInfo = info;
      // Auto-select first preset
      if (info.suggestions.isNotEmpty) {
        onPresetChanged(info.suggestions.first);
      }
    } catch (e) {
      debugPrint(e.toString());
      _infoError = "Error loading info: $e";
    } finally {
      _isInfoLoading = false;
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
      final path = await generateVideoThumbnail(
        path: _selectedPath!,
        outputPath: _thumbnailOutputPath!,
        params: VideoThumbnailParams(timeMs: BigInt.from(_value)),
        emptyImageFallback: true,
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

  Future<void> runEstimation() async {
    if (_selectedPath == null || _videoInfo == null || _compressedOutputPath == null) {
      return;
    }

    _isEstimationLoading = true;
    _estimationError = null;
    _estimate = null;
    notifyListeners();

    final int? width = int.tryParse(widthController.text);
    final int? height = int.tryParse(heightController.text);
    final int targetBitrateKbps = _targetBitrateKbps ?? 1000;
    final int targetCrf = _targetCrf ?? 28;
    final String preset = "veryfast";
    final BigInt sampleDurationMs = BigInt.from(3000);
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
          sampleDurationMs: sampleDurationMs,
        ),
      );
      _estimate = estimate;
    } catch (e) {
      _estimationError = "Estimation failed: $e";
      debugPrint(_estimationError);
    } finally {
      _isEstimationLoading = false;
      notifyListeners();
    }
  }

  Future<void> runCompression() async {
    if (_selectedPath == null || _compressedOutputPath == null) return;

    _isCompressing = true;
    _compressionError = null;
    _compressionResult = null;
    _compressedSize = null;
    _compressedDuration = null;
    notifyListeners();

    int? w = int.tryParse(widthController.text);
    int? h = int.tryParse(heightController.text);
    final int targetBitrateKbps = _targetBitrateKbps ?? 1000;
    final int targetCrf = _targetCrf ?? 28;

    final Stopwatch stopwatch = Stopwatch()..start();

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

      _compressedVideoPath = outputPath;
      _compressionResult = "Success! Saved to $outputPath";
      _compressedSize = await getVideoInfo(path: outputPath).then((info) {
        return info.sizeBytes;
      });
    } catch (e) {
      _compressionError = "Compression failed: $e";
      debugPrint(_compressionError);
    } finally {
      _isCompressing = false;
      stopwatch.stop();
      notifyListeners();
    }
    _compressedDuration = BigInt.from(stopwatch.elapsedMilliseconds);
    notifyListeners();
  }

  Future<void> runTimelineGeneration() async {
    if (_selectedPath == null || _generatingTimeline || _thumbnailOutputPath == null) {
      return;
    }

    final int? numThumbnails = int.tryParse(numThumbnailsController.text);
    if (numThumbnails == null || numThumbnails <= 0) {
      _timelineError = "Invalid number of thumbnails";
      notifyListeners();
      return;
    }

    _generatingTimeline = true;
    _timelineThumbnails.clear();
    _timelineError = null;
    notifyListeners();

    try {
      final stream = generateVideoTimelineThumbnails(
        path: _selectedPath!,
        outputPath: join(_thumbnailOutputPath!, "timeline_${DateTime.now().millisecondsSinceEpoch}"),
        numThumbnails: numThumbnails,
        params: const ImageThumbnailParams(sizeType: ThumbnailSizeType.small(), format: OutputFormat.webp),
      );

      _timelineSubscription = stream.listen(
        (path) {
          _timelineThumbnails.add(path);
          notifyListeners();
        },
        onError: (e) {
          _timelineError = "Timeline generation error: $e";
          _generatingTimeline = false;
          notifyListeners();
        },
        onDone: () {
          _generatingTimeline = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _timelineError = "Failed to start timeline generation: $e";
      _generatingTimeline = false;
      notifyListeners();
    }
  }

  void onPresetChanged(ResolutionPreset? value) {
    if (value != null) {
      _selectedPreset = value;
      _isCustom = false;
      widthController.text = value.width.toString();
      heightController.text = value.height.toString();
      _targetBitrateKbps = (value.bitrate ~/ BigInt.from(1000)).toInt();
      _targetCrf = value.crf;
    } else {
      _selectedPreset = null;
      _isCustom = true;
      if (widthController.text.isEmpty && _videoInfo != null) {
        widthController.text = _videoInfo!.width.toString();
        heightController.text = _videoInfo!.height.toString();
        _targetBitrateKbps = 1000;
        _targetCrf = 28;
      }
    }
    notifyListeners();
  }

  void onWidthChanged(String val) {
    if (val.isNotEmpty && _videoInfo != null) {
      final w = int.tryParse(val);
      if (w != null && w > 0) {
        final ratio = _videoInfo!.height / _videoInfo!.width;
        final h = (w * ratio).round();
        heightController.text = (h & ~1).toString();
      }
    }
    notifyListeners();
  }

  void onHeightChanged(String val) {
    if (val.isNotEmpty && _videoInfo != null) {
      final h = int.tryParse(val);
      if (h != null && h > 0) {
        final ratio = _videoInfo!.width / _videoInfo!.height;
        final w = (h * ratio).round();
        widthController.text = (w & ~1).toString();
      }
    }
    notifyListeners();
  }
}
