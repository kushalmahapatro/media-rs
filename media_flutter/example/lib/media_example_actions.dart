import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:media_flutter/media_flutter.dart';

/// On desktop (macOS, Windows, Linux), shows [path] as an underlined link; tap
/// reveals the file in Finder / Explorer / the default folder view. On mobile,
/// shows a plain [Text] (export uses the adjacent icon buttons).
Widget revealableFilePathText(
  BuildContext context, {
  required String path,
  TextStyle? style,
  int? maxLines = 5,
  TextOverflow overflow = TextOverflow.ellipsis,
}) {
  final isMobile = Platform.isAndroid || Platform.isIOS;
  final baseStyle = style ?? Theme.of(context).textTheme.bodySmall;
  if (isMobile) {
    return Text(
      path,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
  final scheme = Theme.of(context).colorScheme;
  final linkStyle = baseStyle?.copyWith(
    color: scheme.primary,
    decoration: TextDecoration.underline,
    decorationColor: scheme.primary,
  );
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Semantics(
      button: true,
      label: 'Show in file explorer: $path',
      child: GestureDetector(
        onTap: () => shareOrRevealFile(
          context,
          path,
          subject: p.basename(path),
        ),
        child: Text(
          path,
          style: linkStyle,
          maxLines: maxLines,
          overflow: overflow,
        ),
      ),
    ),
  );
}

String thumbnailFormatFileExt(ThumbnailFormat f) {
  switch (f) {
    case ThumbnailFormat.png:
      return 'png';
    case ThumbnailFormat.jpeg:
      return 'jpg';
    case ThumbnailFormat.webp:
      return 'webp';
  }
}

/// Mobile: system share sheet (export). Desktop: reveal in Finder / Explorer / folder.
Future<void> shareOrRevealFile(
  BuildContext context,
  String filePath, {
  String? subject,
}) async {
  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (isMobile) {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: subject ?? p.basename(filePath),
    );
  } else if (Platform.isMacOS) {
    final r = await Process.run('open', ['-R', filePath]);
    if (r.exitCode != 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reveal in Finder: ${r.stderr}')),
      );
    }
  } else if (Platform.isWindows) {
    final norm = p.normalize(filePath);
    await Process.run('explorer', ['/select,', norm]);
  } else {
    await Process.run('xdg-open', [p.dirname(filePath)]);
  }
}

/// Mobile: share sheet with multiple files. Desktop: opens the **parent directory** of the first file in the file manager.
Future<void> shareOrRevealFilesBatch(
  BuildContext context, {
  required List<String> filePaths,
  String? subject,
}) async {
  if (filePaths.isEmpty) return;
  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (isMobile) {
    await Share.shareXFiles(
      [for (final fp in filePaths) XFile(fp)],
      text: subject ?? '${filePaths.length} files',
    );
  } else {
    final dir = p.dirname(filePaths.first);
    if (Platform.isMacOS) {
      await Process.run('open', [dir]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [p.normalize(dir)]);
    } else {
      await Process.run('xdg-open', [dir]);
    }
  }
}

Future<String> writeTempBytes(
  Uint8List bytes,
  String basename,
  String ext,
) async {
  final dir = await getTemporaryDirectory();
  final safeBase = basename.replaceAll(RegExp(r'[^\w\-.]+'), '_');
  final name =
      '${safeBase}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  final path = p.join(dir.path, name);
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<void> shareOrRevealBytes(
  BuildContext context, {
  required Uint8List bytes,
  required String basename,
  required ThumbnailFormat format,
  String? dialogTitle,
}) async {
  final path = await writeTempBytes(bytes, basename, thumbnailFormatFileExt(format));
  if (!context.mounted) return;
  await shareOrRevealFile(
    context,
    path,
    subject: dialogTitle ?? basename,
  );
}

void showImageBytesViewer(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  ThumbnailFormat format = ThumbnailFormat.png,
  VoidCallback? onExport,
}) {
  final mq = MediaQuery.sizeOf(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: mq.width * 0.92,
        height: mq.height * 0.78,
        child: Column(
          children: [
            ListTile(
              title: Text(title),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onExport != null)
                    IconButton(
                      tooltip: Platform.isAndroid || Platform.isIOS
                          ? 'Export / share'
                          : 'Reveal in file manager',
                      icon: const Icon(Icons.ios_share_outlined),
                      onPressed: onExport,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.25,
                maxScale: 6,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not decode (${format.name}). Try PNG or JPEG.',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showImageFileViewer(
  BuildContext context, {
  required String filePath,
  required String title,
  VoidCallback? onExport,
}) {
  final mq = MediaQuery.sizeOf(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: mq.width * 0.92,
        height: mq.height * 0.78,
        child: Column(
          children: [
            ListTile(
              title: Text(title),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onExport != null)
                    IconButton(
                      tooltip: Platform.isAndroid || Platform.isIOS
                          ? 'Export / share'
                          : 'Reveal in file manager',
                      icon: const Icon(Icons.ios_share_outlined),
                      onPressed: onExport,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.25,
                maxScale: 6,
                child: Image.file(
                  File(filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load image file.',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
