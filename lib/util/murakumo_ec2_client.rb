require 'cgi'
require 'base64'
require 'net/https'
require 'openssl'

Net::HTTP.version_1_2

module Murakumo

  class Util

    class EC2Client

      API_VERSION = '2011-12-15'
      SIGNATURE_VERSION = 2
      SIGNATURE_ALGORITHM = :SHA256

      def initialize(accessKeyId, secretAccessKey, endpoint = nil)
        unless endpoint
          local_hostname = Net::HTTP.get('169.254.169.254', '/latest/meta-data/local-hostname')

          if /\A[^.]+\.([^.]+)\.compute\.internal\Z/ =~ local_hostname
            endpoint = $1
          else
            endpoint = 'us-east-1'
          end
        end

        @accessKeyId = accessKeyId
        @secretAccessKey = secretAccessKey
        @endpoint = endpoint

        if /\A[^.]+\Z/ =~ @endpoint
          @endpoint = "ec2.#{@endpoint}.amazonaws.com"
        end
      end

      def query(action, params = {})
        params = {
          :Action           => action,
          :Version          => API_VERSION,
          :Timestamp        => Time.now.getutc.strftime('%Y-%m-%dT%H:%M:%SZ'),
          :SignatureVersion => SIGNATURE_VERSION,
          :SignatureMethod  => "Hmac#{SIGNATURE_ALGORITHM}",
          :AWSAccessKeyId   => @accessKeyId,
        }.merge(params)

        signature = aws_sign(params)
        params[:Signature] = signature

        https = Net::HTTP.new(@endpoint, 443)
        https.use_ssl = true
        https.verify_mode = OpenSSL::SSL::VERIFY_NONE

        https.start do |w|
          req = Net::HTTP::Post.new('/',
            'Host' => @endpoint,
            'Content-Type' => 'application/x-www-form-urlencoded'
          )

          req.set_form_data(params)
          res = w.request(req)

          res.body
        end
      end

      private
      def aws_sign(params)
        params = params.sort_by {|a, b| a.to_s }.map {|k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join('&')
        string_to_sign = "POST\n#{@endpoint}\n/\n#{params}"
        digest = OpenSSL::HMAC.digest(OpenSSL::Digest.const_get(SIGNATURE_ALGORITHM).new, @secretAccessKey, string_to_sign)
        Base64.encode64(digest).gsub("\n", '')
      end
    end

  end # Util

end # Murakumo
