require "toolchest"

module Toolchest
  module RSpec
    class ToolResponse
      attr_reader :raw

      def initialize(raw) = @raw = raw

      def success? = !error?

      def error? = @raw[:isError] == true

      def content = @raw[:content] || []

      def text = content.map { |c| c[:text] }.compact.join("\n")

      def suggests?(tool_name) = text.include?("Suggested next: call #{tool_name}")
    end

    module Helpers
      def call_tool(tool_name, params: {}, as: nil)
        Toolchest::Current.set(auth: as) do
          raw = Toolchest.router.dispatch(tool_name, params)
          @_tool_response = ToolResponse.new(raw)
        end
      end

      def tool_response = @_tool_response
    end

    module Matchers
      extend ::RSpec::Matchers::DSL

      matcher :be_success do
        match { |response| response.success? }
        failure_message { "expected tool response to be success, got error: #{actual.text}" }
      end

      matcher :be_error do
        match { |response| response.error? }
        failure_message { "expected tool response to be an error, but it succeeded" }
      end

      matcher :include_text do |expected|
        match { |response| response.text.include?(expected) }
        failure_message { "expected tool response text to include #{expected.inspect}, got: #{actual.text}" }
      end

      matcher :suggest do |tool_name|
        match { |response| response.suggests?(tool_name) }
        failure_message { "expected tool response to suggest #{tool_name}, got: #{actual.text}" }
      end
    end
  end
end

RSpec.configure do |config|
  config.include Toolchest::RSpec::Helpers, type: :toolbox
  config.include Toolchest::RSpec::Matchers, type: :toolbox
end
