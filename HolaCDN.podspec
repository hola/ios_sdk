Pod::Spec.new do |s|
  s.name         = "HolaCDN"
  s.version      = "1.3.0"
  s.summary      = "Integration for holacdn.com service"

  s.homepage     = "https://holacdn.com/"

  s.license      = { :type => "hola.org", :file => "LICENSE" }

  s.author       = "hola.org"

  s.ios.deployment_target = '7.0'
  s.tvos.deployment_target = '9.0'

  s.source       = { :git => "https://github.com/hola/ios_sdk.git", :tag => "1.3.0" }
  s.source_files  = "hola-cdn-sdk/*.{h,m}"

  s.public_header_files = "hola-cdn-sdk/*.h"

  s.resource_bundles = {
    'HolaCDNAssets' => ['hola-cdn-sdk/*.{js}']
  }

  s.frameworks = "UIKit", "AVFoundation", "JavaScriptCore"

  s.dependency "GCDWebServer", "~> 3.0"

end
