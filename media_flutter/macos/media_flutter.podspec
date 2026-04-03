#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint media_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'media_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for media processing'
  s.description      = <<-DESC
Flutter plugin for media processing using native code.
                       DESC
  s.homepage         = 'https://github.com/kushalmahapatro/media-rs'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
  
  # Script to copy FFmpeg binaries after build
  s.script_phases = [
    {
      :name => 'Copy FFmpeg Binaries',
      :script => '
        set -e
        
        # Determine architecture
        if [ "${ARCHS}" = "arm64" ]; then
          FFMPEG_ARCH="darwin-arm64"
        else
          FFMPEG_ARCH="darwin-x64"
        fi
        
        # Source: media_dart/native/ffmpeg/
        FFMPEG_SRC="${PODS_TARGET_SRCROOT}/../media_dart/native/ffmpeg/${FFMPEG_ARCH}"
        
        # Target: App bundle Frameworks
        BUNDLE_DIR="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}"
        FRAMEWORKS_DIR="${BUNDLE_DIR}/Contents/Frameworks"
        
        if [ -f "${FFMPEG_SRC}/ffmpeg" ] && [ -f "${FFMPEG_SRC}/ffprobe" ]; then
          mkdir -p "${FRAMEWORKS_DIR}"
          cp "${FFMPEG_SRC}/ffmpeg" "${FRAMEWORKS_DIR}/"
          cp "${FFMPEG_SRC}/ffprobe" "${FRAMEWORKS_DIR}/"
          chmod +x "${FRAMEWORKS_DIR}/ffmpeg" "${FRAMEWORKS_DIR}/ffprobe"
          echo "✅ Copied FFmpeg to ${FRAMEWORKS_DIR}"
        else
          echo "⚠️ FFmpeg not found at ${FFMPEG_SRC}"
          echo "   Run 'dart run hook/build.dart' first to download FFmpeg"
        fi
      ',
      :execution_position => :after_compile
    }
  ]
end
