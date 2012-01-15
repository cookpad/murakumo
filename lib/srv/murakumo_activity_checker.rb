require 'open3'

require 'srv/murakumo_activity_check_notifier'
require 'misc/murakumo_const'

module Murakumo

  class ActivityChecker

    def initialize(address, name, cloud, logger, options)
      @address = address
      @name = name
      @cloud = cloud
      @logger = logger
      @options = options

      # 各種変数の設定
      {
        'interval'    => [  5, 1, 300],
        'start-delay' => [ 60, 1, 300],
        'active'      => [  2, 1,  10],
        'inactive'    => [  2, 1,  10],
      }.each {|key, vals|
        defval, min, max = vals
        value = (options[key] || defval).to_i

        if value < min
          value = min
          @logger.warn("activateation-check/#{@name}/#{key} is smaller than #{min}. it was changed into #{min}.")
        elsif value > max
          value = max
          @logger.warn("activation-check/#{@name}/#{key} is larger than #{max}. it was changed into #{max}.")
        end

        instance_variable_set("@#{key.gsub('-', '_')}", value)
      }

      # 通知オブジェクトの設定
      if options[:notification]
        @notifier = ActivityCheckNotifier.new(@address, @name, @logger, options[:notification])
      end

      # イベントハンドラの設定
      @on_activate = options['on-activate']
      @on_inactivate = options['on-inactivate']
    end

    def mark_active
      if @activated.nil?
        # 状態がなかったら、まず状態をセット
        @logger.info("initial activity: #{@name}: active")
        @activated = true
      elsif @activated == true # わざとですよ…
        @inactive_count = 0
      elsif (@active_count += 1) >= @active
        toggle_activity
      end
    end

    def mark_inactive
      if @activated.nil?
        # 状態がなかったら、まず状態をセット
        @logger.info("initial activity: #{@name}: inactive")
        @activated = false
      elsif @activated == false # わざとですよ…
        @active_count = 0
      elsif (@inactive_count += 1) >= @inactive
        toggle_activity
      end
    end

    def toggle_activity
      @activated = !@activated
      @active_count = 0
      @inactive_count = 0

      status = @activated ? 'active' : 'inactive'
      @logger.info("activity condition changed: #{@name}: #{status}")

      if @activated
        @notifier.notify_active if @notifier
        handle_event(@on_activate, 'active') if @on_activate
      else
        @notifier.notify_inactive if @notifier
        handle_event(@on_inactivate, 'inactive') if @on_inactivate
      end
    end

    def start
      # 各種変数は初期状態にする
      @alive = true
      @activated = nil # アクティビティの初期状態はnil
      @active_count = 0
      @inactive_count = 0

      # 既存のスレッドは破棄
      if @thread and @thread.alive?
        begin
          @thread.kill
        rescue ThreadError
        end
      end

      @thread = Thread.start {
        begin
          # 初回実行の遅延
          if @start_delay
            @logger.debug("activity check is delaying: #{@name}")
            sleep @start_delay
            @start_delay = nil
            @logger.debug("activity check is starting: #{@name}")
          end

          while @alive
            retval = nil

            begin
              retval = validate_activity
            rescue => e
              retval = false
              message = (["#{e.class}: #{e.message}"] + (e.backtrace || [])).join("\n\tfrom ")
              @logger.error("activity check failed: #{@name}: #{message}")
            end

            status = retval == true ? 'active' : retval == false ? 'inactive' : '-'
            @logger.debug("result of a activity check: #{@name}: #{status}")

            if retval == true
              mark_active
            elsif retval == false
              mark_inactive
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

    def validate_activity
      records = @cloud.db.execute(<<-EOS, @name, ACTIVE)
        SELECT ip_address, priority FROM records
        WHERE name = ? AND activity = ?
      EOS

      # マスタに自IPが含まれているならアクティブ
      masters = records.select {|i| i['priority'] == MASTER }
      if masters.any? {|i| i['ip_address'] == @address }
        return true
      end

      # マスタがなくてセカンダリに自IPが含まれているならアクティブ
      secondaries = records.select {|i| i['priority'] == SECONDARY }

      if masters.empty? and secondaries.any? {|i| i['ip_address'] == @address }
        return true
      end

      # マスタ・セカンダリがなくてバックアップに自IPが含まれているならアクティブ
      backups = records.select {|i| i['priority'] == BACKUP }

      if masters.empty? and secondaries.empty? and backups.any? {|i| i['ip_address'] == @address }
        return true
      end

      # 上記以外は非アクティブ
      return false
    end

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

  end # ActivityChecker

end # Murakumo
