module Forty
  module Privilege
    class Base
      PRIVILEGES = self.constants.map { |const| self.const_get(const) }

      def self.get_privilege_name_by_acronym(acronym)
        privilege = self.constants.select do |constant|
          self.const_get(constant).eql?(acronym)
        end[0]
        privilege.nil? ? nil : privilege.to_s.downcase
      end

      def self.parse_privileges_from_string(privileges_string)
        privileges = []
        self.constants.each do |constant|
          acronym = self.const_get(constant)
          unless privileges_string.slice!(acronym).nil?
            privileges << self.get_privilege_name_by_acronym(acronym)
          end
          break if privileges_string.empty?
        end
        privileges
      end
    end

    # https://www.postgresql.org/docs/9.6/static/sql-grant.html
    #        r -- SELECT ("read")
    #        w -- UPDATE ("write")
    #        a -- INSERT ("append")
    #        d -- DELETE
    #        D -- TRUNCATE
    #        x -- REFERENCES
    #        t -- TRIGGER
    #        X -- EXECUTE
    #        U -- USAGE
    #        C -- CREATE
    #        c -- CONNECT
    #        T -- TEMPORARY
    #  arwdDxt -- ALL PRIVILEGES (for tables, varies for other objects)
    #        * -- grant option for preceding privilege
    #
    #    /yyyy -- role that granted this privilege

    class Table < Base
      ALL = 'arwdDxt'
      SELECT = 'r'
      UPDATE = 'w'
      INSERT = 'a'
      DELETE = 'd'
      TRUNCATE = 'D'
      REFERENCES = 'x'
      TRIGGER = 't'
      EXECUTE = 'X'
    end

    class Schema < Base
      ALL = 'UC'
      USAGE = 'U'
      CREATE = 'C'
    end

    class Database < Base
      ALL = 'CTc'
      CREATE = 'C'
      CONNECT = 'c'
      TEMPORARY = 'T'
    end
  end
end
