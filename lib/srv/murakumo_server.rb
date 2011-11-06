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

      def cloud
        @@cloud
      end

      def database
        @@db
      end

      def run
        RubyDNS.run_server(:listen => [[:udp, @@options[:dns_address], @@options[:dns_port]]]) do
          # RubyDNS::Serverのコンテキスト
          @logger = @@options[:logger]

          on(:start) do
            if @@options[:daemon] and @@options[:sock]
              # ServerクラスをDRuby化
              DRb.start_service("drbunix:#{@@options[:sock]}", self)
            end

            # ゴシッププロトコルを開始
            @@cloud.start
          end

          # look up A record
          match(@@cloud.method(:address_exist?), :A) do |transaction|
            records = @@cloud.lookup_addresses(transaction.name)

            if records.length == 1
              # レコードが一件ならそれを返す
              address, ttl, weight = records.first
              transaction.respond!(address, :ttl => ttl)
            else
              # 重み付けに応じてアドレスを返す
              total_weight = records.inject(0) {|r, i| r + i[2] }
              rand_num = rand(total_weight)

              records.each do |address, ttl, weight|
                rand_num -= weight

                # いずれかの時点で必ず0以下になる
                if rand_num < 0
                  transaction.respond!(address, :ttl => ttl)
                  break
                end
              end
            end
          end # match

          # look up PTR record
          match(@@cloud.method(:name_exist?), :PTR) do |transaction|
            name, ttl = @@cloud.lookup_name(transaction.name)
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
        FileUtils.rm_f(@@options[:sock]) if @@options[:sock]
      end

    end # class << self

  end # Server

end # Murakumo
