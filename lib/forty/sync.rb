# require_relative 'configuration'

module Forty

  def self.sync
    Forty::Sync.new(
      Forty.configuration.logger,
      Forty.configuration.master_username,
      Forty.configuration.schemas,
      Forty::ACL.new(Forty.configuration.acl_file),
      Forty.instance_variable_get(:@database),
      false
    ).run
  end

  class Sync
    class Error < StandardError; end

    def initialize(logger, master_username, production_schemas, acl_config, executor, dry_run=true)
      @logger = logger or raise Error, 'No logger provided'
      @master_username = master_username or raise Error, 'No master username provided'
      @production_schemas = production_schemas or raise Error, 'No production schemas provided'
      @system_groups = ["pg_signal_backend"]
      @system_users = ["postgres"]
      @acl_config = acl_config or raise Error, 'No acl config provided'
      @acl_config['users'] ||= {}
      @acl_config['groups'] ||= {}

      @executor   = executor   or raise Error, 'No dwh executor provided'
      @dry_run = dry_run

      @logger.warn('Dry mode disabled, executing on production') unless @dry_run
    end

    def run
      banner()
      sync_users()
      sync_groups()
      sync_user_groups()
      sync_user_roles()
      sync_acl()
    end

    def banner
      @logger.info(<<-BANNER)
Starting sync...
    ____           __       
   / __/___  _____/ /___  __
  / /_/ __ \\/ ___/ __/ / / /
 / __/ /_/ / /  / /_/ /_/ /
/_/  \\____/_/   \\__/\\__, /  Database ACL Sync
                   /____/   v0.1.0

===============================================================================

Running in #{@dry_run ? 'DRY-MODE (not enforcing state)' : 'PRODUCTION-MODE (enforcing state)'}

Configuration:
    Master user:    #{@master_username}
    Synced schemas: #{@production_schemas.join(', ')}
    System users:   #{@system_users.join(', ')}
    System groups:  #{@system_groups.join(', ')}

