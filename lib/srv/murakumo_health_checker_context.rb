require 'net/http'
require 'socket'

require 'misc/murakumo_const'

module Murakumo

  # ヘルスチェックのコンテキスト
  class HealthCheckerContext

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
    rescue Exception
      return false
    end

    # HTTPチェッカー
    def http_get(path, statuses = [200], host = '127.0.0.1', port = 80)
      res = Net::HTTP.start('127.0.0.1', 80) do |http|
        http.get(path)
      end

      statuses.include?(res.code.to_i)
    rescue Exception
      return false
    end

    # MySQLのドライバがあれば、MySQLチェッカーを定義
    mysql_class = nil

    begin
      require 'mysql'
      mysql_class = Mysql
    rescue LoadError
      begin
        require 'mysql2'
        mysql_class = Mysql2::Client
      rescue LoadError
      end
    end

    if mysql_class
      class_eval <<-EOS
        def mysql_check(user, passwd = nil, port_sock = 3306, host = '127.0.0.1', db = nil)
          port = nil
          sock = nil

          if port_sock.kind_of?(Integer)
            port = port_sock
          else
            sock = port_sock
          end

          my = #{mysql_class}.new(host, user, passwd, db, port, sock)
          !!(my.respond_to?(:ping) ? my.ping : my.stat)
        rescue => e
          @logger.debug(e.message)
          false
        end
      EOS
    end

  end # HealthCheckerContext

end # Murakumo
