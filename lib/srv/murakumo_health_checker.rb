require 'timeout'
require 'open3'
require 'resolv-replace'

require 'srv/murakumo_health_check_context'
require 'srv/murakumo_health_check_notifier'
require 'misc/murakumo_const'

module Murakumo

  class HealthChecker

    def initialize(address, name, cloud, logger, options)
      @address = address
      @name = name
      @cloud = cloud
      @logger = logger
      @options = options

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
      @script = options['script']
      raise "health check script of #{@name} is not found" unless @script
      @script = File.read(script) if File.exists?(@script)

      # 通知オブジェクトの設定
      if options[:notification]
        @notifier = HealthCheckNotifier.new(@address, @name, @logger, options[:notification])
      end

      # イベントハンドラの設定
      @on_activate = options['on-activate']
      @on_inactivate = options['on-inactivate']
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
        @cloud.gossip.data.each do |i|
          # 名前の一致するデータを更新
          i[3] = activity if i[0] == @name
        end
      end

      @cloud.db.execute(<<-EOS, activity, @cloud.address, @name)
        UPDATE records SET activity = ?
        WHERE ip_address = ? AND name = ?
      EOS

      @healthy_count = 0
      @unhealthy_count = 0

      status = @normal_health ? 'healthy' : 'unhealthy'
      @logger.info("health condition changed: #{@name}: #{status}")

      case activity
      when ACTIVE
        @notifier.notify_active if @notifier
        handle_event(@on_activate, 'Active') if @on_activate
      when INACTIVE
        @notifier.notify_inactive if @notifier
        handle_event(@on_inactivate, 'Inactive') if @on_inactivate
      end
    end

    def start
      # 各種変数は初期状態にする
      @alive = true
      @normal_health = true
      @healthy_count = 0
      @unhealthy_count = 0

      # 既存のスレッドは破棄
      if @thread and @thread.alive?
        begin
          @thread.kill
        rescue ThreadError
        end
      end

      @thread = Thread.start {
        healthy = 0
        unhealthy = 0

        begin
          while @alive
            retval = nil

            begin
              retval = timeout(@timeout) {
                HealthCheckContext.new(:name => @name, :logger => @logger, :options => @options).instance_eval(@script)
              }
            rescue Timeout::Error
              retval = false
            rescue => e
              retval = false
              message = (["#{e.class}: #{e.message}"] + (e.backtrace || [])).join("\n\tfrom ")
              @logger.error("healthcheck failed: #{@name}: #{message}")
            end

            status = retval == true ? 'good' : retval == false ? 'bad' : '-'
            @logger.debug("result of a health check: #{@name}: #{status}")

            if retval == true
              good
            elsif retval == false
              bad
            end

            sleep @interval
          end # while
        rescue Exception => e
          message = (["#{e.class}: #{e.message}"] + (e.backtrace || [])).join("\n\tfrom ")
          @logger.error("#{@name}: #{message}")
        end # begin
      }
    end

    def stop
      @alive = false
    end

    def alive?
      @alive
    end

    private

    def handle_event(handler, status)
      Open3.popen3("#{@on_activate} '#{@address}' '#{@name}' '#{status}'") do |stdin, stdout, stderr|
        out = stdout.read.strip
        @logger.info(out) unless out.empty?

        err = stderr.read.strip
        @logger.error(err) unless err.empty?
      end
    rescue Exception => e
      message = (["#{e.class}: #{e.message}"] + (e.backtrace || [])).join("\n\tfrom ")
      @logger.error("#{@name}: #{message}")
    end

  end # HealthChecker

end # Murakumo
