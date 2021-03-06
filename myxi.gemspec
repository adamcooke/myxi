require File.expand_path('../lib/myxi/version', __FILE__)

Gem::Specification.new do |s|
  s.name          = "myxi"
  s.description   = %q{A RabbitMQ-based web socket server & framework}
  s.summary       = s.description
  s.homepage      = "https://github.com/adamcooke/myxi"
  s.licenses      = ['MIT']
  s.version       = Myxi::VERSION
  s.files         = Dir.glob("{bin,lib,vendor}/**/*")
  s.require_paths = ["lib"]
  s.authors       = ["Adam Cooke"]
  s.email         = ["me@adamcooke.io"]
  s.add_runtime_dependency 'bunny', '>= 2.5.1', '< 3'
  s.add_runtime_dependency 'websocket', '>= 1.2.4', '< 2'
  s.add_runtime_dependency 'nio4r', '>= 1.2'
  s.add_runtime_dependency 'timers', '>= 4.1.2', '< 5'
end
