require 'logger'
require 'optopus'
require 'rubydns'
require 'socket'

require 'cli/murakumo_initializer_context'
require 'misc/murakumo_const'

unless defined?(Version)
  Version = Murakumo::VERSION
end

def murakumo_parse_args
  optopus do
    before do |options|
      if (script = options['init-script'])
        script = File.read(script) if File.exists?(script)
        Murakumo::InitializerContext.new(options).instance_eval(script)
      end
    end

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

    desc 'var directory path'
    option :working_dir, '-w', '--working-dir PATH', :default => '/var'

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

    desc 'verifies communication of initial nodes'
    option :ping_init_nodes, '-V', '--ping-init-nodes', :default => false

    desc 'delay of a gossip start'
    option :gossip_start_delay, '-D', '--gossip-start-delay', :type => Integer, :default => 0

    after do |options|
      # auth_key
      if File.exist?(options[:auth_key])
        options[:auth_key] = File.read(options[:auth_key]).strip
      end

      # resolver
      if options[:resolver]
        servers = []
        options[:resolver].each do |addr|
          [:udp, :tcp].each {|prot| servers << [prot, addr.strip, 53] }
        end
        options[:resolver] = RubyDNS::Resolver.new(servers)
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
      if options[:aliases]
        unless options[:aliases].kind_of?(Array)
          parse_error('configuration of a aliases is not right')
        end

        # 設定ファイルからの設定の場合は「配列の配列」に変換
        if options[:aliases][0].kind_of?(String)
          options[:aliases] = options[:aliases].map {|i| i.split(',') }
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
      else
        options[:aliases] = []
      end # aliases

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

      # ping init nodes
      if options[:ping_init_nodes]
        options[:ping_init_nodes] = !!options[:ping_init_nodes]
      end

      # health check
      if (health_check = options[:health_check])
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

          conf['init-status'] ||= 'active'

          unless /\A(active|inactive)\Z/i =~ conf['init-status']
            parse_error('configuration of a health check is not right', "#{name}/init-status")
          end

          if conf['init-status'] =~ /\Aactive\Z/i
            conf['init-status'] = Murakumo::ACTIVE
          else
            conf['init-status'] = Murakumo::INACTIVE
          end

          # 各種変数の設定
          {
            'interval'  => [ 5, 1, 300],
            'timeout'   => [ 5, 1, 300],
            'healthy'   => [ 2, 1,  60],
            'unhealthy' => [ 2, 1,  60],
          }.each {|key, vals|
            defval, min, max = vals
            value = (conf[key] || defval).to_i

            if value < min
              value = min
              parse_error("health-check/#{name}/#{key} is smaller than #{min}.", "#{name}/#{key}")
            elsif value > max
              value = max
              parse_error("health-check/#{name}/#{key} is larger than #{max}.", "#{name}/#{key}")
            end

            conf[key] = value
          }
        end
      end # health check

      # activity check
      if (activity_check = options[:activity_check])
        activity_check.kind_of?(Hash) or parse_error('configuration of a activity check is not right')

        activity_check.each do |name, conf|
          # 'on-activate'か'on-inactivate'のいずれかが必須
          if (conf['on-activate'] || conf['on-inactivate'] || '').empty?
            parse_error('configuration of a health check is not right', "on-activate or on-inactivate is not defined")
          end

          conf['init-status'] ||= 'undefined'

          unless /\A(active|inactive|undefined)\Z/i =~ conf['init-status']
            parse_error('configuration of a health check is not right', "#{name}/init-status")
          end

          conf['init-status'] = conf['init-status'].downcase.to_sym

          %w(on-activate on-inactivate).each do |key|
            next unless conf[key]
            path = conf[key] = conf[key].strip

            if FileTest.directory?(path) or not FileTest.executable?(path)
              parse_error('configuration of a health check is not right', "#{name}/#{key}")
            end
          end

          # 各種変数の設定
          {
            'interval'    => [ 10, 1, 300],
            'start-delay' => [ 60, 1, 300],
            'active'      => [  2, 1,  60],
            'inactive'    => [  2, 1,  60],
          }.each {|key, vals|
            defval, min, max = vals
              value = (conf[key] || defval).to_i

            if value < min
              value = min
              parse_error("activateation-check/#{name}/#{key} is smaller than #{min}.", "#{name}/#{key}")
            elsif value > max
              value = max
              parse_error("activation-check/#{name}/#{key} is larger than #{max}.", "#{name}/#{key}")
            end

            conf[key] = value
          }
        end
      end # activity check

      # notification
      if (ntfc = options[:notification])
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
      [:name_includes, :name_excludes, :addr_includes, :addr_excludes].each do |key|
        unless (reg_vals = (options[key] || '').strip).empty?
          reg_vals = reg_vals.split(/\s*,\s*/).select {|i| not i.empty? }.map {|i| Regexp.new(i.strip, Regexp::IGNORECASE) }
          options[key] = reg_vals
        else
          options.delete(key)
        end
      end # {name,addr}-{includes,excludes}

      # balancing
      if (balancing = options[:balancing])
        balancing.kind_of?(Hash) or parse_error('configuration of a balancing is not right')
        balancing_h = options[:balancing] = {}

        balancing.map {|k, v| [k.to_s.strip.downcase, v] }.each do |dest, attrs|
          if dest.empty? or attrs.empty?
            parse_error('configuration of a balancing is not right', dest)
          end

          unless attrs.kind_of?(Hash)
            parse_error('configuration of a balancing is not right', dest)
          end

          attrs_algorithm = (attrs['algorithm'] || 'random').strip.downcase
          attrs_max_ip_num = attrs['max-ip-num']
          attrs_sources = (attrs['sources'] || '').strip.split(/\s*,\s*/).map {|i| i.strip }

          unless %w(random fix_by_src fix_by_src2).include?(attrs_algorithm)
            parse_error('configuration of a balancing is not right', dest)
          end

          unless attrs_max_ip_num.nil? or (/\A\d+\Z/ =~ attrs_max_ip_num.to_s and attrs_max_ip_num.to_i > 0)
            parse_error('configuration of a balancing is not right', dest)
          end

          unless attrs_sources.empty? or attrs_sources.all? {|i| /\A[0-9a-z\.\-]+\Z/ =~ i }
            parse_error('configuration of a balancing is not right', dest)
          end

          reg_dest = Regexp.new(dest, Regexp::IGNORECASE)

          attrs_h = {
            :algorithm  => attrs_algorithm.to_sym,
            :max_ip_num => (attrs_max_ip_num || options[:max_ip_num]).to_i
          }

          case attrs_algorithm
          when 'random'
            parse_error('configuration of a balancing is not right', dest) unless attrs_sources.empty?
          when 'fix_by_src', 'fix_by_src2'
            parse_error('configuration of a balancing is not right', dest) if attrs_sources.empty?
            attrs_h[:sources] = attrs_sources
          end

          balancing_h[reg_dest] = attrs_h
        end
      end # balancing

      # on start
      if (on_start = options[:on_start])
        unless File.exist?(on_start)
          parse_error('on_start script is not found')
        end
      end # on start
    end # after

    error do |e|
      abort(e.message)
    end
  end
end
