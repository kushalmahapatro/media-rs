/// Flutter-facing re-export of [media_dart] plus plugin registration.
library;

export 'package:media_dart/media_dart.dart';

import 'package:flutter/services.dart';

/// The MediaFlutter plugin class.
/// This is needed for plugin registration on desktop platforms.
class MediaFlutter {
  static void registerWith() {
    // No-op - FFI is used instead of platform channels
    // This method is required for plugin registration
  }
}
