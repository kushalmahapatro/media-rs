package dev.flutter.packages.media_flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Ensures the Android embedding merges Media3 / Kotlin classes into the host APK. */
class MediaPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
