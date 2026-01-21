import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs a process and streams stdout/stderr line-by-line to the console.
///
/// - Mirrors the `Process.run` API shape for `executable`, `arguments`,
///   `workingDirectory`, `environment`, and `runInShell`.
/// - Returns the full collected stdout/stderr and the exit code.
Future<ProcessResult> runProcessStreaming(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
  );

  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();

  // Stream stdout
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    stdoutBuffer.writeln(line);
    stdout.writeln(line);
  }).asFuture<void>();

  // Stream stderr
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    stderrBuffer.writeln(line);
    stderr.writeln(line);
  }).asFuture<void>();

  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);

  return ProcessResult(
    process.pid,
    exitCode,
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}


