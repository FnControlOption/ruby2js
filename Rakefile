require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"
require "bundler"

Bundler.setup

RuboCop::RakeTask.new

Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList["spec/*_spec.rb"]
  t.verbose = true
end

task :default => [:rubocop, :test]

namespace :demo do
  task :build do
    Dir.chdir('demo') { sh 'rake' }
  end
end

# Run `rake release` to release a new version of the gem.
