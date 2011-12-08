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

    desc 'resource record of an alias: <hostname>[,<TTL>[,{master|secondary|backup}[, <weight>]]]'
    option :aliases, '-A', '--alias RECORD', :type => Array, :multiple => true do |value|
      (1 <= value.length and value.length <= 4) or invalid_argument

      value = value.map {|i| i.strip }
      hostname, ttl, priority, weight = value

      # hostname
      /\A[0-9a-z\.\-]+\Z/ =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end

      # Priority
      priority.nil? or /\A(master|secondary|backup)\Z/i =~ priority or invalid_argument

      # Weight
      unless weight.nil? or (/\A\d+\Z/ =~ weight and weight.to_i > 0)
        invalid_argument
      end
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

    desc 'enables the cache of a response'
    option :enable_cache, '-e', '--enable-cache'

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
        [nil, 60, 'master', 100].each_with_index {|v, i| r[i] ||= v }

        priority = case r[2].to_s
                   when /master/i
                     Murakumo::MASTER
                   when /secondary/i
                     Murakumo::SECONDARY
                   else
                     Murakumo::BACKUP
                   end

        [
          r[0],      # name
          r[1].to_i, # TTL
          priority,
          r[3].to_i, # weight
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
        parse_error('same hostname was found')
      end

      # health check
      if options.config_file and (health_check = options.config_file['health-check'])
        health_check.kind_of?(Hash) or parse_error('configuration of a health check is not right')

        health_check.each do |name, conf|
          if (conf['script'] || '').empty?
            parse_error('configuration of a health check is not right', "#{name}/script")
          end

          %w(on-activate on-inactivate).each do |key|
            next unless conf[key]
            path = conf[key] = conf[key].strip

            if FileTest.directory?(path) or not FileTest.executable?(path)
              parse_error('configuration of a health check is not right', "#{name}/#{key}")
            end
          end
        end
      end # health check

      # notification
      if options.config_file and (ntfc = options.config_file['notification'])
        ntfc.kind_of?(Hash) or parse_error('configuration of a notification is not right')

        if (ntfc['host'] || '').empty?
          parse_error('configuration of a notification is not right', 'host')
        end

        unless ntfc['recipients']
          parse_error('configuration of a notification is not right', 'recipients')
        end

        %w(port open_timeout read_timeout).each do |key|
          if ntfc[key] and /\A\d+\Z/ !~ ntfc[key].to_s
            parse_error('configuration of a notification is not right', key)
          end
        end

        ntfc_args = [ntfc['host']]
        ntfc_args << ntfc['port'].to_i if ntfc['port']
        ntfc_args << ntfc['account'] if ntfc['account']
        ntfc_args << ntfc['password'] if ntfc['password']

        options[:notification] = ntfc_h = {:args => ntfc_args}

        ntfc_h[:sender] = ntfc['sender'] || 'murakumo@localhost.localdomain'

        if ntfc['recipients'].kind_of?(Array)
          ntfc_h[:recipients] = ntfc['recipients']
        else
          ntfc_h[:recipients] = ntfc['recipients'].to_s.split(/\s*,\s*/).select {|i| not i.empty? }
        end

        ntfc_h[:open_timeout] = ntfc['open_timeout'].to_i if ntfc['open_timeout']
        ntfc_h[:read_timeout] = ntfc['read_timeout'].to_i if ntfc['read_timeout']
      end # notification

      # {name,addr}-{includes,excludes}
      if options.config_file
        %w(name-includes name-excludes addr-includes addr-excludes).each do |key|
          unless (reg_vals = (options.config_file[key] || '').strip).empty?
            reg_vals = reg_vals.split(/\s*,\s*/).select {|i| not i.empty? }.map {|i| Regexp.new(i.strip, Regexp::IGNORECASE) }
            options[key.gsub('-', '_').to_sym] = reg_vals
          end
        end
      end # {name,addr}-{includes,excludes}

      # balancing
      if options.config_file and (balancing = options.config_file['balancing'])
        balancing = balancing.donwcase

        unless %w(random fix_by_host fix_by_addr).include?(balancing)
          parse_error('configuration of a balancing is not right')
        end

        options[:balancing] = balancing.to_sym
      else
        options[:balancing] = :random
      end # balancing

    end # after

    error do |e|
      abort(e.message)
    end
  end
end
