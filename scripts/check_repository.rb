#!/usr/bin/env ruby
# Offline documentation/resource checks; does not read credentials or health data.
require 'json'
require 'yaml'
require 'pathname'

root = Pathname.new(__dir__).parent
pages = %w[README.md FORK_NOTES.md NOTICE.md CONTRIBUTING.md docs/README.md
           docs/DEVELOPMENT.md docs/PRIVACY.md docs/LICENSING.md docs/EVIDENCE.md docs/media/README.md]
failures = []
pages.each do |page|
  file = root.join(page)
  text = file.read
  links = text.scan(/\]\(([^)]+)\)/).flatten + text.scan(/(?:src|href)="([^"]+)"/).flatten
  links.each do |link|
    next if link.match?(/\A(?:https?:|mailto:|#)/)
    path = link.split('#', 2).first
    failures << "#{page}: missing #{path}" unless file.dirname.join(path).exist?
  end
end

failures << 'Bundled GPL differs from root LICENSE' unless root.join('LICENSE').binread == root.join('xDrip/Resources/Legal/GPL-3.0.txt').binread
notices = root.join('xDrip/Resources/Legal/ThirdPartyNotices.txt').read
pins = JSON.parse(root.join('xdrip.xcworkspace/xcshareddata/swiftpm/Package.resolved').read).fetch('pins')
pins.each do |pin|
  revision = pin.fetch('state').fetch('revision')
  failures << "Update notices for #{pin.fetch('identity')} #{revision}" unless notices.include?(revision)
end
%w[ActionClosurable CryptoSwift PieCharts SwiftCharts Icons8].each do |name|
  failures << "Missing notice: #{name}" unless notices.include?(name)
end
required = 'This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/).'
failures << 'Missing CryptoSwift acknowledgement' unless notices.include?(required)

workflow = YAML.load_file(root.join('.github/workflows/build_xdrip.yml'))
# Psych uses YAML 1.1, where GitHub's unquoted `on` is parsed as true.
events = workflow['on'] || workflow[true]
failures << 'Signed build must remain manual-only' unless events.keys == ['workflow_dispatch']
failures << 'Workflow must not synchronize upstream' if root.join('.github/workflows/build_xdrip.yml').read.include?('Fork-Sync-With-Upstream')
failures << 'Binary publishing must be opt-in' unless events.dig('workflow_dispatch', 'inputs', 'upload_to_testflight', 'default') == false

abort failures.join("\n") unless failures.empty?
puts "PASS: #{pages.length} documentation pages, local links/media, license copy, dependency notices and manual release controls"
