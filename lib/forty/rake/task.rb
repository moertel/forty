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
            task :all, [:disable_dry_run] do
              Forty.sync
            end
          end
        end
      end
    end
  end
end

Forty::Rake::Task.new.install_tasks
