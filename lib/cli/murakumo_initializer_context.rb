require 'misc/murakumo_const'
require 'util/murakumo_self_ip_address'
require 'util/murakumo_ec2_tags'
require 'util/murakumo_ec2_instances'
require 'util/murakumo_ec2_private_ip_addresses'
require 'util/murakumo_ec2_attach_interface'
require 'util/murakumo_ec2_interfaces'

module Murakumo

  # 設定初期化スクリプトのコンテキスト
  class InitializerContext

    def initialize(options)
      @options = options
    end

  end # InitializerContext

end # Murakumo
