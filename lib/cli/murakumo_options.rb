require 'logger'
require 'optopus'
require 'resolv'
require 'socket'

require 'misc/murakumo_const'

unless defined?(Version)
  Version = Murakumo::VERSION
end

def murakumo_parse_args
  optopus do
    desc 'key for authentication (required)'
    option :auth_key, '-K', '--auth-key STRING_OR_PATH', :required => true

    desc 'ip address to bind'
    option :dns_address, '-a', '--address IP', :default => '0.0.0.0' do |value|
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ value or invalid_argument
    end

    desc 'port number of a name service'
    option :dns_port, '-p', '--port NUM', :type => Integer, :default => 53

    desc 'initial node list of gossip protocols'
    option :initial_nodes, '-i', '--initial-nodes IP_LIST', :type => Array, :default => [] do |value|
      value = value.map {|i| i.strip }
      value.all? {|i| /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ i } or invalid_argument
    end

    desc "host's resource record : <ip_addr>[,<hostname>[,<TTL>]] (required)"
    option :host, '-H', '--host RECORD', :type => Array, :required => true do |value|
      (1 <= value.length and value.length <= 3) or invalid_argument

      value = value.map {|i| i.strip }
      ip_addr, hostname, ttl = value

      # ip address
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ ip_addr or invalid_argument

      # hostname
      /\A[0-9a-z\.\-]+\Z/i =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end
    end # :host

    desc 'resource record of an alias: <hostname>[,<TTL>[,{master|secondary|backup}]]'
    option :aliases, '-A', '--alias RECORD', :type => Array, :multiple => true do |value|
      (1 <= value.length and value.length <= 3) or invalid_argument

      value = value.map {|i| i.strip }
      hostname, ttl, priority = value

      # hostname
      /\A[0-9a-z\.\-]+\Z/ =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end

      # Priority
      priority.nil? or /\A(master|secondary|backup)\Z/i =~ priority or invalid_argument
    end # :aliases

    desc 'ip address of a default resolver'
    option :resolver, '-r', '--resolver IP_LIST', :type => Array  do |value|
      value = value.map {|i| i.strip }

      unless value.all? {|i| /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ i }
        invalid_argument
      end
    end

    desc 'path of a socket file'
    option :socket, '-S', '--socket PATH', :default => '/var/tmp/murakumo.sock'

    desc 'maximum number of the IP address returned as a response'
    option :max_ip_num, '-n', '--max-ip-num NUM', :type => Integer, :default => 8 do |value|
      invalid_argument if value < 1
    end

    desc 'suffix of a host name'
    option :domain, '-b', '--domain DOMAIN' do |value|
      invalid_argument if (value || '').strip.empty?
    end

    desc 'command of daemonize: {start|stop|restart|status}'
    option :daemon, '-d', '--daemon CMD', :type => [:start, :stop, :restart, :status]

    desc 'directory of a pid file'
    option :pid_dir, '-f', '--pid-dir PATH'

    desc 'output path of a log'
    option :log_path, '-l', '--log-path PATH'

    desc 'output level of a log'
    option :log_level, '-L', '--log-level LEVEL', :type => [:debug, :info, :warn, :error, :fatal], :default => :info

    desc 'path of a configuration file'
    config_file '-c', '--config PATH'

    desc 'port number of a gossip service'
    option :gossip_port, '-P', '--gossip-port NUM', :type => Integer, :default => 10870

    desc 'lifetime of the node of a gossip protocol'
    option :gossip_node_lifetime, '-T', '--gossip-node-lifetime NUM', :type => Integer, :default => 10

    desc 'transmitting interval of a gossip protocol'
    option :gossip_send_interval, '-I', '--gossip-send-interval NUM', :type => Float, :default => 0.3

    desc 'reception timeout of a gossip protocol'
    option :gossip_receive_timeout, '-O', '--gossip-receive-timeout NUM', :type => Integer, :default => 3

    after do |options|
      # auth_key
      if File.exist?(options[:auth_key])
        options[:auth_key] = File.read(options[:auth_key]).strip
      end

      # resolver
      if options[:resolver]
        options[:resolver] = options[:resolver].map {|i| i.strip }
        options[:resolver] = Resolv::DNS.new(:nameserver => options[:resolver])
      end

      # initial nodes
      if options[:initial_nodes]
        options[:initial_nodes] = options[:initial_nodes].map {|i| i.strip }
      end

      # host
      options[:host] = options[:host].map {|i| i.strip }
      options[:host][1] ||= Socket.gethostname
      options[:host][2] = (options[:host][2] || 60).to_i # TTL

      # aliases
      config_file_aliases = options.config_file ? options.config_file['alias'] : nil

      if config_file_aliases
       if config_file_aliases.kind_of?(Array)
          options[:aliases] = config_file_aliases.map {|i| i.split(',') }
        else
          options[:aliases] = [options[:aliases]]
        end
      end

      options[:aliases] = (options[:aliases] || []).map do |r|
        r = r.map {|i| i.to_s.strip }
        [nil, 60, 'master'].each_with_index {|v, i| r[i] ||= v }

        priority = case r[2].to_s
                   when /master/i
                     Murakumo::MASTER
                   when /secondary/i
                     Murakumo::SECONDARY
                   else
                     Murakumo::BACKUP
                   end

        [
          r[0], # name
          r[1].to_i, # TTL
          priority,
        ]
      end

      # logger
      if not options[:log_path] and options[:daemon]
        options[:log_path] = '/var/log/murakumo.log'
      end

      options[:logger] = Logger.new(options[:log_path] || $stderr)
      options[:logger].level = Logger.const_get(options[:log_level].to_s.upcase)

      # check same hostname
      hostnames = [options[:host][0].downcase] + options[:aliases].map {|i| i[0].downcase }

      if hostnames.length != hostnames.uniq.length
        raise OptionParser::ParseError, 'same hostname was found'
      end

      # health check
      if options.config_file and (health_check = options.config_file['health-check'])
        unless health_check.kind_of?(Hash) and health_check.all? {|k, v| v.has_key?('script') }
          raise OptionParser::ParseError, 'configuration of a health check is not right'
        end
      end
    end

    error do |e|
      abort(e.message)
    end
  end
end
