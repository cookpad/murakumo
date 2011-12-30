require 'net/http'
require 'rexml/document'

require 'util/murakumo_ec2_client'

module Murakumo

  class Util

    def self.ec2_tags(access_key, secret_key, endpoint = nil, instance_id = nil)
      unless instance_id
        instance_id = Net::HTTP.get('169.254.169.254', '/latest/meta-data/instance-id')
      end

      ec2cli = Murakumo::Util::EC2Client.new(access_key, secret_key, endpoint)
      source = ec2cli.query('DescribeTags', 'Filter.1.Name' => 'resource-id', 'Filter.1.Value' => instance_id)

      tags = {}

      REXML::Document.new(source).each_element('//tagSet/item') do |element|
        key = element.text('key')
        value = element.text('value')
        tags[key] = value
      end

      return tags
    end

  end # Util

end # Murakumo
