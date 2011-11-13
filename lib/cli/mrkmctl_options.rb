require 'optopus'

require 'misc/murakumo_const'

Version = '0.1.0'

def parse_args
  optopus do
    desc 'displays a list of a record'
    option :list, '-L', '--list [NAME]'

    desc 'adds or updates a record: <hostname>[,<TTL>[,{master|backup}]]'
    option :add, '-A', '--add RECORD', :type => Array, :multiple => true do |v|
      # XXX:
    end

    desc 'deletes a record'
    option :delete, '-D', '--delete NAME', :multiple => true do |v|
      # XXX:
    end

    desc 'adds a node'
    option :add_node, nil, '--add-node IP_ADDR', :multiple => true do |v|
      # XXX:
    end

    desc 'deletes a node'
    option :delete_node, nil, '--delete-node IP_ADDR', :multiple => true do |v|
      # XXX:
    end

    desc 'sets an attribute: name=value'
    option :set, nil, '--set ATTR', :multiple => true

    desc 'path of a socket file'
    option :socket, '-S', '--socket PATH', :default => '/var/tmp/murakumo.sock'

    after do |options|
      commands = [:list, :add, :delete, :add_node, :delete_node, :set].map {|k|
        [k, options[k]]
      }.select {|i| not i[1].nil? }

      if commands.length < 1
        parse_error('command is not specified', '-L', '-A', '-D', '--add-node', '--delete-node', '--set')
      elsif commands.length > 1
        parse_error('cannot use together', '-L', '-A', '-D', '--add-node', '--delete-node', '--set')
      end

      options[:command] = commands.first
    end

    error do |e|
      abort(e.message)
    end
  end
end
