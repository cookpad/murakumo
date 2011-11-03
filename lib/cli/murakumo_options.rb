require 'optopus'
require 'socket'

Version = '0.1.0'

def parse_args
  optopus do
    desc 'resource record: <ip_addr>,<hostname>[,<TTL>[,weight[,{MASTER,BACKUP}]]] (required)'
    option :record, '-R', '--record RR', :type => Array, :required => true do |value|
      ip_addr, hostname, ttl, weight, master_backup = value

      # ip address
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ ip_addr or invalid_argument

      # hostname
      /\A[0-9a-z\.\-]+\Z/ =~ hostname or invalid_argument

      # TTL
      ttl.nil? or /\A\d+\Z/ =~ ttl or invalid_argument

      # Weight
      weight.nil? or /\A\d+\Z/ =~ weight or invalid_argument

      # MASTER or BACKUP
      master_backup.nil? or /\A(MASTER|BACKUP)\Z/i =~ master_backup or invalid_argument
    end # :record

    desc 'key for authentication (required)'
    option :record, '-K', '--auth-key STRING', :required => true

    desc 'ip address to bind'
    option :dns_port, '-a', '--address IP', :default => '0.0.0.0' do |value|
      /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\Z/ =~ value or invalid_argument
    end

    desc 'port number of a name service'
    option :dns_port, '-p', '--port NUM', :type => Integer, :default => 53

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
    option :gossip_interval, nil, '--gossip-interval NUM', :type => Float, :default => 0.1

    desc 'reception timeout of a gossip protocol'
    option :gossip_receive_timeout, nil, '--gossip-receive-timeout NUM', :type => Integer, :default => 3

    after do |options|
      record = options[:record]
      [nil, nil, 300, 1, :MASTER].each_with_index {|v, i| record[i] ||= v }
      record[2] = record[2].to_i # TTL
      record[3] = record[3].to_i # Weight
      record[4] = record[4].to_s.upcase.to_sym # MASTER or BACKUP
    end

    error do |e|
      abort(e.message)
    end
  end
end
