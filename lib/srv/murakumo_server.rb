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

      def run
        RubyDNS.run_server(:listen => [[:udp, @@options[:dns_address], @@options[:dns_port]]]) do
          # RubyDNS::Serverのコンテキスト
          @logger = @@options[:logger]

          on(:start) do
            if @@options[:socket]
              # ServerクラスをDRuby化
              DRb.start_service("drbunix:#{@@options[:socket]}", @@cloud)
              at_exit { FileUtils.rm_f(@@options[:socket]) }
            end

            # ゴシッププロトコルを開始
            @@cloud.start
          end

          # look up A record
          match(@@cloud.method(:address_exist?), :A) do |transaction|
            records = @@cloud.lookup_addresses(transaction.name)

            # 先頭のAレコードを決定
            max_ip_num = [records.length, @@options[:max_ip_num]].min
            first_index = rand(max_ip_num);

            # Aレコードを返す
            (records + records).slice(first_index, max_ip_num).each do |r|
              address, ttl = r
              transaction.respond!(address, :ttl => ttl)
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
      end

    end # class << self

  end # Server

end # Murakumo
