import 'dart:io';

import 'package:flutter/material.dart';

Future<void> showInExplorer(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  } else if (Platform.isLinux) {
    // Linux file managers vary, xdg-open usually opens the file itself or directory.
    // To select the file might require specific file manager commands (nautilus, dolphin).
    // For safety, let's just open the parent directory.
    await Process.run('xdg-open', [File(path).parent.path]);
  } else if (Platform.isAndroid) {
    // On Android, we can't directly open the file manager to a specific file
    // The file_picker package handles file selection, and files are typically
    // stored in app-specific directories that are accessible.
    // For now, we'll just show a message or do nothing.
    // In a production app, you might want to use a package like 'open_file' or 'share_plus'
    // to open the file or share it.
    debugPrint('File path on Android: $path');
    // Optionally, you could show a snackbar or dialog with the path
  }
}

extension BigIntExtension on BigInt {
  int get divider => 1000;
  String get kb {
    return (this / BigInt.from(divider)).toStringAsFixed(2);
  }

  String get mb {
    return (this / BigInt.from(divider) / divider).toStringAsFixed(2);
  }
}
