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

  end # HealthCheckerContext

end # Murakumo
