require 'net/http'
require 'socket'

require 'misc/murakumo_const'

module Murakumo

  # ヘルスチェックのコンテキスト
  class HealthCheckerContext

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
    has_mysql = false

    begin
      require 'mysql'
      has_mysql = true
    rescue LoadError
      begin
        require 'mysql2'
        has_mysql = true
      rescue LoadError
      end
    end

    if has_mysql
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
      rescue
        false
      end
    end

  end # HealthCheckerContext

end # Murakumo
