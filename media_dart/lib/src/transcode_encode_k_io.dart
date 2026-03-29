import 'dart:io';

/// Platform-specific **median-ish** wall-clock factor: `encode_seconds ≈ k * duration_seconds * (…)`.
///
/// Hardware encoders (Android Media3, iOS VideoToolbox) complete transcodes much faster than
/// this formula would predict with CPU-style `k`; keep mobile `k` low so the hint is in the same
/// ballpark as typical HW re-encode. Desktop FFmpeg/x264 stays higher.
double defaultTranscodeEncodeK() {
  // iOS `AVAssetExportSession` / VideoToolbox is typically several× faster than this
  // heuristic implied at 0.09 for comparable wall-clock hints.
  if (Platform.isIOS) {
    return 0.035;
  }
  if (Platform.isAndroid) {
    return 0.09;
  }
  if (Platform.isMacOS) {
    return 0.52;
  }
  return 1.45;
}
