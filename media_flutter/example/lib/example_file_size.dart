import 'dart:io';

/// Human-readable size using **B**, **KB**, **MB**, or **GB** — whichever keeps the number readable.
String formatAdaptiveFileSize(int bytes) {
  var n = bytes < 0 ? 0 : bytes;
  const k = 1024;

  if (n < k) {
    return '$n B';
  }
  var v = n / k;
  if (v < k) {
    return '${_fmtUnit(v)} KB';
  }
  v /= k;
  if (v < k) {
    return '${_fmtUnit(v)} MB';
  }
  v /= k;
  return '${_fmtUnit(v)} GB';
}

String _fmtUnit(double v) {
  String s;
  if (v >= 100) {
    s = v.toStringAsFixed(0);
  } else if (v >= 10) {
    s = v.toStringAsFixed(1);
  } else {
    s = v.toStringAsFixed(2);
  }
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// `File size: …` line, or `null` if [path] cannot be stat’d.
String? tryFileSizeLabel(String path) {
  try {
    final len = File(path).lengthSync();
    return 'File size: ${formatAdaptiveFileSize(len)}';
  } catch (_) {
    return null;
  }
}
