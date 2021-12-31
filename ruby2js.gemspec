# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'ruby2js/version'

Gem::Specification.new do |s|
  s.name = "ruby2js"
  s.version = Ruby2JS::VERSION::STRING

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Sam Ruby", "Jared White"]
  s.description = "    The base package maps Ruby syntax to JavaScript semantics.\n    Filters may be provided to add Ruby-specific or framework specific\n    behavior.\n"
  s.email = "rubys@intertwingly.net"
  s.files = %w(ruby2js.gemspec README.md bin/ruby2js demo/ruby2js.rb) + Dir.glob("{lib}/**/*")
  s.homepage = "http://github.com/rubys/ruby2js"
  s.licenses = ["MIT"]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3")
  s.summary = "Minimal yet extensible Ruby to JavaScript conversion."

  s.executables << 'ruby2js'

  s.add_dependency('parser')
  s.add_dependency('regexp_parser', '~> 2.1.1')
end
