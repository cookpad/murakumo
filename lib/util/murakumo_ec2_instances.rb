require 'net/http'
require 'rexml/document'

require 'util/murakumo_ec2_client'

module Murakumo

  class Util

    def self.ec2_instances(access_key, secret_key, endpoint = nil)
      ec2cli = Murakumo::Util::EC2Client.new(access_key, secret_key, endpoint)
      source = ec2cli.query('DescribeInstances')
      instances = []

      items = REXML::Document.new(source).get_elements('//instancesSet/item')
      walk_item_list(items, instances)

      return instances
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
