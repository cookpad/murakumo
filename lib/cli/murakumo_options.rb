require 'logger'
require 'optopus'
require 'resolv'

require 'misc/murakumo_const'

Version = '0.1.0'

def parse_args
  optopus do
    desc 'resource record: <ip_addr>,<hostname>[,<TTL>[,weight[,{master|backup}]]] (required)'
    option :record, '-R', '--record RR', :type => Array, :required => true do |value|
      ip_addr, hostname, ttl, weight, master_backup = value

      # ip address
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ ip_addr or invalid_argument

      # hostname
      /\A[0-9a-z\.\-]+\Z/ =~ hostname or invalid_argument

      # TTL
      unless ttl.nil? or (/\A\d+\Z/ =~ ttl and ttl.to_i > 0)
        invalid_argument
      end

      # Weight
      weight.nil? or /\A\d+\Z/ =~ weight or invalid_argument

      # MASTER or BACKUP
      master_backup.nil? or /\A(master|backup)\Z/i =~ master_backup or invalid_argument
    end # :record

    desc 'key for authentication (required)'
    option :auth_key, '-K', '--auth-key STRING', :required => true

    desc 'ip address to bind'
    option :dns_address, '-a', '--address IP', :default => '0.0.0.0' do |value|
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ value or invalid_argument
    end

    desc 'port number of a name service'
    option :dns_port, '-p', '--port NUM', :type => Integer, :default => 53

    desc 'initial node list of gossip protocols'
    option :initial_nodes, '-i', '--initial-nodes IP_LIST', :type => Array, :default => [] do |value|
      value.all? {|i| /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ i } or invalid_argument
    end

    desc 'path of a socket file'
    option :socket, '-S', '--socket SOCK', :default => '/var/tmp/murakumo.sock'

    desc 'ip address of a default resolver'
    option :resolver, '-r', '--resolver IP'  do |value|
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ value or invalid_argument
    end

    desc 'path of a socket file'
    option :socket, '-S', '--socket PATH', :default => '/var/tmp/murakumo.sock'

    desc 'command of daemonize: {start|stop|restart|status}'
    option :daemon, '-d', '--daemon CMD', :type => [:start, :stop, :restart, :status]

    desc 'output path of a log'
    option :log_path, '-l', '--log-path PATH', :default => '/var/log/murakumo.log'

    desc 'output level of a log'
    option :log_level, '-L', '--log-level LEVEL', :type => [:debug, :info, :warn, :error, :fatal], :default => :info

    desc 'path of a configuration file'
    config_file '-c', '--config PATH'

    desc 'path of the configuration file of a health check'
    option :health_check, '-H', '--health-check PATH'

    desc 'port number of a gossip service'
    option :gossip_port, nil, '--gossip-port NUM', :type => Integer, :default => 10870

    desc 'lifetime of the node of a gossip protocol'
    option :gossip_node_lifetime, nil, '--gossip-node-lifetime NUM', :type => Integer, :default => 10

    desc 'transmitting interval of a gossip protocol'
    option :gossip_send_interval, nil, '--gossip-send-interval NUM', :type => Float, :default => 0.1

    desc 'reception timeout of a gossip protocol'
    option :gossip_receive_timeout, nil, '--gossip-receive-timeout NUM', :type => Integer, :default => 3

    after do |options|
      # resource record
      record = options[:record]
      [nil, nil, 60, 100, 'master'].each_with_index {|v, i| record[i] ||= v }
      record[2] = record[2].to_i # TTL
      record[3] = record[3].to_i # Weight
      record[4] = (/master/i =~ record[4]) ? Murakumo::MASTER : Murakumo::BACKUP

      # resolver
      if options[:resolver]
        options[:resolver] = Resolv::DNS.new(:nameserver => options[:resolver])
      end

      # logger
      options[:logger] = Logger.new(options[:log_path])
      options[:logger].level = Logger.const_get(options[:log_level].to_s.upcase)
    end

    error do |e|
      abort(e.message)
    end
  end
end
