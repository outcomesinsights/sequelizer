require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs = ['lib']
  t.warning = true
  t.test_files = FileList['test/**/test_*.rb']
end

begin
  require 'rubocop/rake_task'

  RuboCop::RakeTask.new(:lint) do |task|
    task.options = ['--display-cop-names']
  end

  RuboCop::RakeTask.new(:format) do |task|
    task.options = ['--auto-correct-all']
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
