Pod::Spec.new do |s|
  s.name             = "BlurImageProcessor"
  s.version          = "1.0.0"
  s.summary          = "BlurImageProcessor offers a very easy and practical way to generate blurred images in real time."
  s.homepage         = "http://github.com/danielalves/BlurImageProcessor"
  s.screenshots      = "https://raw.githubusercontent.com/danielalves/BlurImageProcessor/master/blur-image-processor.gif"
  s.license          = 'MIT'
  s.author           = "Daniel L. Alves"
  s.source           = { :git => "http://github.com/danielalves/BlurImageProcessor.git", :tag => s.version.to_s }

  s.platform     = :ios, '6.0'
  s.ios.deployment_target = '6.0'
  s.requires_arc = true

  s.source_files = 'ALDBlurImageProcessor'
  s.frameworks = 'Accelerate'
end
