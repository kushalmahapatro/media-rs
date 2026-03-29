import 'package:media_flutter/media_flutter.dart';

/// Preset for the **`maxEdge`** argument on [Media.thumbnailImage],
/// [Media.thumbnailSaveToPath], and [Media.timelineThumbnailsStream].
///
/// The native stack scales so the **longest side** of the output image is at
/// most this many pixels (aspect ratio preserved). Smaller values mean faster
/// decode, less memory, and smaller files — at the cost of sharpness.
enum ThumbnailWidthPreset {
  /// Uses [sourceLongEdge] from the current [VideoProbe] so the thumbnail is
  /// not downscaled relative to the source dimensions (when width/height are
  /// known). If the probe has no resolution, pick another preset or use
  /// [custom] with an explicit pixel value.
  original,

  /// **1280** px long edge — sharp previews on high-DPI screens and tablets.
  large,

  /// **720** px long edge — common default for chat-style previews; good
  /// balance of quality vs. cost.
  medium,

  /// **320** px long edge — compact grids, filmstrips, and timeline strips.
  small,

  /// Uses the **Custom (px)** text field next to the dropdown; must be a
  /// positive integer.
  custom,
}

/// Long-edge pixel values for fixed tiers (not [original] / [custom]).
const int kThumbnailWidthLargePx = 1280;
const int kThumbnailWidthMediumPx = 720;
const int kThumbnailWidthSmallPx = 320;

String thumbnailWidthPresetLabel(ThumbnailWidthPreset p) {
  switch (p) {
    case ThumbnailWidthPreset.original:
      return 'Original (source long edge)';
    case ThumbnailWidthPreset.large:
      return 'Large ($kThumbnailWidthLargePx px)';
    case ThumbnailWidthPreset.medium:
      return 'Medium ($kThumbnailWidthMediumPx px)';
    case ThumbnailWidthPreset.small:
      return 'Small ($kThumbnailWidthSmallPx px)';
    case ThumbnailWidthPreset.custom:
      return 'Custom (px field)';
  }
}

/// Returns `null` if the preset cannot be resolved (show an error in UI).
int? resolveThumbnailMaxEdge({
  required ThumbnailWidthPreset preset,
  required VideoProbe? probe,
  required String customPixelsText,
}) {
  switch (preset) {
    case ThumbnailWidthPreset.original:
      if (probe == null) return null;
      final e = sourceLongEdge(probe);
      return e > 0 ? e : null;
    case ThumbnailWidthPreset.large:
      return kThumbnailWidthLargePx;
    case ThumbnailWidthPreset.medium:
      return kThumbnailWidthMediumPx;
    case ThumbnailWidthPreset.small:
      return kThumbnailWidthSmallPx;
    case ThumbnailWidthPreset.custom:
      final v = int.tryParse(customPixelsText.trim());
      if (v == null || v < 1) return null;
      return v;
  }
}
