require 'bundler/gem_helper'
require 'rake/testtask'

# Not bundler/gem_tasks: its `release` task (and `release:rubygem_push`) would
# tag whatever is checked out and push the gem from this machine, skipping the
# checks in .github/workflows/release.yml. Only build and install are kept.
gem_helper = Bundler::GemHelper.new(__dir__)

desc "Build #{gem_helper.gemspec.name}-#{gem_helper.gemspec.version}.gem into the pkg directory"
task(:build) { gem_helper.build_gem }

desc "Build and install #{gem_helper.gemspec.name}-#{gem_helper.gemspec.version}.gem into system gems"
task(install: :build) { gem_helper.install_gem }

desc 'Disabled: releases publish from GitHub Actions when a v* tag is pushed'
task :release do
  abort <<~MSG
    rake release is disabled. To release: bump VERSION in lib/sequelizer/version.rb,
    update CHANGELOG.md (git-cliff --unreleased --bump), land that commit on main,
    wait for CI to pass on it, then push the matching tag (git tag vX.Y.Z && git push
    origin vX.Y.Z). .github/workflows/release.yml checks the tag and publishes.
  MSG
end

Rake::TestTask.new do |t|
  t.libs = %w[lib test]
  t.warning = true
  t.test_files = FileList['test/**/test_*.rb']
end

begin
  require 'rubocop/rake_task'

  RuboCop::RakeTask.new(:lint) do |task|
    task.options = [ '--display-cop-names' ]
  end

  RuboCop::RakeTask.new(:format) do |task|
    task.options = [ '--auto-correct-all' ]
  end

  desc 'Run RuboCop with safe autocorrect'
  task :lint_fix do
    system('bundle exec rubocop --autocorrect')
  end
rescue LoadError
  # RuboCop not available
end

desc 'Run tests with coverage report'
task :coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:test].invoke
end

task default: :test
