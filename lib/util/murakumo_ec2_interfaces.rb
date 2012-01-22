require 'net/http'
require 'rexml/document'

require 'util/murakumo_ec2_client'

module Murakumo

  class Util

    def self.ec2_interfaces(access_key, secret_key, endpoint = nil, if_id = nil)
      dev_idx = 1 unless dev_idx
      params = {}

      if if_id
        params.update('Filter.1.Name' => 'network-interface-id', 'Filter.1.Value' => if_id)
      end

      ec2cli = Murakumo::Util::EC2Client.new(access_key, secret_key, endpoint)

      source = ec2cli.query('DescribeNetworkInterfaces', params)
      interfaces = []

      items = REXML::Document.new(source).get_elements('//networkInterfaceSet/item')
      walk_item_list(items, interfaces)

      return interfaces
    end

    def self.walk_item_list(list, ary)
      list.each do |item|
        hash = {}
        walk_item(item, hash)
        ary << hash
      end
    end 
    private_class_method :walk_item_list

    def self.walk_item(item, hash)
      return unless item.has_elements?

      item.elements.each do |child|
        if child.has_elements?
          if child.elements.all? {|i| i.name =~ /\Aitem\Z/i }
            hash[child.name] = nested = []
            walk_item_list(child.elements, nested)
          else
            hash[child.name] = nested = {}
            walk_item(child, nested)
          end
        else
          hash[child.name] = child.text
        end
      end
    end
    private_class_method :walk_item

  end # Util

end # Murakumo
