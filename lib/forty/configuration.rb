require 'logger'
require 'mail'
require 'erb'

module Forty
  class Configuration
    attr_accessor :logger
    attr_accessor :master_username
    attr_accessor :schemas
    attr_accessor :acl_file
    attr_accessor :generate_passwords

    def initialize
      @logger = ::Logger.new(STDOUT)
      @logger.level = ::Logger::INFO
      @logger.formatter = proc do |severity, _, _, message|
        "[Forty] [#{severity}] #{message}\n"
      end
    end
  end

  class Database
    attr_accessor :name
    attr_accessor :host
    attr_accessor :port
    attr_accessor :user
    attr_accessor :password
    attr_accessor :database
  end

  class Mailer
    attr_accessor :smtp_address
    attr_accessor :smtp_host
    attr_accessor :smtp_port
    attr_accessor :smtp_username
    attr_accessor :smtp_password
    attr_accessor :smtp_authentication
    attr_accessor :smtp_encryption
    attr_accessor :enabled
    attr_accessor :templates

    def send_welcome(recipient, username, password)
      mail = ::Mail.new
      mail.delivery_method :smtp, {
        smtp_envelope_from: @smtp_address,
        address: @smtp_host,
        port: @smtp_port.to_i,
        user_name: @smtp_username,
        password: @smtp_password,
        authentication: @smtp_authentication,
        encryption: @smtp_encryption,
      }
      mail.from @smtp_address
      mail.to recipient
      mail.subject "#{Forty.database_configuration.name.to_s.length == 0 ? '' : Forty.database_configuration.name + ' '}DB Credentials (User: #{username})"

      parameters = binding
      parameters.local_variable_set(:database_name, Forty.database_configuration.name)
      parameters.local_variable_set(:username, username)
      parameters.local_variable_set(:password, password)
      parameters.local_variable_set(:host, Forty.database_configuration.host)
      parameters.local_variable_set(:port, Forty.database_configuration.port)
      parameters.local_variable_set(:database, Forty.database_configuration.database)

      if @enabled
        mail.body ERB.new(File.read(@templates[:user_created])).result(parameters)
        Forty.configuration.logger.info('Sending \'user_created\' email to ' + recipient)
        mail.deliver
        Forty.configuration.logger.info('Sent \'user_created\' email successfully')
      else
        Forty.configuration.logger.warn('Mail not enabled, skipped sending welcome email. You will need to regenerate a password for user ' + username + '.')
      end
    end
  end

  class << self
    attr_writer :configuration
    attr_writer :database_configuration
    attr_writer :mailer_configuration
  end

  def self.configuration
    @configuration ||= Forty::Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  def self.database_configuration
    @database ||= Forty::Database.new
  end

  def self.database
    yield(database_configuration)
  end

  def self.mailer_configuration
    @mailer ||= Forty::Mailer.new
  end

  def self.mailer
    yield(mailer_configuration)
  end
end
