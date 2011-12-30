module Murakumo

  module Util

    def self_ip_address
      `/sbin/ifconfig eth0 | awk -F'[: ]+' '/^eth0/,/^$/{if(/inet addr/) print $4}'`.strip
    end

    module_function :self_ip_address

  end # Util

end # Murakumo
