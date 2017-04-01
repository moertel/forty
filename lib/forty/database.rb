require 'pg'

module Forty
  class Database
    attr_accessor :host
    attr_accessor :port
    attr_accessor :user
    attr_accessor :password
    attr_accessor :database

    def execute(statement)
      @db ||= PG.connect(
        host: self.host,
        port: self.port,
        user: self.user,
        password: self.password,
        dbname: self.database
      )

      @db.exec(statement)
    end
  end
end
