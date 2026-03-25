import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media/media.dart';
import 'package:os_video_delivery/os_video_delivery.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Processing pipeline for A/B comparison: Rust/FFmpeg vs OS codecs (Media3 / AVFoundation).
enum VideoLabBackend {
  rustMedia,
  platformOs,
}

class VideoLabViewModel extends ChangeNotifier {
  // Picked file directory
  Directory? _pickedFileDirectory;

  VideoLabBackend _backend = VideoLabBackend.rustMedia;
  VideoLabBackend get backend => _backend;

  static bool get platformBackendAvailable => OsVideoDelivery.isSupported;

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

  /// Playback duration of the compressed file (from container metadata).
  BigInt? _compressedOutputDurationMs;
  BigInt? get compressedOutputDurationMs => _compressedOutputDurationMs;

  /// Wall-clock time spent in [compressVideo] (not video length).
  BigInt? _compressionEncodeTimeMs;
  BigInt? get compressionEncodeTimeMs => _compressionEncodeTimeMs;

  bool _isCompressing = false;
  bool get isCompressing => _isCompressing;

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

  void setBackend(VideoLabBackend value) {
    if (_backend == value) return;
    if (value == VideoLabBackend.platformOs && !OsVideoDelivery.isSupported) return;
    _backend = value;
    _timelineSubscription?.cancel();
    _timelineSubscription = null;
    _estimate = null;
    _estimationError = null;
    _compressionResult = null;
    _compressedVideoPath = null;
    _compressedSize = null;
    _compressedOutputDurationMs = null;
    _compressionEncodeTimeMs = null;
    _compressionError = null;
    _timelineThumbnails.clear();
    _timelineError = null;
    _thumbnailPath = null;
    _thumbnailError = null;
    notifyListeners();
  }

  VideoDeliveryProfile _deliveryProfileFromUi() {
    var w = int.tryParse(widthController.text) ?? 0;
    var h = int.tryParse(heightController.text) ?? 0;
    if (w <= 0 || h <= 0) {
      final info = _videoInfo;
      if (info != null) {
        w = info.width;
        h = info.height;
      }
    }
    final longEdge = max(1, max(w, h));
    final br = _targetBitrateKbps ?? 1000;
    return VideoDeliveryProfile(
      id: 'lab_custom',
      maxLongEdgePx: longEdge,
      videoBitrateKbps: br,
      audioBitrateKbps: 128,
    );
  }

