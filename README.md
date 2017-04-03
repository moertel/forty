# Forty

[![Build Status](https://travis-ci.org/moertel/forty.svg?branch=master)](https://travis-ci.org/moertel/forty) [![Gem Version](https://badge.fury.io/rb/forty.svg)](https://badge.fury.io/rb/forty)

Define Postgres users, groups and their permissions as code and let Forty enforce this state in your Postgres database. Forty will create users/groups which are present in the configuration file but missing from the database, and will delete users/groups which are present in the database but missing from the configuration file. An extensive example can be found [here](example/acl.json).

## Example

If you have Docker installed, you can run `docker-compose -f docker-compose_demo.yml up` on your machine to see an example in action. This will spin up a Postgres instance with the system user `postgres` and another admin user `demo_admin_user`. The file [`acl.json`](example/acl.json) specifies a few more users and groups (and their permissions) who are not yet present in the database. When calling Forty's `sync` method, the configuration will be synced to the database.

## Usage

To configure Forty, simply require it in your script and configure the library as well as a Postgres database. You will need to specify a user for the Postgres database which has access to all realms that you want to manage. In case you want to allow it to delete users, Forty will reassign objects that are defined in `Forty.configuration.schemas` to the user defined as `Forty.configuration.master_username` and delete all other objects in "unmanaged" schemas.

### Configuration

```ruby
require 'forty'

Forty.configure do |config|
    config.master_username = 'postgres' # the root user; no permissions will be synced for this user
    config.acl_file = 'acl.json'        # the file with users, groups and permissions
    config.schemas = ['postgres']       # a list of schemas to be caught by wildcard identifiers in `acl.json`
end

Forty.database do |db|
    db.host = '127.0.0.1'
    db.port = 5432
    db.user = 'postgres'    # the user to be used to sync permissions. must have full access to everything!
    db.password = 'secret'
    db.database = 'postgres'
end
```

### Execution

You can either sync immediately by calling the command somewhere in your Ruby code:
```ruby
# ./some_ruby_script.rb

require 'forty'

Forty.sync  # this starts the sync immediately
```

Or import Forty's Rake tasks and call it from elsewhere; especially useful if you want to run this in Docker:
```ruby
# Rakefile

require 'forty/rake/task'
```
Which will give you the following command:
```
$ rake acl:sync:all
```

### ACL File

Define users, groups and permissions in a JSON formatted file. (A more sophisticated example can be found [here](example/acl.json).)
```json
{
    "users": {
        "some_readonly_user": {
            "groups": [
                "all_tables_readonly"
            ]
        }
    },
    "groups": {
        "all_tables_readonly": {
            "permissions": [
                {
                    "type": "table",
                    "identifiers": [
                        "*.*"
                    ],
                    "privileges": [
                        "select"
                    ]
                }
            ]
        }
    }
}
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'forty'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install forty


## Contributing

1. Fork it ( https://github.com/moertel/forty/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
