import 'package:media/src/bindings/api/logger.dart';
import 'package:media/src/bindings/frb_generated.dart';

export 'src/bindings/api/media.dart';

sealed class Media {
  static Future<void> init({bool kDebugMode = false}) async {
    await RustLib.init();
    await initLogger(
      logLevel: kDebugMode ? LogLevel.debug : LogLevel.warn,
      writeToStdoutOrSystem: true,
      useLightweightTokioRuntime: true,
    );
  }
}
