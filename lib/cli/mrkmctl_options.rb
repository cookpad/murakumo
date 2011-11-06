require 'optopus'

require 'misc/murakumo_const'

Version = '0.1.0'

def parse_args
  optopus do
    desc 'path of a socket file'
    option :socket, '-S', '--socket PATH', :default => '/var/tmp/murakumo.sock'

    error do |e|
      abort(e.message)
    end
  end
end
