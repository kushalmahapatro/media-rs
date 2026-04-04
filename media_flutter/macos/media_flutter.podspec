#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'media_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for media processing'
  s.description      = 'Flutter plugin for media processing using native code.'
  s.homepage         = 'https://github.com/kushalmahapatro/media-rs'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Kushal Mahapatro' => 'kushal@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.swift_version    = '5.0'
  
  # Automatically copy FFmpeg binaries after compilation
  s.script_phases = [
    {
      :name => 'Copy FFmpeg Binaries',
      :script => 'bash "${PODS_TARGET_SRCROOT}/copy_ffmpeg.sh" "${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}" || true',
      :execution_position => :after_compile
    }
  ]
end
