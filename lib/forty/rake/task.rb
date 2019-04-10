require 'rake'
require_relative '../../forty'

module Forty
  module Rake
    class Task
      include ::Rake::DSL if defined? ::Rake::DSL

      def install_tasks
        namespace :acl do
          namespace :sync do
            desc 'syncs entire acl config with database'
            task :all, [:disable_dry_run, :strict] do |t, args|
              dry_run = args[:disable_dry_run].eql?('true') ? false : true
              strict = args[:strict].eql?('true') ? true : false
              Forty.sync(dry_run, strict)
            end
          end
        end
      end
    end
  end
end

Forty::Rake::Task.new.install_tasks
