import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:media_cli/src/collect_native_command.dart';
import 'package:media_cli/src/dist_command.dart';
import 'package:media_cli/src/package_macos_pkg_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'media_cli',
    'Media package tooling: collect-native prebuilts; optional Fastforge dist wrapper.',
  )..addCommand(CollectNativeCommand())
    ..addCommand(DistCommand())
    ..addCommand(PackageMacosPkgCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}
