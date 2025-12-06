import 'package:media/src/bindings/frb_generated.dart';

class FrbMediaService {
  const FrbMediaService();

  Future<void> init() async {
    return await RustLib.init();
  }
}
