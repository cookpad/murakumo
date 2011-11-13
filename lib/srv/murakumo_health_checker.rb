require 'socket'
require 'timeout'
require 'resolv-replace'

require 'misc/murakumo_const'

module Murakumo

  class HealthChecker

    # ヘルスチェックのコンテキスト
    class Context

      # TCPチェッカー
      def tcp_check(port, host = '127.0.0.1')
        s = TCPSocket.new(host, port)
        s.close
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        return false
      end

    end # Context

    def initialize(cloud, logger, options)
      @cloud = cloud
      @logger = logger

      # 各種変数の設定
      {
        'interval'  => [30, 1, 300],
        'timeout'   => [ 5, 1, 300],
        'healthy'   => [10, 2,  10],
        'unhealthy' => [ 2, 2,  10],
      }.each {|key, vals|
        defval, min, max = vals
        value = (options[key] || defval).to_i
        value = min if value < min
        value = max if value > max
        instance_variable_set("@#{key}", value)
      }

      # スクリプトの読み込み
      @script = options.fetch('script')
      @script = File.read(script) if File.exists?(@script)

      @alive = true
      @normal_health = true
      @healthy_count = 0
      @unhealthy_count = 0
    end

    def good
      if @normal_health
        @unhealthy_count = 0
      elsif (@healthy_count += 1) >= @healthy
        toggle_health
      end
    end

    def bad
      if not @normal_health
        @healthy_count = 0
      elsif (@unhealthy_count += 1) >= @unhealthy
        toggle_health
      end
    end

    def toggle_health
      @normal_health = !@normal_health
      activity = (@normal_health ? ACTIVE : INACTIVE)

      @cloud.gossip.transaction do
        @cloud.gossip.data.each {|i| i[3] = activity }
      end

      @cloud.db.execute(<<-EOS, activity, @cloud.address)
        UPDATE records SET activity = ?
        WHERE ip_address = ?
      EOS

      @healthy_count = 0
      @unhealthy_count = 0

      if @logger
        status = @normal_health ? 'healthy' : 'unhealthy'
        @logger.info("health condition changed: #{status}")
      end
    end

    def start
      @thread = Thread.start {
        healthy = 0
        unhealthy = 0

        begin
          while @alive
            retval = nil

            begin
              retval = timeout(@timeout) {
                Context.new.instance_eval(@script)
              }
            rescue Timeout::Error
              retval = false
            end

            if @logger
              status = retval == true ? 'good' : retval == false ? 'bad' : '-'
              @logger.debug("result of a health check: #{status}")
            end

            if retval == true
              good
            elsif retval == false
              bad
            end

            sleep @interval
          end # while
        rescue Exception => e
          message = (["#{e.class}: #{e.message}"] + (e.backtrace || [])).join("\n\tfrom ")

          if @logger
            @logger.error(message)
          else
            $stderr.puts(message)
          end
        end # begin
      }
    end

    def stop
      @alive = false
    end

    def alive?
      @alive
    end
  end # HealthChecker

end # Murakumo
