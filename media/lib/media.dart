import 'package:media/src/bindings/frb_generated.dart';

export 'src/bindings/api/media.dart';

sealed class Media {
  static Future<void> init() async {
    return await RustLib.init();
  }
}
