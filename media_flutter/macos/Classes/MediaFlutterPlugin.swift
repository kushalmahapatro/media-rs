import Cocoa
import FlutterMacOS

public class MediaFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Platform channel setup if needed
    // Currently using FFI (frb) so no platform channel needed
  }
}