===============================================================================
BANNER
    end

    def sync_users
      current_users = _get_current_dwh_users.keys
      defined_users = @acl_config['users'].keys

      undefined_users = (current_users - defined_users - @system_users).uniq.compact
      missing_users = (defined_users - current_users).uniq.compact

      @logger.debug("Undefined users: #{undefined_users}")
      @logger.debug("Missing users: #{missing_users}")
      undefined_users.each { |user| _delete_user(user) }

      missing_users.each do |user|
        roles = @acl_config['users'][user]['roles'] || []
        password = @acl_config['users'][user]['password']
        search_path = @production_schemas.join(',')

        _create_user(user, password, roles, search_path)
      end

      @logger.info('All users are in sync') if (undefined_users.count + missing_users.count) == 0
    end

    def sync_groups
      current_groups = _get_current_dwh_groups().keys
      defined_groups = @acl_config['groups'].keys

      undefined_groups = (current_groups - defined_groups - @system_groups).uniq.compact
      missing_groups = (defined_groups - current_groups).uniq.compact

      undefined_groups.each { |group| _delete_group(group) }
      missing_groups.each   { |group| _create_group(group) }

      @logger.info('All groups are in sync') if (undefined_groups.count + missing_groups.count) == 0
    end

    def sync_user_groups
      current_user_groups = _get_current_user_groups()
      defined_user_groups = _get_defined_user_groups()
      _check_group_unknown(current_user_groups.keys, defined_user_groups.keys)

      current_users = _get_current_dwh_users().keys
      defined_users = _get_defined_users()
      _check_user_unknown(current_users, defined_users)

      diverged = 0

      current_user_groups.each do |group, list|
        current_list = list
        defined_list = defined_user_groups[group] || []

        undefined_assignments = (current_list - defined_list).uniq.compact
        missing_assignments = (defined_list - current_list).uniq.compact

        undefined_assignments.each { |user| _remove_user_from_group(user, group) }
        missing_assignments.each   { |user| _add_user_to_group(user, group) }

        current_group_diverged = (undefined_assignments.count + missing_assignments.count)
        diverged += current_group_diverged

        @logger.debug("Users of group #{group} are in sync") if current_group_diverged == 0
      end

      @logger.info('All user groups are in sync') if diverged == 0
    end

    def sync_personal_schemas
      users = @acl_config['users'].keys
      users.each do |user|
        next if user.eql?(@master_username)
        schemas_owned_by_user = _get_currently_owned_schemas(user).uniq - @production_schemas
        unless schemas_owned_by_user.empty?
          tables_owned_by_user = _get_currently_owned_tables(user)
          schemas_owned_by_user.each do |schema|
            @executor.execute("set search_path=#{schema}")
            tables = @executor.execute("select tablename from pg_tables where schemaname='#{schema}'").map { |row| "#{schema}.#{row['tablename']}" }
            nonowned_tables_by_user = tables.uniq - tables_owned_by_user
            nonowned_tables_by_user.each { |table| _execute_statement("alter table #{table} owner to #{user};") }
          end
        end
      end
    end

    def sync_user_roles
      defined_user_roles = _get_defined_user_roles()
      current_user_roles = _get_current_user_roles()

      users = ((defined_user_roles.keys).concat(current_user_roles.keys)).uniq.compact

      diverged = 0

      users.each do |user|
        next if user.eql?(@master_username) or @system_users.include?(user)

        raise Error, "Users are not in sync #{user}" if current_user_roles[user].nil? or defined_user_roles[user].nil?

        undefined_roles = (current_user_roles[user] - defined_user_roles[user]).uniq.compact
        missing_roles   = (defined_user_roles[user] - current_user_roles[user]).uniq.compact

        current_roles_diverged = (undefined_roles.count + missing_roles.count)
        diverged += current_roles_diverged

        undefined_roles.each { |role| _execute_statement("alter user #{user} no#{role};") }
        missing_roles.each   { |role| _execute_statement("alter user #{user} #{role};") }

        @logger.debug("Roles of #{user} are in sync") if current_roles_diverged == 0
      end

      @logger.info('All user roles are in sync') if diverged == 0
    end

    def sync_acl
      sync_database_acl()
      sync_schema_acl()
      sync_table_acl()
    end

    def sync_database_acl
      current_database_acl = _get_current_database_acl()
      defined_database_acl = _get_defined_database_acl()

      diverged = _sync_typed_acl('database', current_database_acl, defined_database_acl)
      @logger.info('All database privileges are in sync') if diverged == 0
    end

    def sync_schema_acl
      current_schema_acl = _get_current_schema_acl()
      defined_schema_acl = _get_defined_schema_acl()

      diverged = _sync_typed_acl('schema', current_schema_acl, defined_schema_acl)
      @logger.info('All schema privileges are in sync') if diverged == 0
    end

    def sync_table_acl
      current_table_acl = _get_current_table_acl()
      defined_table_acl = _get_defined_table_acl()

      diverged = _sync_typed_acl('table', current_table_acl, defined_table_acl)
      @logger.info('All table privileges are in sync') if diverged == 0
    end

    private

    def _get_defined_user_groups
      Hash[@acl_config['groups'].map do |group, _|
        [group, @acl_config['users'].select do |_, data|
          groups = data['groups'] || []
          groups.include?(group)
        end.keys]
      end]
    end

    def _get_current_user_groups
      current_groups = _get_current_dwh_groups()
      current_users = _get_current_dwh_users().invert

      current_user_groups = Hash[current_groups.map { |group, list| [group, list.map { |id| current_users[id] }]}]
      current_user_groups
    end

    def _get_defined_user_roles
      Hash[@acl_config['users'].map do |user, config|
        user_groups = @acl_config['groups'].select { |group| (config['groups'] || []).include?(group) }
        user_roles = config['roles'] || []
        user_groups.each do |_, group_config|
          user_roles.concat(group_config['roles']) if group_config['roles'].is_a?(Array)
        end
        [user, user_roles.uniq]
      end]
    end

    def _get_current_user_roles
      Hash[@executor.execute(<<-SQL).map { |row| [row['usename'], row['user_roles'].split(',').select { |e| not e.empty? }.compact] }]
          select
              usename
            , case when usecreatedb is true then 'createdb' else '' end
              || ',' ||
              case when usesuper is true then 'createuser' else '' end
              as user_roles
          from pg_user
          where usename != 'rdsdb'
          order by usename
          ;
      SQL
    end

    def _check_group_unknown(current_groups, defined_groups)
      @logger.debug("Check whether groups are in sync. Current: #{current_groups}; Defined: #{defined_groups}; System: #{@system_groups}")
      raise Error, 'Groups are out of sync!' if _mismatch?(current_groups - @system_groups, defined_groups)
    end

    def _check_user_unknown(current_users, defined_users)
      @logger.debug("Check whether users are in sync. Current: #{current_users}; Defined: #{defined_users}; System: #{@system_users}")
      raise Error, 'Users are out of sync!' if _mismatch?(current_users - @system_users, defined_users)
    end

    def _mismatch?(current, defined)
      mismatch_count = 0
      mismatch_count += (current - defined).count
      mismatch_count += (defined - current).count
      mismatch_count > 0 ? true : false
    end

    def _execute_statement(statement)
      attempts = 0
      @logger.info(statement.sub(/(password\s+')(?:[^\s]+)(')/, '\1\2'))
      if @dry_run === false
        begin
          @logger.info("Retrying to execute statement in #{attempts*10} seconds...") if attempts > 0
          sleep (attempts*10)
          attempts += 1
          @executor.execute(statement)
        rescue PG::UndefinedTable => e
          @logger.error("#{e.class}: #{e.message}" )
          retry unless attempts > 3
          raise Error, 'Maximum number of attempts exceeded, giving up'
        end
      end
    end

    def _create_group(group)
      _execute_statement("create group #{group};")
    end

    def _delete_group(group)
      full_group_name = "group #{group}"

      acl = {
        'table' => _get_current_table_acl()[full_group_name],
        'schema' => _get_current_schema_acl()[full_group_name],
        'database' => _get_current_database_acl()[full_group_name]
      }

      acl.each do |type, acl|
        unless acl.nil? or acl.empty?
          acl.each do |identifier, permissions|
            _revoke_privileges(full_group_name, type, identifier, permissions)
          end
        end
      end

      _execute_statement("drop group #{group};")
    end

    def _create_user(user, password, roles=[], search_path=nil)
      _execute_statement("create user #{user} with password '#{password}' #{roles.join(' ')};")

      unless search_path.nil? or search_path.empty?
        _execute_statement("alter user #{user} set search_path to #{search_path};")
      end
    end

    def _generate_password
      begin
        password = SecureRandom.base64.gsub(/[^a-zA-Z0-9]/, '')
        raise 'Not valid' unless password.match(/[a-z]/) && password.match(/[A-Z]/) && password.match(/[0-9]/)
      rescue
        retry
      else
        password
      end
    end

    def _delete_user(user)
      raise Error, 'Please define the master user in the ACL file!' if user.eql?(@master_username)

      schemas_owned_by_user = _get_currently_owned_schemas(user)
      tables_owned_by_user = _get_currently_owned_tables(user)

      _resolve_object_ownership_upon_user_deletion(schemas_owned_by_user, tables_owned_by_user)
      _revoke_all_privileges(user)

      _execute_statement("drop user #{user};")
    end

    def _resolve_object_ownership_upon_user_deletion(schemas, tables)
      non_production_tables = tables.select { |table| !@production_schemas.include?(table.split('.')[0]) }
      production_tables = tables.select { |table| @production_schemas.include?(table.split('.')[0]) }

      non_production_tables.each { |table| _execute_statement("drop table #{table};") }
      production_tables.each { |table| _execute_statement("alter table #{table} owner to #{@master_username};") }

      non_production_schemas = (schemas - @production_schemas)
      production_schemas = schemas.select { |schema| @production_schemas.include?(schema) }

      non_production_schemas.each { |schema| _execute_statement("drop schema #{schema} cascade;") }
      production_schemas.each { |schema| _execute_statement("alter schema #{schema} owner to #{@master_username};") }
    end

    def _revoke_all_privileges(grantee)
      (_get_current_table_acl[grantee] || {}).each do |name, privileges|
       _revoke_privileges(grantee, 'table', name, privileges)
      end

      (_get_current_schema_acl[grantee] || {}).each do |name, privileges|
       _revoke_privileges(grantee, 'schema', name, privileges)
      end

      (_get_current_database_acl[grantee] || {}).each do |name, privileges|
       _revoke_privileges(grantee, 'database', name, privileges)
      end
    end

    def _add_user_to_group(user, group)
      _execute_statement("alter group #{group} add user #{user};")
    end

    def _remove_user_from_group(user, group)
      _execute_statement("alter group #{group} drop user #{user};")
    end

    def _get_current_dwh_users
      query = <<-SQL
        select distinct
            usename as name
          , usesysid as id
        from pg_user
        where usename != 'rdsdb'
        ;
      SQL

      raw_dwh_users = @executor.execute(query)

      Hash[raw_dwh_users.map do |row|
        name = row['name']
        id = row['id'].to_i

        [name, id]
      end]
    end

    def _get_defined_users
      @acl_config['users'].keys
    end

    def _get_current_dwh_groups
      query = <<-SQL
        select distinct
            groname as name
          , array_to_string(grolist, ',') as user_list
        from pg_group
        ;
      SQL
      raw_dwh_groups = @executor.execute(query)

      Hash[raw_dwh_groups.map do |row|
        name = row['name']
        user_ids = row['user_list'].to_s.split(',').map { |id| id.to_i }

        [name, user_ids]
      end]
    end

    def _get_current_schema_acl
      query = <<-SQL
        select
            nspname                      as name
          , array_to_string(nspacl, ',') as acls
        from
            pg_namespace
        where
            nspacl is not null
        and nspowner != 1
        ;
      SQL

      raw_schema_acl = @executor.execute(query)
      _parse_current_acl('schema', raw_schema_acl)
    end

    def _get_current_database_acl
      query = <<-SQL
        select
            datname as name
          , array_to_string(datacl, ',')  as acls
        from pg_database
        where
              datacl is not null
          and datdba != 1
        ;
      SQL

      raw_database_acl = @executor.execute(query)
      _parse_current_acl('database', raw_database_acl)
    end

    def _get_current_table_acl
      query = <<-SQL
        select
            pg_namespace.nspname || '.' || pg_class.relname as name
          , array_to_string(pg_class.relacl, ',') as acls
        from pg_class
        left join pg_namespace on pg_class.relnamespace = pg_namespace.oid
        where
            pg_class.relacl is not null
        and pg_namespace.nspname not in (
            'pg_catalog'
          , 'pg_toast'
          , 'information_schema'
        )
        order by
            pg_namespace.nspname || '.' || pg_class.relname
        ;
      SQL

      raw_table_acl = @executor.execute(query)
      _parse_current_acl('table', raw_table_acl)
    end

    def _sync_typed_acl(identifier_type, current_acl, defined_acl)
      diverged = 0
      current_acl ||= {}
      defined_acl ||= {}

      grantees = []
        .concat(current_acl.keys)
        .concat(defined_acl.keys)
        .uniq
        .compact

      known_grantees = []
        .concat(_get_current_dwh_users().keys)
        .concat(_get_current_dwh_groups().keys.map { |group| "group #{group}" })
        .uniq
        .compact

      if grantees.any? { |grantee| !known_grantees.include?(grantee) }
        raise Error, "Users or groups not in sync! Could not find #{grantees.select { |grantee| !known_grantees.include?(grantee) }.join(', ')}"
      end

      grantees.each do |grantee|
        current_grantee_acl = current_acl[grantee] || {}
        defined_grantee_acl = defined_acl[grantee] || {}

        unsynced_privileges_count = _sync_privileges(grantee, identifier_type, current_grantee_acl, defined_grantee_acl)
        diverged += unsynced_privileges_count
      end

      diverged
    end

    def _sync_privileges(grantee, identifier_type, current_acl, defined_acl)
      current_acl ||= {}
      defined_acl ||= {}

      identifiers = []
        .concat(current_acl.keys)
        .concat(defined_acl.keys)
        .uniq
        .compact

      unsynced_privileges = 0

      identifiers.each do |identifier_name|
        if _is_in_unmanaged_schema?(identifier_type, identifier_name)
          @logger.debug("SKIPPED #{identifier_type} '#{identifier_name}'. Cannot sync privileges for object outside production schemas!")
        else
          current_privileges = current_acl[identifier_name] || []
          defined_privileges = defined_acl[identifier_name] || []

          undefined_privileges = (current_privileges - defined_privileges).uniq.compact
          missing_privileges   = (defined_privileges - current_privileges).uniq.compact

          current_privileges_diverged = (undefined_privileges.count + missing_privileges.count)
          unsynced_privileges += current_privileges_diverged

          _revoke_privileges(grantee, identifier_type, identifier_name, undefined_privileges)
          _grant_privileges(grantee, identifier_type, identifier_name, missing_privileges)
        end
      end

      @logger.debug("#{identifier_type.capitalize} privileges for #{grantee} are in sync") if unsynced_privileges == 0

      unsynced_privileges
    end

    def _is_in_unmanaged_schema?(identifier_type, identifier_name)
      managed = true
      case identifier_type
        when 'schema'
          managed = @production_schemas.include?(identifier_name)
        when 'table'
          managed = @production_schemas.any? { |p| identifier_name.start_with?("#{p}.") }
      end
      !managed
    end

    def _grant_privileges(grantee, identifier_type, identifier_name, privileges)
      privileges ||= []
      unless privileges.empty?
        _execute_statement("grant #{privileges.join(',')} on #{identifier_type} #{identifier_name} to #{grantee};")
      end
    end

    def _revoke_privileges(grantee, identifier_type, identifier_name, privileges)
      privileges ||= []
      unless privileges.empty?
        _execute_statement("revoke #{privileges.join(',')} on #{identifier_type} #{identifier_name} from #{grantee};")
      end
    end

    def _get_defined_acl(identifier_type)
      defined_acl = {}

      groups = Hash[@acl_config['groups'].map { |name, config| ["group #{name}", config] }] || {}
      users = @acl_config['users'] || {}

      grantees = {}
        .merge(groups)
        .merge(users)

      grantees.each do |grantee, config|
        permissions = config['permissions'] || []
        parsed_permissions = _parse_defined_permissions(identifier_type, permissions)
        defined_acl[grantee] = parsed_permissions unless parsed_permissions.empty?
      end

      defined_acl #.select { |_, permissions| !permissions.empty? }
    end

    def _get_defined_database_acl
      _get_defined_acl('database')
    end

    def _get_defined_schema_acl
      _get_defined_acl('schema')
    end

    def _get_defined_table_acl
      _get_defined_acl('table')
    end

    def _parse_defined_permissions(identifier_type, raw_permissions)
      defined_acl = {}

      # Implicitly grant usage on schemas for which we grant table privileges
      if identifier_type.eql?('schema')
        table_permissions = raw_permissions.select { |permission| permission['type'].eql?('table') } || []
        table_permissions.each do |table_permission|
          table_permission['identifiers'].each do |schema_and_table|
            schema, _ = schema_and_table.split('.')
            schemas_to_grant_usage_on = []

            if schema.eql?('*')
              schemas_to_grant_usage_on = @production_schemas
            else
              schemas_to_grant_usage_on << schema
            end

            schemas_to_grant_usage_on.each do |schema_name|
              defined_acl[schema_name] ||= []
              defined_acl[schema_name].concat(['usage'])
            end
          end
        end
      end

      permissions = raw_permissions.select { |permission| permission['type'].eql?(identifier_type) } || []

      permissions.each do |permission|
        permission['identifiers'].each do |identifier|
          privileges = permission['privileges']

          if identifier.match /\*/
            case identifier_type
              when 'database'
                raise Error, 'Don\'t know how to resolve database identifiers with wildcard'
              when 'schema'
                @production_schemas.each do |schema|
                  defined_acl[schema] ||= []
                  defined_acl[schema].concat(privileges)
                end
              when 'table'
                schema, table = identifier.split('.')

                raise Error, 'Cannot resolve wildcard schema for specific table names' if schema.eql?('*') and !table.eql?('*')

                tables_to_grant_privileges_on = []

                if schema.eql?('*')
                  @production_schemas.each do |prod_schema|
                    tables = @executor.execute(<<-SQL).map { |row| "#{prod_schema}.#{row['tablename']}" }
                      select tablename from pg_tables where schemaname='#{prod_schema}'
                    SQL

                    tables_to_grant_privileges_on.concat(tables)
                  end
                else
                  tables_to_grant_privileges_on = @executor.execute(<<-SQL).map { |row| "#{schema}.#{row['tablename']}" }
                    select tablename from pg_tables where schemaname='#{schema}'
                  SQL
                end

                tables_to_grant_privileges_on = tables_to_grant_privileges_on.uniq.compact

                tables_to_grant_privileges_on.each do |table|
                  defined_acl[table] ||= []
                  defined_acl[table].concat(privileges)
                end
            end
          else
            defined_acl[identifier] ||= []
            defined_acl[identifier].concat(privileges)
          end
        end
      end

      uniquely_defined_acl = Hash[defined_acl.map do |identifier, privileges|
        unique_privileges = privileges.include?('all') ? ['all'] : privileges.uniq.compact
        [identifier, unique_privileges]
      end]

      uniquely_defined_acl
    end

    def _parse_current_acl(identifier_type, raw_acl)
      parsed_acls = {}
      raw_acl.each do |row|
        name = row['name']
        @logger.debug("Current ACL: [#{identifier_type}] '#{name}': #{row['acls']}")
        parsed_acl = _parse_current_permissions(identifier_type, row['acls'])
        parsed_acl.each do |grantee, privileges|
          unless grantee.empty?
            if _get_current_dwh_groups().keys.include?(grantee)
              @logger.debug("Grantee '#{grantee}' has been identified as a group")
              grantee = "group #{grantee}"
            end
            parsed_acls[grantee] ||= {}
            parsed_acls[grantee][name] ||= []
            parsed_acls[grantee][name].concat(privileges)
          end
        end
      end
      parsed_acls
    end

    def _parse_current_permissions(identifier_type, raw_permissions)
      # http://www.postgresql.org/docs/8.1/static/sql-grant.html
      # Typical ACL string:
      #
      #     admin=arwdRxt/admin,someone=r/admin,"group selfservice=r/admin"
      #
      #                =xxxx -- privileges granted to PUBLIC
      #           uname=xxxx -- privileges granted to a user
      #     group gname=xxxx -- privileges granted to a group
      #                /yyyy -- user who granted this privilege

      privilege_type = case identifier_type
        when 'database'
          Privilege::Database
        when 'schema'
          Privilege::Schema
        when 'table'
          Privilege::Table
        else
          raise Error, 'wtf'
      end

      parsed_permissions = {}
      permissions = raw_permissions.split(',')
      permissions.map! { |entry| entry.delete('"') }
      permissions.each do |permission|
        grantee, permission_string = permission.split('=')
        privileges_string = permission_string.split('/')[0]

        next if grantee.eql?(@master_username) # superuser has access to everything anyway

        parsed_permissions[grantee] ||= privilege_type.parse_privileges_from_string(privileges_string)
      end

      parsed_permissions
    end

    def _get_currently_owned_schemas(user)
      query = <<-SQL
        select pg_namespace.nspname as schemaname
        from pg_namespace
        left join pg_user on pg_namespace.nspowner = pg_user.usesysid
        where pg_user.usename = '#{user}'
        ;
      SQL
      @executor.execute(query).map { |row| row['schemaname'] }
    end

    def _get_currently_owned_tables(user)
      query = <<-SQL
        select (schemaname || '.' || tablename) as tablename
        from pg_tables
        where tableowner = '#{user}'
        ;
      SQL
      @executor.execute(query).map { |row| row['tablename'] }
    end
  end
end
