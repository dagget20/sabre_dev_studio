require 'httparty'
require 'base64'

module SabreDevStudio
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  class Configuration
    attr_accessor :user, :group, :domain, :password, :uri

    def initialize
    end
  end

  class Base
    include HTTParty

    @@token = nil

    def self.access_token
      @@token
    end

    def self.get_access_token
      user          = SabreDevStudio.configuration.user
      group         = SabreDevStudio.configuration.group
      domain        = SabreDevStudio.configuration.domain
      client_id     = Base64.strict_encode64("V1:#{user}:#{group}:#{domain}")
      client_secret = Base64.strict_encode64(SabreDevStudio.configuration.password)
      credentials   = Base64.strict_encode64("#{client_id}:#{client_secret}")
      headers       = { 'Authorization' => "Basic #{credentials}" }
      req           = post("#{SabreDevStudio.configuration.uri}/v1/auth/token",
                            :body        => { :grant_type => 'client_credentials' },
                            :ssl_version => :TLSv1,
                            :verbose     => true,
                            :headers     => headers)
      @@token       = req['access_token']
    end

    def self.get(path, options = {})
      attempt = 0
      begin
        attempt += 1
        get_access_token if @@token.nil?
        headers = {
          'Authorization'   => "Bearer #{@@token}",
          'Accept-Encoding' => 'gzip'
        }
        data = super(
          SabreDevStudio.configuration.uri + path,
          :query       => options[:query],
          :ssl_version => :TLSv1,
          :headers     => headers
        )
        verify_response(data)
        return data
      rescue SabreDevStudio::Unauthorized
        if attempt == 1
          get_access_token
          retry
        end
      end
    end

    private

    def self.verify_response(data)
      # NOTE: should all of these raise or should some reissue the request?
      case data.response.code.to_i
      when 200
        # nothing to see here, please move on
        return
      when 400
        raise SabreDevStudio::BadRequest.new(data)
      when 401
        raise SabreDevStudio::Unauthorized.new(data)
      when 403
        raise SabreDevStudio::Forbidden.new(data)
      when 404
        raise SabreDevStudio::NotFound.new(data)
      when 406
        raise SabreDevStudio::NotAcceptable.new(data)
      when 429
        raise SabreDevStudio::RateLimited.new(data)
      when 500
        raise SabreDevStudio::InternalServerError.new(data)
      when 503
        raise SabreDevStudio::ServiceUnavailable.new(data)
      when 504
        raise SabreDevStudio::GatewayTimeout.new(data)
      else
        raise SabreDevStudio::Error.new(data)
      end
    end
  end
end
