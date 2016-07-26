Pod::Spec.new do |s|
  s.name         = "HolaCDN"
  s.version      = "1.1.1"
  s.summary      = "Integration for holacdn.com service"

  s.homepage     = "https://holacdn.com/"

  s.license      = { :type => "hola.org", :file => "LICENSE" }

  s.author       = "hola.org"

  s.platform     = :ios, "9.0"
  s.source       = { :git => "https://github.com/hola/ios_sdk.git", :tag => "1.1.1" }
  s.source_files  = "hola_cdn/*.{swift,plist}"

  #s.public_header_files = "hola_cdn/*.h"

  s.frameworks = "UIKit", "AVFoundation", "AVKit", "JavaScriptCore"

  s.dependency "GCDWebServer", "~> 3.0"

end
