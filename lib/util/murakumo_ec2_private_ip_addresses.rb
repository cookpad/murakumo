require 'net/http'
require 'rexml/parsers/pullparser'

require 'util/murakumo_ec2_client'

module Murakumo

  class Util

    def self.ec2_private_ip_addresses(access_key, secret_key, endpoint = nil)
      ec2cli = Murakumo::Util::EC2Client.new(access_key, secret_key, endpoint)
      source = ec2cli.query('DescribeInstances')

      parser = REXML::Parsers::PullParser.new(source)
      ip_addrs = []
      instance_id = nil
      status = nil

      while parser.has_next?
        event = parser.pull
        next if event.event_type != :start_element

        case event[0]
        when 'instanceId'
          instance_id = parser.pull[0]
        when 'instanceState'
          until event.event_type == :start_element and event[0] == 'name'
            event = parser.pull
          end

          status = parser.pull[0]
        when 'privateIpAddress'
          ip_addrs << [instance_id, parser.pull[0], status]
        end
      end

      return ip_addrs
    end

  end # Util

end # Murakumo
