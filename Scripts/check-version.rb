#!/usr/bin/env ruby
# frozen_string_literal: true

# Asserts that the app version and build number agree everywhere they appear.
# Version drift is easy to miss by hand and shows up in user-facing places.

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)

def read(path)
  File.read(File.join(ROOT, path), encoding: "UTF-8")
end

def plist(path, key)
  output, status = Open3.capture2("plutil", "-extract", key, "raw", "-o", "-", File.join(ROOT, path))
  abort("Unable to read #{key} from #{path}") unless status.success?

  output.strip
end

version = plist("Resources/Info.plist", "CFBundleShortVersionString")
build = plist("Resources/Info.plist", "CFBundleVersion")

abort("CFBundleShortVersionString #{version.inspect} is not X.Y.Z") unless version.match?(/\A\d+\.\d+\.\d+\z/)
abort("CFBundleVersion #{build.inspect} is not numeric") unless build.match?(/\A\d+\z/)

checks = []

# Both READMEs advertise the release, so accept ASCII or full-width parentheses.
%w[README.md README.zh-CN.md].each do |path|
  pattern = /\*\*#{Regexp.escape(version)}\s*[（(]Build\s+#{Regexp.escape(build)}[)）]\*\*/
  checks << [path, "Version **#{version} (Build #{build})**", read(path).match?(pattern)]
end

changelog = read("CHANGELOG.md")
checks << ["CHANGELOG.md", "## [#{version}] section", changelog.match?(/^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}$/)]
checks << [
  "CHANGELOG.md",
  "[Unreleased] compares against v#{version}",
  changelog.match?(/^\[Unreleased\]:\s+\S*\/compare\/v#{Regexp.escape(version)}\.\.\.HEAD$/)
]

issue_template = read(".github/ISSUE_TEMPLATE/bug_report.yml")
checks << [
  ".github/ISSUE_TEMPLATE/bug_report.yml",
  "placeholder: #{version} (Build #{build})",
  issue_template.include?("placeholder: #{version} (Build #{build})")
]

failed = checks.reject { |(_, _, ok)| ok }

unless failed.empty?
  failed.each do |(path, expectation, _)|
    warn "#{path}: expected #{expectation}"
  end
  abort "Version checks failed: Resources/Info.plist says #{version} (Build #{build})."
end

puts "Version checks passed: #{version} (Build #{build}) across #{checks.length} locations."
