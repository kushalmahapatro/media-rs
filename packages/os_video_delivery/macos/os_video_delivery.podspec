Pod::Spec.new do |s|
  s.name             = 'os_video_delivery'
  s.version          = '0.1.0'
  s.summary          = 'OS-native video delivery for macOS'
  s.homepage         = 'https://github.com/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'media-rs' => 'dev@localhost' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