  Future<void> pickVideoFile() async {
    String? path;
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        final result = await ImagePicker().pickVideo(source: ImageSource.gallery);
        path = result?.path;
      } else {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          initialDirectory: _pickedFileDirectory?.path,
        );
        path = result?.files.single.path;
      }

      if (path != null) {
        _pickedFileDirectory = Directory(path).parent;
        _selectedPath = path;
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
        _compressedOutputDurationMs = null;
        _compressionEncodeTimeMs = null;
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
      if (_backend == VideoLabBackend.platformOs) {
        await Directory(_thumbnailOutputPath!).create(recursive: true);
        final bytes = await OsVideoDelivery.instance.videoThumbnail(
          path: _selectedPath!,
          timeMs: _value.toInt(),
          maxWidth: 512,
          maxHeight: 512,
          format: ThumbnailImageFormat.jpeg,
          rotationDegrees: _videoInfo?.rotationDegrees,
        );
        final name = 'platform_thumb_${_value.toInt()}.jpg';
        final out = join(_thumbnailOutputPath!, name);
        await File(out).writeAsBytes(bytes);
        _thumbnailPath = out;
      } else {
        final path = await generateVideoThumbnail(
          path: _selectedPath!,
          outputPath: _thumbnailOutputPath!,
          params: VideoThumbnailParams(timeMs: BigInt.from(_value)),
          emptyImageFallback: true,
        );
        _thumbnailPath = path;
      }
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
    final String preset = "veryfast";
    final BigInt sampleDurationMs = BigInt.from(3000);
    try {
      if (_backend == VideoLabBackend.platformOs) {
        final profile = _deliveryProfileFromUi();
        final rows = await OsVideoDelivery.instance.estimateDelivery(
          path: _selectedPath!,
          profiles: [profile],
        );
        if (rows.isEmpty) {
          throw StateError('Platform estimate returned no rows');
        }
        final row = rows.first;
        _estimate = CompressionEstimate(
          estimatedSizeBytes: BigInt.from(row.estimatedSizeBytes),
          estimatedDurationMs: BigInt.from(row.estimatedEncodeTimeMs),
        );
      } else {
        final estimate = await estimateCompression(
          path: _selectedPath!,
          tempOutputPath: _compressedOutputPath!,
          params: CompressParams(
            targetBitrateKbps: targetBitrateKbps,
            width: width,
            height: height,
            preset: preset,
            crf: null,
            sampleDurationMs: sampleDurationMs,
          ),
        );
        _estimate = estimate;
      }
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
    _compressedOutputDurationMs = null;
    _compressionEncodeTimeMs = null;
    notifyListeners();

    int? w = int.tryParse(widthController.text);
    int? h = int.tryParse(heightController.text);
    final int targetBitrateKbps = _targetBitrateKbps ?? 1000;
    final int targetCrf = _targetCrf ?? 28;

    final Stopwatch stopwatch = Stopwatch()..start();

    try {
      late final String outputPath;
      if (_backend == VideoLabBackend.platformOs) {
        await Directory(_compressedOutputPath!).create(recursive: true);
        final profile = _deliveryProfileFromUi();
        final name = 'osvd_${DateTime.now().millisecondsSinceEpoch}.mp4';
        outputPath = join(_compressedOutputPath!, name);
        await OsVideoDelivery.instance.transcode(
          inputPath: _selectedPath!,
          outputPath: outputPath,
          profile: profile,
        );
        _compressedVideoPath = outputPath;
        final stat = await File(outputPath).stat();
        _compressedSize = BigInt.from(stat.size);
        final outProbe = await OsVideoDelivery.instance.probe(outputPath);
        _compressedOutputDurationMs = BigInt.from(outProbe.durationMs);
        _compressionResult = "Success (platform / Media3 or AVFoundation)! Saved to $outputPath";
      } else {
        outputPath = await compressVideo(
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
        final VideoInfo outInfo = await getVideoInfo(path: outputPath);
        _compressedSize = outInfo.sizeBytes;
        _compressedOutputDurationMs = outInfo.durationMs;
        _compressionResult = "Success (Rust / FFmpeg)! Saved to $outputPath";
      }
    } catch (e) {
      _compressionError = "Compression failed: $e";
      debugPrint(_compressionError);
    } finally {
      _isCompressing = false;
      stopwatch.stop();
      _compressionEncodeTimeMs = BigInt.from(stopwatch.elapsedMilliseconds);
      notifyListeners();
    }
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
      if (_backend == VideoLabBackend.platformOs) {
        final folder = join(_thumbnailOutputPath!, "timeline_${DateTime.now().millisecondsSinceEpoch}");
        await Directory(folder).create(recursive: true);
        final durMs = _videoInfo!.durationMs.toInt();
        final n = numThumbnails;
        for (var i = 0; i < n; i++) {
          final tMs = n <= 1 ? 0 : ((i * durMs) / (n - 1)).round();
          final bytes = await OsVideoDelivery.instance.videoThumbnail(
            path: _selectedPath!,
            timeMs: tMs,
            maxWidth: 256,
            maxHeight: 256,
            format: ThumbnailImageFormat.jpeg,
            rotationDegrees: _videoInfo?.rotationDegrees,
          );
          final out = join(folder, 'timeline_$i.jpg');
          await File(out).writeAsBytes(bytes);
          _timelineThumbnails.add(out);
          notifyListeners();
        }
        _generatingTimeline = false;
        notifyListeners();
      } else {
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
      }
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
