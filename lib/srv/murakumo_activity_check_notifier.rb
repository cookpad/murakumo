require 'net/smtp'
require 'time'

module Murakumo

  class ActivityCheckNotifier

    def initialize(address, name, logger, options)
      @address = address
      @name = name
      @logger = logger
      @args = options[:args]
      @sender = options[:sender]
      @recipients = options[:recipients]
      @open_timeout = options[:open_timeout]
      @read_timeout = options[:read_timeout]
    end

    def notify_active
      notify('active', "#{@name} became active.")
    end

    def notify_inactive
      notify('inactive', "#{@name} became inactive. Zzz...")
    end

    private
    def notify(status, body)
      Net::SMTP.start(*@args) do |smtp|
        smtp.open_timeout = @open_timeout if @open_timeout
        smtp.read_timeout = @read_timeout if @read_timeout

        smtp.send_mail(<<-EOS, @sender, *@recipients)
From: Murakumo Activity Check Notifier <#{@sender}>
To: #{@recipients.join(', ')}
Subject: [Activity] #{@name}/#{@address} => #{status}
Date: #{Time.now.rfc2822}

Address: #{@address}
Name: #{@name}
Status: #{status}

#{body.strip}
        EOS
      end

      @logger.info("sent notice: #{status}")
    rescue Exception => e
      message = (["#{e.class}: #{e.message}"] + (e.backtrace || [])).join("\n\tfrom ")
      @logger.error("activity check failed: #{@name}: #{message}")
    end

  end # ActivityCheckNotifier

end # Murakumo
