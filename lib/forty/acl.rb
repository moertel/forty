require 'json'

module Forty
  class ACL
    def initialize(path_to_acl_file)
      raise('no path to ACL file provided') if path_to_acl_file.nil? or path_to_acl_file.empty?

      if File.exist?(path_to_acl_file)
        begin
          @acl = JSON.parse(File.read(path_to_acl_file))
        rescue StandardError
          raise "ACL file #{path_to_acl_file} could not be parsed"
        end
      else
        raise("ACL file not found at: #{path_to_acl_file}")
      end
    end

    def [](key)
      @acl[key]
    end

    def []=(key, value)
      @acl[key] = value
    end
  end
end
