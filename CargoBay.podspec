Pod::Spec.new do |s|
  s.name     = 'CargoBay'
  s.version  = '2.1.2'
  s.license  = 'MIT'
  s.summary  = 'The Essential StoreKit Companion.'
  s.homepage = 'https://github.com/mattt/CargoBay'
  s.social_media_url = 'https://twitter.com/mattt'
  s.authors  = { 'Mattt Thompson' => 'm@mattt.me' }
  s.source   = { :git => 'https://github.com/mattt/CargoBay.git', :tag => s.version }
  s.source_files = 'CargoBay'
  s.requires_arc = true

  s.ios.deployment_target = '9.3'
  s.osx.deployment_target = '10.8'
  s.frameworks = 'StoreKit', 'Security'
end
