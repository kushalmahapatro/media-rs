import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/exception.dart';

@internal
interface class ProcessRunner {
  const ProcessRunner(this.logger);
  final Logger logger;

  Future<ProcessResult> invoke(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      logger.info(
        'Invoking "$executable $arguments" '
        '${workingDirectory != null ? 'in directory $workingDirectory ' : ''}'
        'with environment: ${environment ?? {}}',
      );
      final process = await Process.start(
        executable,
        arguments,
        environment: environment,
        workingDirectory: workingDirectory,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // Stream stdout
      final stdoutDone = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        stdoutBuffer.writeln(line);
        stdout.writeln(line);
      }).asFuture<void>();

      // Stream stderr
      final stderrDone = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        stderrBuffer.writeln(line);
        stderr.writeln(line);
      }).asFuture<void>();

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);

      if (exitCode != 0) {
        throw RustProcessException('Process finished with non-zero exit code: "$executable $arguments" ');
      }

      return ProcessResult(process.pid, exitCode, stdoutBuffer.toString(), stderrBuffer.toString());
    } on ProcessException catch (exception, stackTrace) {
      logger.severe('Failed to invoke "$executable $arguments"', exception, stackTrace);
      rethrow;
    }
  }
}

@internal
extension InvokeRustup on ProcessRunner {
  Future<ProcessResult> invokeRustup(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      return await invoke('rustup', arguments, workingDirectory: workingDirectory, environment: environment);
    } on ProcessException catch (e) {
      throw RustProcessException(
        'Failed to invoke rustup; is it installed? '
        'For help installing rust, see https://rustup.rs',
        inner: e,
      );
    }
  }
}
