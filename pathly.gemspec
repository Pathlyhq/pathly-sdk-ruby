# frozen_string_literal: true

require_relative "lib/pathly/version"

Gem::Specification.new do |spec|
  spec.name          = "pathly"
  spec.version       = Pathly::VERSION
  spec.authors       = ["Simon Raynaud / keyral"]
  spec.email         = ["devs@pathlyhq.com"]

  spec.summary       = "Official Ruby SDK for the Pathly public /v1 API"
  spec.description   =
    "Manage Pathly HTTP monitoring scenarios, maintenance windows, " \
    "signed webhooks and SLA targets from Ruby scripts and CI."
  spec.homepage      = "https://pathlyhq.com"
  spec.license       = "Apache-2.0"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = "https://pathlyhq.com"
  spec.metadata["documentation_uri"] = "https://pathlyhq.com/en/developers"
  spec.metadata["source_code_uri"] = "https://github.com/pathlyhq/pathly-sdk-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/pathlyhq/pathly-sdk-ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/pathlyhq/pathly-sdk-ruby/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,examples}/**/*", "LICENSE", "NOTICE", "AUTHORS", "README.md", "README.fr.md", "CHANGELOG.md"]
  end
  spec.require_paths = ["lib"]
end
