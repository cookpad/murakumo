module Murakumo
  # Priority
  MASTER = 1
  BACKUP = 0
  ORIGIN = -1

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
