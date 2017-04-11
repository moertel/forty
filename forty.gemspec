Gem::Specification.new do |s|
  s.name               = 'forty'
  s.version            = '0.3.0'
  s.default_executable = 'forty'

  s.licenses = ['MIT']
  s.required_ruby_version = '>= 2.0'
  s.required_rubygems_version = Gem::Requirement.new('>= 0') if s.respond_to? :required_rubygems_version=
  s.authors = ['Stefanie Grunwald']
  s.date = %q{2017-04-03}
  s.email = %q{steffi@physics.org}
  s.files = [
    'lib/forty.rb',
    'lib/forty/privilege.rb',
    'lib/forty/acl.rb',
    'lib/forty/configuration.rb',
    'lib/forty/database.rb',
    'lib/forty/sync.rb',
    'lib/forty/rake/task.rb',
  ]
  s.homepage = %q{https://github.com/moertel/forty}
  s.require_paths = ['lib']
  s.rubygems_version = %q{1.6.2}
  s.summary = %q{Manage users, groups and ACL (access control lists) for Postgres databases}

  s.add_runtime_dependency 'pg', ['>= 0.16', '< 1.0']
  s.add_runtime_dependency 'cucumber', ['>= 2.0', '< 3.0']
  s.add_runtime_dependency 'rake', ['>= 10.1', '< 12.0']
  s.add_runtime_dependency 'mail', ['>= 2.6.0', '< 3.0']

  s.add_development_dependency 'rspec', ['>= 3.1', '< 4.0']
  s.add_development_dependency 'rspec-collection_matchers', ['>= 1.1.2', '< 2.0']

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.0.0') then
    else
    end
  else
  end
end

