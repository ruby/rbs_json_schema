require_relative 'lib/rbs_json_schema/version'

Gem::Specification.new do |spec|
  spec.name          = "rbs_json_schema"
  spec.version       = RBSJsonSchema::VERSION
  spec.authors       = ["Soutaro Matsumoto"]
  spec.email         = ["matsumoto@soutaro.com"]

  spec.summary       = %q{Generate RBS type definitions from JSON Schema}
  spec.description   = %q{Generate RBS type definitions from JSON Schema}
  spec.homepage      = "https://github.com/ruby/rbs_json_schema"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ruby/rbs_json_schema"
  spec.metadata["changelog_uri"] = "https://github.com/soutaro/rbs_json_schema/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "rbs", ">=1.8.0"
  spec.add_runtime_dependency "activesupport", ">=5.0.0"
end
