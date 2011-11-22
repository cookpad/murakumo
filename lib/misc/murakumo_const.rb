module Murakumo
  VERSION = '0.2.6'

  # Priority
  MASTER = 1
  SECONDARY = 0
  BACKUP = -1
  ORIGIN = -65536

  # Activity
  ACTIVE = 1
  INACTIVE = 0

  ATTRIBUTES = {
    :node_lifetime   => [:node_lifetime, :to_f],
    :send_interval   => [:gossip_interval, :to_f],
    :receive_timeout => [:receive_timeout, :to_f],
    :log_level       => nil,
  }
end
