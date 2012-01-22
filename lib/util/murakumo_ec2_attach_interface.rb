require 'net/http'
require 'rexml/document'

require 'util/murakumo_ec2_client'
require 'util/murakumo_ec2_interfaces'

module Murakumo

  class Util
    WAIT_LIMIT = 99
    WAIT_INTERVAL = 0.3

    def self.ec2_attach_interface(access_key, secret_key, if_id, dev_idx = 1, endpoint = nil, instance_id = nil)
      dev_idx = 1 unless dev_idx

      unless instance_id
        instance_id = Net::HTTP.get('169.254.169.254', '/latest/meta-data/instance-id')
      end

      check_own_attached(access_key, secret_key, endpoint, if_id, instance_id)

      ec2_detach_interface(access_key, secret_key, if_id, endpoint, :force) rescue nil

      wait_detach(access_key, secret_key, endpoint, if_id)

      ec2cli = Murakumo::Util::EC2Client.new(access_key, secret_key, endpoint)
      source = ec2cli.query('AttachNetworkInterface',
        'NetworkInterfaceId' => if_id, 'InstanceId' => instance_id, 'DeviceIndex' => dev_idx)

      errors = []

      REXML::Document.new(source).each_element('//Errors/Error') do |element|
        code = element.text('Code')
        message = element.text('Message')
        errors << "#{code}:#{message}"
      end

      raise errors.join(', ') unless errors.empty?
    end

    def self.ec2_detach_interface(access_key, secret_key, if_id, endpoint = nil, force = false)
      interfaces = ec2_interfaces(access_key, secret_key, endpoint, if_id)

      if not interfaces or interfaces.empty?
        raise 'interface was not found'
      end

      interface = interfaces.first
      attachment_id = (interface['attachment'] || {})['attachmentId'] || ''

      if attachment_id.empty?
        raise 'attachmentId was not found'
      end

      ec2cli = Murakumo::Util::EC2Client.new(access_key, secret_key, endpoint)

      params = {'AttachmentId' => attachment_id}
      params['Force'] = true if force
      source = ec2cli.query('DetachNetworkInterface', params)

      errors = []

      REXML::Document.new(source).each_element('//Errors/Error') do |element|
        code = element.text('Code')
        message = element.text('Message')
        errors << "#{code}:#{message}"
      end

      raise errors.join(', ') unless errors.empty?
    end

    def self.check_own_attached(access_key, secret_key, endpoint, if_id, instance_id)
      interfaces = ec2_interfaces(access_key, secret_key, endpoint, if_id)

      if not interfaces or interfaces.empty?
        raise 'interface was not found'
      end

      interface = interfaces.first

      if (interface['attachment'] || {})['instanceId'] == instance_id
        raise 'interface is already attached'
      end
    end
    private_class_method :check_own_attached

    def self.wait_detach(access_key, secret_key, endpoint, if_id)
      WAIT_LIMIT.times do
        interfaces = ec2_interfaces(access_key, secret_key, endpoint, if_id)

        if not interfaces or interfaces.empty?
          raise 'interface was not found'
        end

        interface = interfaces.first

        return if interface['status'] == 'available'

        sleep WAIT_INTERVAL
      end

      raise 'cannot detach interface'
    end
    private_class_method :wait_detach

  end # Util

end # Murakumo
