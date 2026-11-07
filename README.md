# ActiveRecordPrettyKey

A Ruby gem for generating and managing pretty, human-readable keys in ActiveRecord models. 

The gem automatically generates pretty keys by creating unique integer "tickets" and encoding them with the [Sqids](https://github.com/sqids/sqids-ruby) library to produce short, URL-safe string identifiers. Keys are generated before saving records, ensuring both uniqueness and consistency.

**Examples:** `BnJe`, `xK4m`, `Qp7R`, `vN2f8` — short, memorable IDs perfect for URLs like `/posts/xK4m`

Inspired by:
- [Flickr Ticket Servers: Distributed Unique Primary Keys on the Cheap](https://code.flickr.net/2010/02/08/ticket-servers-distributed-unique-primary-keys-on-the-cheap/)
- [Hashids](https://github.com/peterhellberg/hashids.rb)

## Why Pretty Keys?

| Feature | Regular Primary Keys | UUID7 | Pretty Keys |
|---------|---------------------|-------|-------------|
| **Human Readable** | ✅ Sequential numbers (1, 2, 3...) | ❌ Long, random strings | ✅ Short, memorable strings |
| **In Order** | ✅ Yes |  ✅ Yes |  ❌ No |
| **URL Friendly** | ✅ Simple and clean | ❌ Long and unwieldy | ✅ Short and clean |
| **Guessability** | ❌ Sequential, easily enumerated | ✅ Hard to guess | ⚠️ Obfuscated, not secret (see [Security](#security)) |
| **Length** | ✅ Very short | ❌ Very long (36 chars) | ✅ Short (4+ chars, grows slowly) |
| **Collision Risk** | ✅ None (auto-increment) | ✅ Extremely low | ✅ None (ticket database table) |

Pretty keys offer a middle ground between auto-incrementing integers and UUIDs — short, human-readable identifiers that don't expose your raw row IDs.

## Requirements

- Ruby 3.0+
- Rails / ActiveRecord 6.1 – 8.x
- PostgreSQL (incl. PostGIS), MySQL 8.0+ (`mysql2` or `trilogy` adapter) or SQLite. Other databases raise `ActiveRecordPrettyKey::Error`.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'active_record_pretty_key'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install active_record_pretty_key
```

## Usage

### Setup

First, run the generator to create the required tickets table:

```bash
rails generate active_record_pretty_key:install
```

This creates a `create_pretty_key_tickets` migration for the single-row `pretty_key_tickets` table that hands out unique ticket numbers. Run it with `rails db:migrate`.

### Customizing or Randomizing the Sqids Alphabet

A custom Sqids alphabet can be configured in Rails credentials:

```yaml
sqids:
  alphabet: "ENwUpVBslGq25afc6i0hyD4tnjxRY31Wouz7HFTeMKgSbmPZvJ9ALXCQdrkI8O"
```

This can be used to configure a randomized alphabet to obfuscate object IDs. The alphabet is read from credentials the first time a key is generated.

> **Warning:** Choose the alphabet before you create any records and never change it afterwards. Existing keys are stored as strings, so a new alphabet can encode a new ticket number to a key that already exists, causing primary key collisions.

To generate a shuffled alphabet:
```ruby
require 'sqids'
puts Sqids::DEFAULT_ALPHABET.split('').shuffle.join
```

### Creating Models

Pretty keys require that your model use a string primary key:
```ruby
class CreatePosts < ActiveRecord::Migration[8.0]
  def change
    create_table :posts, id: :string do |t|
      t.string :title

      t.timestamps
    end
  end
end
```

You may choose to configure ActiveRecord to always generate migrations with a string primary key:
```ruby
  # application.rb

  # Default string primary key in migrations for use with Sqids
  config.generators do |generate|
    generate.orm :active_record, primary_key_type: :string
  end
```

### Including the Concern

Include the concern in your ApplicationRecord to use everywhere:
```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  include ActiveRecordPrettyKey::Concern
end
```

OR

Include the concern on a model by model basis:
```ruby
class Post < ApplicationRecord
  include ActiveRecordPrettyKey::Concern
end
```

### Generating Keys

Keys are generated automatically before a record is created:
```ruby
post = Post.create(title: "My Awesome Post")
post.id
# => "BnJe"
```

Or the generation helper can be called manually. It returns the record's key, and does not replace a key that is already set:
```ruby
post = Post.new(title: "My Awesome Post")
post.generate_pretty_key
# => "9LW9"

post.save!
```

Because keys are generated in a `before_create` callback, which runs *after* validation, don't add `validates :id, presence: true`. If you need the key during validation, generate it first:
```ruby
class Post < ApplicationRecord
  include ActiveRecordPrettyKey::Concern
  before_validation :generate_pretty_key, on: :create
end
```

### Associations

Every column that refers to a pretty-keyed record must also be a string, including foreign keys and polymorphic `*_id` columns:
```ruby
create_table :comments, id: :string do |t|
  t.references :post, type: :string, foreign_key: true
  t.references :commentable, polymorphic: true, type: :string
end
```

### Active Storage

For the same reason, Active Storage's polymorphic `record_id` column must be a string:
```ruby
class FixAttachmentsFks < ActiveRecord::Migration[8.0]
  def change
    change_column :active_storage_attachments, :record_id, :string, null: false
  end
end
```

### How tickets are generated

Keys are generated inside the record's save transaction. A ticket number is never handed out twice, even if that transaction rolls back, and generating one doesn't hold locks until it commits:

- **PostgreSQL** uses a sequence (`nextval`), which takes no locks and is not rolled back.
- **MySQL** uses a dedicated connection pool for the tickets table, so each ticket commits immediately on its own, separately from your transaction. The pool is created on first use with the same settings as your application's pool, so each process may open up to `pool` additional database connections; account for this in your database's `max_connections`.
- **SQLite** allows only one writer at a time, so tickets are generated in your transaction and **rolled back with it**. A key that was read inside a transaction that then rolled back (for example, passed to a job or API before the rollback) can be given to a later record. Use keys outside a transaction only once it has committed.

If the ticket row is missing, for example in a database created from `schema.rb` with `db:schema:load` or `db:prepare`, it is recreated automatically.

## Security

Pretty keys are **obfuscated, not encrypted**. Each key is an encoded, globally sequential ticket number:

- With the default alphabet, anyone can decode a key back to its ticket number (e.g. `Sqids.new(min_length: 4).decode("gbHJ") # => [2]`) and generate the keys before and after it.
- A shuffled alphabet makes this harder, but it is not a cryptographic secret and should not be treated as one.
- Because the ticket counter is shared across all models, decoded keys reveal roughly how many records your application has created and how quickly.

Never rely on a key being unguessable for authorization. Always check that the current user is allowed to access the record.

## Development

After checking out the repo, run `bin/setup` to install dependencies and run the specs. Run `bundle exec rspec` to run the tests, and `bin/console` for an interactive prompt with an in-memory database and a `Post` model.

The specs use in-memory SQLite by default. To run them against another database, install its driver group and set `DB` (and optionally `DATABASE_URL`):

```bash
docker run -d --rm -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=pretty_key_test postgres:17
BUNDLE_WITH=postgresql bundle install
DB=postgresql bundle exec rspec

docker run -d --rm -p 3306:3306 -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=pretty_key_test mysql:8.4
BUNDLE_WITH=mysql bundle install
DB=mysql2 bundle exec rspec   # or DB=trilogy
```

CI runs the suite against all four adapters.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in the `VERSION` file, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org). Releases require RubyGems multi-factor authentication.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/noreastergroup/active_record_pretty_key. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/noreastergroup/active_record_pretty_key/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ActiveRecordPrettyKey project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/noreastergroup/active_record_pretty_key/blob/main/CODE_OF_CONDUCT.md).
