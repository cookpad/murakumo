require 'optopus'

require 'misc/murakumo_const'

Version = '0.1.0'

def parse_args
  optopus do
    desc 'displays a list of a record'
    option :list, '-L', '--list [NAME]'

    desc 'adds or updates a record: <hostname>[,<TTL>[,{master|backup}]]'
    option :add, '-A', '--add RECORD', :type => Array, :multiple => true do |value|
      (1 <= value.length and value.length <= 3) or invalid_argument

      hostname, ttl, master_backup = value

      # hostname
      /\A[0-9a-z\.\-]+\Z/i =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end

      # MASTER or BACKUP
      master_backup.nil? or /\A(master|backup)\Z/i =~ master_backup or invalid_argument
    end

    desc 'deletes a record'
    option :delete, '-D', '--delete NAME', :multiple => true do |value|
      /\A[0-9a-z\.\-]+\Z/ =~ value or invalid_argument
    end

    desc 'adds a node'
    option :add_node, nil, '--add-node HOST', :multiple => true do |value|
      unless [/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/, /\A[0-9a-z\.\-]+\Z/i].any? {|i| i =~ value }
        invalid_argument
      end
    end

    desc 'deletes a node'
    option :delete_node, nil, '--delete-node HOST', :multiple => true do |value|
      unless [/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/, /\A[0-9a-z\.\-]+\Z/i].any? {|i| i =~ value }
        invalid_argument
      end
    end

    desc 'sets an attribute: name=value'
    option :set, nil, '--set ATTR', :multiple => true

    desc 'path of a socket file'
    option :socket, '-S', '--socket PATH', :default => '/var/tmp/murakumo.sock'

    after do |options|
      # add
      if options[:add]
        options[:add] = options[:add].map do |r|
          r = r.map {|i| i.to_s.strip }
          [nil, 60, 'master'].each_with_index {|v, i| r[i] ||= v }

          [
            r[0], # name
            r[1].to_i, # TTL
            ((/master/i =~ r[2].to_s) ? Murakumo::MASTER : Murakumo::BACKUP),
          ]
        end
      end

      # 一応、uniq
      [:delete, :add_node, :delete_node].each do |key|
        if options[key]
          options[key] = options[key].uniq
        end
      end

      # command
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
