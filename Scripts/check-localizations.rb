#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
SOURCE_ROOT = File.join(ROOT, "Sources")
LOCALES = %w[en zh-Hans].freeze

def load_strings(locale)
  path = File.join(ROOT, "Resources", "#{locale}.lproj", "Localizable.strings")
  output, status = Open3.capture2("plutil", "-convert", "json", "-o", "-", path)
  abort("Invalid localization file: #{path}") unless status.success?

  JSON.parse(output)
end

tables = LOCALES.to_h { |locale| [locale, load_strings(locale)] }
reference_keys = tables.fetch("en").keys.sort
failed = false

LOCALES.drop(1).each do |locale|
  missing = reference_keys - tables.fetch(locale).keys
  extra = tables.fetch(locale).keys - reference_keys
  unless missing.empty?
    warn "#{locale}: missing #{missing.length} keys:\n  #{missing.join("\n  ")}"
    failed = true
  end
  unless extra.empty?
    warn "#{locale}: extra #{extra.length} keys:\n  #{extra.sort.join("\n  ")}"
    failed = true
  end
end

format_tokens = /%(?:\d+\$)?(?:@|d|ld|lld|f|s)/
reference_keys.each do |key|
  expected = tables.fetch("en").fetch(key).scan(format_tokens).sort
  LOCALES.drop(1).each do |locale|
    actual = tables.fetch(locale).fetch(key, "").scan(format_tokens).sort
    next if actual == expected

    warn "#{locale}: format tokens differ for #{key.inspect}: #{actual.inspect} != #{expected.inspect}"
    failed = true
  end
end

source = Dir.glob(File.join(SOURCE_ROOT, "**", "*.swift")).sort.to_h do |path|
  [path, File.read(path, encoding: "UTF-8")]
end

source.each do |path, contents|
  contents.each_line.with_index(1) do |line, line_number|
    next unless line.match?(/[\p{Han}]/)

    warn "Hard-coded Han character: #{path.delete_prefix("#{ROOT}/")}:#{line_number}"
    failed = true
  end
end

localized_call = /(?:(?:Core)?L10n\.(?:tr|format)|Text|Button|Label|Picker|Toggle)\(\s*"((?:\\.|[^"\\])*)"/m
used_keys = source.values.flat_map do |contents|
  contents.scan(localized_call).flatten.map { |key| key.gsub("\\n", "\n") }
end.reject { |key| key.include?("\\(") }.uniq.sort

missing_from_catalog = used_keys - reference_keys
unless missing_from_catalog.empty?
  warn "English localization catalog is missing #{missing_from_catalog.length} UI keys:\n  #{missing_from_catalog.join("\n  ")}"
  failed = true
end

abort "Localization checks failed." if failed
puts "Localization checks passed: #{reference_keys.length} keys across #{LOCALES.join(" + ")}."
