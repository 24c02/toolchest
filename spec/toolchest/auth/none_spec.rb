require "spec_helper"

RSpec.describe Toolchest::Auth::None do
  let(:strategy) { described_class.new }

  describe "#authenticate" do
    it "returns nil regardless of request" do
      request = Struct.new(:env).new({"HTTP_AUTHORIZATION" => "Bearer something"})
      expect(strategy.authenticate(request)).to be_nil
    end

    it "returns nil with empty request" do
      request = Struct.new(:env).new({})
      expect(strategy.authenticate(request)).to be_nil
    end
  end
end
