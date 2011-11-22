Gem::Specification.new do |spec|
  spec.name              = 'murakumo'
  spec.version           = '0.2.2'
  spec.summary           = 'Murakumo is the internal DNS server which manages name information using a gossip protocol.'
  spec.require_paths     = %w(lib)
  spec.files             = %w(README) + Dir.glob('bin/**/*') + Dir.glob('lib/**/*') + Dir.glob('etc/**/*')
  spec.author            = 'winebarrel'
  spec.email             = 'sgwr_dts@yahoo.co.jp'
  spec.homepage          = 'https://bitbucket.org/winebarrel/murakumo'
  spec.bindir            = 'bin'
  spec.executables << 'murakumo'
  spec.executables << 'mrkmctl'
  spec.executables << 'murakumo-install-init-script'
  spec.add_dependency('rubydns', '~> 0.3.3')
  spec.add_dependency('rgossip2', '>= 0.1.7')
  spec.add_dependency('optopus', '>= 0.2.1')
  spec.add_dependency('sqlite3-ruby', '~> 1.2.5')
end
