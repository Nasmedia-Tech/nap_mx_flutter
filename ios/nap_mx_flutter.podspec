#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint nap_mx_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'nap_mx_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for the nap mx mobile advertising SDK.'
  s.description      = <<-DESC
Flutter plugin for the nap mx mobile advertising SDK.
                       DESC
  s.homepage         = 'https://github.com/Nasmedia-Tech/nap_mx_flutter'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'KT Nasmedia' => 'nap_mx@nasmedia.co.kr' }
  s.source           = { :path => '.' }
  s.source_files = 'nap_mx_flutter/Sources/nap_mx_flutter/**/*'
  s.dependency 'Flutter'
  s.dependency 'AdMixerMediation', '= 2.5.0'
  s.platform = :ios, '13.0'
  s.resource_bundles = {
    'nap_mx_flutter_resources' => [
      'nap_mx_flutter/Sources/nap_mx_flutter/PrivacyInfo.xcprivacy'
    ]
  }

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

end
