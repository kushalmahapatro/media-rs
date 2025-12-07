import 'dart:io';

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
