require 'net/http'
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
    def http_get(path, statuses = [200], host = '127.0.0.1', port = 80)
      res = Net::HTTP.start('127.0.0.1', 80) do |http|
        http.read_timeout = @options['timeout']
        http.get(path)
      end

      statuses.include?(res.code.to_i)
    rescue => e
      @logger.debug("#{@name}: #{e.message}")
      return false
    end

    # MySQLのドライバがあれば、MySQLチェッカーを定義
    mysql_class = nil

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

        my = Mysql.new(host, user, passwd, db, port, sock)
        !!(my.respond_to?(:ping) ? my.ping : my.stat)
      rescue => e
        @logger.debug("#{@name}: #{e.message}")
        return false
      ensure
        my.close if my
      end
    rescue LoadError
    end

    begin
      require 'mysql2'

      def mysql_check(user, passwd = nil, port_sock = 3306, host = '127.0.0.1', db = nil)
        opts = {}
        opts[:username] = user
        opts[:password] = passwd if passwd
        opts[:host]     = host if host
        opts[:database] = db if db

        if port_sock.kind_of?(Integer)
          opts[:port] = port_sock
        else
          opts[:socket] = port_sock
        end

        my = Mysql2::Client.new(opts)
        my.ping
      rescue => e
        @logger.debug("#{@name}: #{e.message}")
        return false
      ensure
        my.close if my
      end
    rescue LoadError
    end

  end # HealthCheckContext

end # Murakumo
