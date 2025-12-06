import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:media/src/bindings/ffi.g.dart';

class MediaService {
  const MediaService();

  Future<CVideoInfo> getVideoInfo(String path) async {
    final pathPtr = path.toNativeUtf8().cast<Char>();
    final infoPtr = await Isolate.run(() => media_get_video_info(pathPtr));
    calloc.free(pathPtr);

    if (infoPtr == nullptr) {
      throw Exception("Failed to get video info");
    }
    final info = infoPtr.ref;
    media_free_video_info(infoPtr);
    return info;
  }

  Future<Uint8List> generateThumbnail(
    String path, {
    int timeMs = 1000,
    int maxWidth = 512,
    int maxHeight = 512,
  }) async {
    final pathPtr = path.toNativeUtf8().cast<Char>();
    final bufferPtr = await Isolate.run(
      () => media_generate_thumbnail(pathPtr, timeMs, maxWidth, maxHeight),
    );
    calloc.free(pathPtr);

    if (bufferPtr == nullptr) {
      throw Exception("Failed to generate thumbnail");
    }

    final buffer = bufferPtr.ref;
    // Copy data to Dart-managed memory
    final data = Uint8List.fromList(buffer.data.asTypedList(buffer.len));

    media_free_buffer(bufferPtr);

    return data;
  }
}
