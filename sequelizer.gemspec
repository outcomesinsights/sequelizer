lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sequelizer/version'

Gem::Specification.new do |spec|
  spec.name          = 'sequelizer'
  spec.version       = Sequelizer::VERSION
  spec.authors       = ['Ryan Duryea']
  spec.email         = ['aguynamedryan@gmail.com']
  spec.summary       = 'Sequel database connections via config/database.yml or .env'
  spec.description   = 'Easily establish a connection to a database via Sequel gem using options specified in config/database.yml or .env files'
  spec.homepage      = 'https://github.com/outcomesinsights/sequelizer'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2.0'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'guard', '~> 2.0'
  spec.add_development_dependency 'guard-minitest', '~> 2.3'
  spec.add_development_dependency 'minitest', '~> 5.3'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
  spec.add_development_dependency 'rubocop-minitest', '~> 0.25'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_dependency 'activesupport', '~> 7.0'
  spec.add_dependency 'dotenv', '~> 2.1'
  spec.add_dependency 'hashie', '~> 3.2'
  spec.add_dependency 'sequel', '~> 5.93'
  spec.add_dependency 'thor', '~> 1.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
