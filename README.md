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
| **Security** | ❌ Predictable, easily guessable | ✅ Random and secure | ✅ Obfuscated but readable |
| **Length** | ✅ Very short | ❌ Very long (36 chars) | ✅ Short (8-12 chars) |
| **Collision Risk** | ✅ None (auto-increment) | ✅ Extremely low | ✅ None (ticket database table) |

Pretty keys offer a middle ground between auto-incrementing integers and UUIDs — they're human-readable identifiers that remain secure, performant, and user-friendly.

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

This will create a migration that sets up the tickets table needed for generating unique IDs.

### Customizing or Randomising the Sqids Alphabet

Configration of a customized Sqids ID alphabet can be done by setting Rails credentials like so:

```yaml
sqids:
  alphabet: "ENwUpVBslGq25afc6i0hyD4tnjxRY31Wouz7HFTeMKgSbmPZvJ9ALXCQdrkI8O"
```

This can be used to configure a randomized alphabet to obfuscate object IDs.

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

Keys are generated before-save automatically:
```ruby
post = Post.create(title: "My Awesome Post")
post.id
# => "BnJe"
```

Or the generation helper can be called manually:
```ruby
post = Post.new(title: "My Awesome Post")
post.generate_pretty_key
# => "9LW9"

post.save!
```

### Active Storage

When working with Active Storage remember to properly set the attachments foreign key type:
```ruby
class FixAttachmentsFks < ActiveRecord::Migration[8.0]
  def change
    change_column :active_storage_attachments, :record_id, :string, null: false
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/noreastergroup/active_record_pretty_key. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/noreastergroup/active_record_pretty_key/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ActiveRecordPrettyKey project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/noreastergroup/active_record_pretty_key/blob/main/CODE_OF_CONDUCT.md).
