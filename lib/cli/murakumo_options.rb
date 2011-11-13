require 'logger'
require 'optopus'
require 'resolv'

require 'misc/murakumo_const'

Version = '0.1.0'

def parse_args
  optopus do
    desc 'key for authentication (required)'
    option :auth_key, '-K', '--auth-key STRING', :required => true

    desc 'ip address to bind'
    option :dns_address, '-a', '--address IP', :default => '0.0.0.0' do |value|
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ value or invalid_argument
    end

    desc 'port number of a name service'
    option :dns_port, '-p', '--port NUM', :type => Integer, :default => 53

    desc 'initial node list of gossip protocols'
    option :initial_nodes, '-I', '--initial-nodes IP_LIST', :type => Array, :default => [] do |value|
      value.all? {|i| /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ i } or invalid_argument
    end

    desc "host's resource record : <ip_addr>[,<hostname>[,<TTL>]] (required)"
    option :host, '-H', '--host RECORD', :type => Array, :required => true do |value|
      value.length <= 3 or invalid_argument

      ip_addr, hostname, ttl = value

      # ip address
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ ip_addr or invalid_argument

      # hostname
      /\A[0-9a-z\.\-]+\Z/ =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end
    end # :host

    desc 'resource record of an alias: <hostname>[,<TTL>[,{master|backup}]]'
    option :aliases, '-A', '--alias RECORD', :type => Array, :multiple => true do |value|
      value.length <= 4 or invalid_argument

      hostname, ttl, master_backup = value

      # hostname
      /\A[0-9a-z\.\-]+\Z/ =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end

      # MASTER or BACKUP
      master_backup.nil? or /\A(master|backup)\Z/i =~ master_backup or invalid_argument
    end # :aliases

    desc 'ip address of a default resolver'
    option :resolver, nil, '--resolver IP'  do |value|
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ value or invalid_argument
    end

    desc 'path of a socket file'
    option :socket, nil, '--socket PATH', :default => '/var/tmp/murakumo.sock'

    desc 'maximum number of the IP address returned as a response'
    option :max_ip_num, nil, '--max-ip-number NUM', :type => Integer, :default => 8 do |value|
      invalid_argument if value < 1
    end

    desc 'command of daemonize: {start|stop|restart|status}'
    option :daemon, '-d', '--daemon CMD', :type => [:start, :stop, :restart, :status]

    desc 'output path of a log'
    option :log_path, '-l', '--log-path PATH'

    desc 'output level of a log'
    option :log_level, '-L', '--log-level LEVEL', :type => [:debug, :info, :warn, :error, :fatal], :default => :info

    desc 'path of a configuration file'
    config_file '-c', '--config PATH'

    desc 'port number of a gossip service'
    option :gossip_port, nil, '--gossip-port NUM', :type => Integer, :default => 10870

    desc 'lifetime of the node of a gossip protocol'
    option :gossip_node_lifetime, nil, '--gossip-node-lifetime NUM', :type => Integer, :default => 10

    desc 'transmitting interval of a gossip protocol'
    option :gossip_send_interval, nil, '--gossip-send-interval NUM', :type => Float, :default => 0.3

    desc 'reception timeout of a gossip protocol'
    option :gossip_receive_timeout, nil, '--gossip-receive-timeout NUM', :type => Integer, :default => 3

    after do |options|
      # host
      options[:host][2] = (options[:host][2] || 60).to_i # TTL

      # aliases
      options[:aliases] = (options[:aliases] || []).map do |r|
        [nil, 60, 'master'].each_with_index {|v, i| r[i] ||= v }

        [
          r[0],      # name
          r[1].to_i, # TTL
          ((/master/i =~ r[2]) ? Murakumo::MASTER : Murakumo::BACKUP),
        ]
      end

      # resolver
      if options[:resolver]
        options[:resolver] = Resolv::DNS.new(:nameserver => options[:resolver])
      end

      # logger
      options[:logger] = Logger.new(options[:log_path] || $stderr)
      options[:logger].level = Logger.const_get(options[:log_level].to_s.upcase)
    end

    error do |e|
      abort(e.message)
    end
  end
end
