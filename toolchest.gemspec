require_relative "lib/toolchest/version"

Gem::Specification.new do |spec|
  spec.name = "toolchest"
  spec.version = Toolchest::VERSION
  spec.authors = ["Nora"]
  spec.summary = "MCP for Rails. Toolboxes are controllers, tools are actions."
  spec.description = "A Rails engine that maps the Model Context Protocol (MCP) to Rails conventions. " \
    "If you've built a controller, you already know how to build a toolbox."
  spec.homepage = "https://github.com/24c02/toolchest"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "LICENSE",
    "README.md",
    "LLMS.txt"
  ].reject { |f| f.end_with?("claudes_cool_post.txt") }

  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "mcp", ">= 0.10"
  # View layer: bring your own. jb (recommended), jbuilder, or blueprinter all work.

  spec.metadata = {
    "source_code_uri" => "https://github.com/24c02/toolchest",
    "changelog_uri" => "https://github.com/24c02/toolchest/blob/main/CHANGELOG.md"
  }
end
