module Murakumo

  class Util

    def self.self_ip_address
      `/sbin/ifconfig eth0 | awk -F'[: ]+' '/^eth0/,/^$/{if(/inet addr/) print $4}'`.strip
    end

  end # Util

end # Murakumo
