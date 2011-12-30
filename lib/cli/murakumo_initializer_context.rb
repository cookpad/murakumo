require 'misc/murakumo_const'
require 'util/murakumo_self_ip_address'
require 'util/murakumo_ec2_tags'

module Murakumo

  # 設定初期化スクリプトのコンテキスト
  class InitializerContext

    def initialize(options)
      @options = options
    end

  end # InitializerContext

end # Murakumo
