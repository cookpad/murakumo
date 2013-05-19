require 'net/http'
require 'net/smtp'
require 'net/telnet'
require 'socket'

require 'misc/murakumo_const'

module Murakumo

  # ヘルスチェックのコンテキスト
  class HealthCheckContext

    def initialize(vars = {})
      vars.each do |name, val|
        instance_variable_set("@#{name}", val)
      end
    end

    # TCPチェッカー
    def tcp_check(port, host = '127.0.0.1')
      s = TCPSocket.new(host, port)
      s.close
      return true
    rescue => e
      @logger.debug("#{@name}: #{e.message}")
      return false
    end

    # HTTPチェッカー
    def http_get(path, statuses = [200], port = 80, host = '127.0.0.1')
      res = Net::HTTP.start(host, port) do |http|
        http.read_timeout = @options['timeout']
        http.get(path)
      end

      statuses.include?(res.code.to_i)
    rescue => e
      @logger.debug("#{@name}: #{e.message}")
      return false
    end

    # SMTPチェッカー
    def smtp_check(*args)
      Net::SMTP.start(*args) {|smtp| true }
    rescue => e
      @logger.debug("#{@name}: #{e.message}")
      return false
    end

    # memcachedチェッカー
    def memcached_check(port = 11211, host = '127.0.0.1')
      telnet = Net::Telnet.new('Host' => host, 'Port' => port)
      !!telnet.cmd('String' => 'stats', 'Match' => /END/i, 'Timeout' => @options['timeout'])
    rescue =>e 
      @logger.debug("#{@name}: #{e.message}")
      return false
    ensure
      if telnet
        telnet.close rescue nil
      end
    end

    # MySQLチェッカー
    begin
      require 'mysql2/em'

      def mysql_check(user, passwd = nil, port_sock = 3306, host = '127.0.0.1', db = nil)
        opts = {}
        opts[:username] = user
        opts[:password] = passwd if passwd
        opts[:host]     = host if host
        opts[:database] = db if db
        opts[:connect_timeout] = @options['timeout']

        if port_sock.kind_of?(Integer)
          opts[:port] = port_sock
        else
          opts[:socket] = port_sock
        end

        my = Mysql2::EM::Client.new(opts)
        my.ping
      rescue => e
        @logger.debug("#{@name}: #{e.message}")
        return false
      ensure
        if my
          my.close rescue nil
        end
      end
    rescue LoadError
    end

    unless method_defined?(:mysql_check)
      begin
        require 'mysql'

        def mysql_check(user, passwd = nil, port_sock = 3306, host = '127.0.0.1', db = nil)
          port = nil
          sock = nil

          if port_sock.kind_of?(Integer)
            port = port_sock
          else
            sock = port_sock
          end

          my = Mysql.init
          my.options(Mysql::OPT_CONNECT_TIMEOUT, @options['timeout'])
          my.connect(host, user, passwd, db, port, sock)
          !!(my.respond_to?(:ping) ? my.ping : my.stat)
        rescue => e
          @logger.debug("#{@name}: #{e.message}")
          return false
        ensure
          if my
            my.close rescue nil
          end
        end
      rescue LoadError
      end
    end # unless defined?(:mysql_check)

  end # HealthCheckContext

end # Murakumo
