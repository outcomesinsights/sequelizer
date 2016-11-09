# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sequelizer/version'

Gem::Specification.new do |spec|
  spec.name          = 'sequelizer'
  spec.version       = Sequelizer::VERSION
  spec.authors       = ['Ryan Duryea']
  spec.email         = ['aguynamedryan@gmail.com']
  spec.summary       = %q{Sequel database connections via config/database.yml or .env}
  spec.description   = %q{Easily establish a connection to a database via Sequel gem using options specified in config/database.yml or .env files}
  spec.homepage      = 'https://github.com/outcomesinsights/sequelizer'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.5'
  spec.add_development_dependency 'guard', '~> 2.0'
  spec.add_development_dependency 'guard-minitest', '~> 2.3'
  spec.add_development_dependency 'minitest', '~> 5.3'
  spec.add_dependency 'sequel', '~> 4.12'
  spec.add_dependency 'dotenv', '~> 2.1'
  spec.add_dependency 'thor', '~> 0.19'
  spec.add_dependency 'hashie', '~> 3.2'
end
