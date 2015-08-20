# Sequelizer

I was tired of writing the code to bootstrap a connection to my databases.

[Sequel](https://github.com/jeremyevans/sequel/) provides an easy mechanism for connecting to a database, but I didn't want to store my username/password/other sensitive information in the scripts I was writing.

So I wrote this gem that lets me store my database configuration options in either config/database.yml or .env and then lets me call `db` to get a connection to my database.

I normally use this gem when I'm writing a quick script or a Thor-based command line utility.

## Installation

Add this line to your application's Gemfile:

    gem 'sequelizer'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sequelizer

## Usage

To get the most out of Sequelizer, you'll need to create a config/database.yml file or a .env file and specify your database configuration options in that file.

Sequelizer comes with a handy command that will print out your connection parameters.  Just run:

    bundle exec sequelizer config

You'll also need to make sure the gem for your database is installed.  You can do this by adding the gem to your application's Gemfile.

Sequelizer comes with a handy command that will update your Gemfile for you.  Once you've specified your database configuration, run

    bundle exec sequelizer update_gemfile

The command will look up the right gem to use with the adapter you've specified, add a line to your Gemfile specifying that gem, and run `bundle install` to install the gem for you.

Once you've specified your options and made sure your database's gem is installed, simply include the Sequelizer module in any class that needs a database connection and you'll get two handy-dandy methods: `db` and `new_db`

Observe:
```ruby
require 'sequelizer'

class ClassThatNeedsSomeDBLove
  include Sequelizer

  def my_super_cool_method_that_needs_to_talk_to_a_db
    db[:my_awesome_table].join(
      db[:another_great_table].select(:an_important_column),
      [:an_important_column])
  end
end
```

`db` will create a new connection to the database and cache that connection so that subsequent calls to `db` will use the same connection.

`new_db` will create a new connection to the database on each call.

Both take a hash of database options if you don't want to create a config/database.yml or .env file, or simply wish to override those options.  Options are merged together from all sources with the following precedence:

    passed_options > .env > manually defined environment variables > config/database.yml > ~/.config/sequelizer/database.yml

So if config/database.yml specifies a connection, you can set an environment variable (either manually, or through .env) to override one of those options.  Similarly, if you pass an option to the method directly, that option will override the YAML and ENV-based options.  See #3 for further discussion.

Take a look at the examples directory for a few ways you can specify your database configuration options.

## Frustrations

I can't seem to figure out a way to avoid having to specify the database gem in the a user's bundler file.  If anyone has ideas on how to automagically load the correct database gem based on the database options fed to Sequelizer, please let me know (#1)!

## Contributing

1. Fork it ( http://github.com/outcomesinsights/sequelizer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Thanks

- [Outcomes Insights, Inc.](http://outins.com)
    - Many thanks for allowing me to release a portion of my work as Open Source Software!
- Jeremy Evans
    - For writing Sequel!

## License
Released under the MIT license, Copyright (c) 2014 Outcomes Insights, Inc.
