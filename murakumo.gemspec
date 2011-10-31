Gem::Specification.new do |spec|
  spec.name              = 'murakumo'
  spec.version           = '0.1.0'
  spec.summary           = 'murakumo is the internal DNS server which manages name information using a gossip protocol.'
  spec.require_paths     = %w(lib)
  spec.files             = %w(README) + Dir.glob('bin/**/*') + Dir.glob('lib/**/*')
  spec.author            = 'winebarrel'
  spec.email             = 'sgwr_dts@yahoo.co.jp'
  spec.homepage          = 'https://bitbucket.org/winebarrel/murakumo'
  spec.bindir            = 'bin'
  spec.executables << 'murakumo'
  spec.executables << 'mrkmctl'
  spec.add_dependency('rubydns', '>= 0.3.3')
  spec.add_dependency('rgossip2', '>= 0.1.0')
  spec.add_dependency('optopus', '>= 0.1.4')
end
