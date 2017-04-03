# Forty

Define Postgres users, groups and their permissions in a JSON file and let Forty enforce this state in your Postgres database. Forty will create users/groups which are present in the JSON file but missing from the database, and will delete users/groups which are present in the database but missing from the JSON file.

## Example

If you have Docker installed, you can run `docker-compose -f docker-compose_demo.yml up` on your machine to see an example in action. This will spin up a Postgres instance with the system user `postgres` and another admin user `demo_admin_user`. The file [`acl.json`](example/acl.json) further specifies a user `example_user` who is not yet present in the database. When calling Forty's `sync` method, this user will be added to the database.

## Usage

To configure Forty, simply require it in your script and configure the library as well as a Postgres database. You will need to specify a user for the Postgres database which has access to all realms that you want to manage. In case you want to allow it to delete users, Forty will reassign objects that are defined in `Forty.configuration.schemas` to the user defined as `Forty.configuration.master_username` and delete all other objects.

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

Forty.sync  # this starts the sync immediately
```

```json
{
    "users": {
        "some_readonly_user": {
            "groups": [
                "all_tables_readonly"
            ]
        },
        "some_readonly_user_with_special_permissions": {
            "groups": [
                "all_tables_readonly"
            ],
            "permissions": [
                {
                    "type": "table",
                    "identifiers": [
                        "some_schema.some_table",
                        "another_schema.another_table"
                    ],
                    "privileges": [
                        "select",
                        "insert"
                    ]
                }
            ]
        },
        "some_admin_user": {
            "groups": [
                "readwrite_everything"
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
        },
        "readwrite_everything": {
            "roles": [
                "createuser",
                "createdb"
            ],
            "permissions": [
                {
                    "type": "schema",
                    "identifiers": [
                        "*"
                    ],
                    "privileges": [
                        "all"
                    ]
                },
                {
                    "type": "table",
                    "identifiers": [
                        "*.*"
                    ],
                    "privileges": [
                        "all"
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

## Usage

Either call `Forty.sync` directly or call the Rake task `rake acl:sync:all`. An example can be found in [`example/`](example).

## Contributing

1. Fork it ( https://github.com/moertel/forty/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
