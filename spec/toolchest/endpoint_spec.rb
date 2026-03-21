require "spec_helper"

# Engine is only loaded when Rails::Engine is defined.
# Stub it for unit tests.
unless defined?(Toolchest::Engine)
  module Toolchest
    module Engine
      def self.ensure_initialized!; end
    end
  end
end

RSpec.describe Toolchest::Endpoint do
  let(:endpoint) { described_class.new }

  describe "#call" do
    it "delegates to a RackApp for the mount" do
      fake_app = double("RackApp", call: [200, {}, ["ok"]])
      Toolchest.router(:default).rack_app = fake_app

      env = { "toolchest.mount_key" => "default" }
      result = endpoint.call(env)
      expect(result).to eq([200, {}, ["ok"]])
    end

    it "defaults to :default mount when no mount_key in env" do
      fake_app = double("RackApp", call: [200, {}, ["ok"]])
      Toolchest.router(:default).rack_app = fake_app

      env = {}
      result = endpoint.call(env)
      expect(result).to eq([200, {}, ["ok"]])
    end

    it "routes to the correct mount" do
      admin_app = double("AdminRackApp", call: [200, {}, ["admin"]])
      Toolchest.router(:admin).rack_app = admin_app

      env = { "toolchest.mount_key" => "admin" }
      result = endpoint.call(env)
      expect(result).to eq([200, {}, ["admin"]])
    end
  end
end
