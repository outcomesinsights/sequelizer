# Sequelizer

I was tired of writing the code to bootstrap a connection to my databases.

Sequel provides an easy mechanism for connecting to a database, but I didn't
want to store my username/password/other sensitive information in the scripts
I was writing.

So I wrote this gem that lets me store my database configuration options in
either config/database.yml or .env and then lets me call `db` to get a
connection to my database.

I normally use this gem when I'm writing a quick script or a Thor-based
command line utility.

## Installation

Add this line to your application's Gemfile:

    gem 'sequelizer'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sequelizer

## Usage

To get the most out of Sequelizer, you'll need to create a config/database.yml
file or a .env file and specify your database configuration options in that
file.

You'll also need to make sure the gem for your database is installed.  You
can do this by adding a the gem to your application's Gemfile.

Once you've specified your options and made sure your database's gem is
installed, simply include the Sequelizer module in any class that needs a
database connection and you'll get two handy-dandy methods:
`db` and `new_db`

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

`db` will create a new connection to the database and cache that connection
so that subsequent calls to `db` will use the same connection.

`new_db` will create a new connection to the database on each call.

Both take a set of database options if you don't want to create a
config/database.yml or .env file, or simply wish to override those options.

Take a look at the examples directory for a few ways you can specify your
database configuration options.

## Frustrations

I can't seem to figure out a way to avoid having to specify the database gem
in the a user's bundler file.  If anyone has ideas on how to automagically
load the correct database gem based on the database options fed to Sequelizer,
please let me know!

## Contributing

1. Fork it ( http://github.com/<my-github-username>/sequelizer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Thanks

Many thanks to Outcomes Insights, Inc. for allowing me to release a portion
of my work as Open Source Software!
