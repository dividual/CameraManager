Pod::Spec.new do |s|
  s.name         = "CameraManager"
  s.version      = "0.2.0"
  s.summary      = "Camera Manager for blink"
  s.homepage     = "https://github.com/noughts/CameraManager"
  s.author       = { "dividual" => "contact@dividual.jp" }
  s.source       = { :git => "https://github.com/noughts/CameraManager.git", :tag => "#{s.version}" }
  s.license      = { :type => 'MIT', :file => 'LICENSE' }

  s.platform = :ios
  s.requires_arc = true
  s.framework  = 'AddressBook'
  s.dependency 'GPUImage'
  s.source_files = 'CameraManager'
end
