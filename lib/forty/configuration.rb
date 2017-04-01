require 'logger'

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
    attr_accessor :host
    attr_accessor :port
    attr_accessor :user
    attr_accessor :password
    attr_accessor :database
  end

  class << self
    attr_writer :configuration
    attr_writer :database_configuration
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
end
