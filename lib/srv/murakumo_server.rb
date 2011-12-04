require 'drb/drb'
require 'fileutils'
require 'rexec'
require 'rexec/daemon'
require 'rubydns'
require 'socket'

require 'srv/murakumo_cloud'

BasicSocket.do_not_reverse_lookup = true

module Murakumo

  # RExecに依存しているのでこんな設計に…
  class Server < RExec::Daemon::Base

    # クラスメソッドを定義
    class << self

      def init(options)
        # クラスインスタンス変数を使わないこと
        @@options = options
        @@cloud = Cloud.new(options)
      end

      def pid_directory=(path)
        @@pid_directory = path
      end

      def run
        RubyDNS.run_server(:listen => [[:udp, @@options[:dns_address], @@options[:dns_port]]]) do
          # RubyDNS::Serverのコンテキスト
          @logger = @@options[:logger] if @@options[:logger]

          on(:start) do
            if @@options[:socket]
              # 既存のソケットファイルは削除
              FileUtils.rm_f(@@options[:socket])

              # ServerクラスをDRuby化
              DRb.start_service("drbunix:#{@@options[:socket]}", @@cloud)
              at_exit { FileUtils.rm_f(@@options[:socket]) }
            end

            # HUPでログをローテート
            if @@options[:logger]
              trap(:HUP) do
                if logger = @@options[:logger]
                  logdev = logger.instance_variable_get(:@logdev)

                  if (dev = logdev.dev).kind_of?(File)
                    path = dev.path
                    mutex = logdev.instance_variable_get(:@mutex)

                    mutex.synchronize do
                      dev.reopen(path, 'a')
                      dev.sync = true
                    end
                  end
                end
              end
            end

            # ゴシッププロトコルを開始
            @@cloud.start
          end

          # look up A record
          match(@@cloud.method(:address_exist?), :A) do |transaction|
            records = @@cloud.lookup_addresses(transaction.name)

            addrs = []
            min_ttl = nil # 最小のTTLをセット

            records.each do |r|
              address, ttl = r

              if min_ttl.nil? or ttl < min_ttl
                min_ttl = ttl
              end

              addrs << Resolv::DNS::Resource::IN::A.new(address)
            end

            # 直接引数に渡せないので…
            addrs << {:ttl => min_ttl}

            # スループットをあげるためrespond!は呼ばない
            transaction.append!(*addrs)
          end # match

          # look up PTR record
          match(@@cloud.method(:name_exist?), :PTR) do |transaction|
            name, ttl = @@cloud.lookup_name(transaction.name)
            name += ".#{@@options[:domain]}" if @@options[:domain]
            transaction.respond!(Resolv::DNS::Name.create("#{name}."), :ttl => ttl)
          end

          if @@options[:resolver]
            otherwise do |transaction|
              transaction.passthrough!(@@options[:resolver])
            end
          end
        end # RubyDNS.run_server
      end # run

      def shutdown
        @@cloud.stop
      end

    end # class << self

  end # Server

end # Murakumo
