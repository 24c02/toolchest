require_relative "../rails_helper"
require "generators/toolchest/toolbox_generator"

RSpec.describe Toolchest::Generators::ToolboxGenerator do
  include FileUtils

  let(:destination) { Dir.mktmpdir("toolchest_gen_test") }

  before do
    described_class.start(args, destination_root: destination)
  end

  after { rm_rf(destination) }

  context "with Orders show create" do
    let(:args) { ["Orders", "show", "create"] }

    it "creates the toolbox" do
      path = File.join(destination, "app/toolboxes/orders_toolbox.rb")
      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include("class OrdersToolbox < ApplicationToolbox")
      expect(content).to include("def show")
      expect(content).to include("def create")
    end

    it "creates view files for each action" do
      %w[show create].each do |action|
        path = File.join(destination, "app/views/toolboxes/orders/#{action}.json.jb")
        expect(File.exist?(path)).to be true
      end
    end

    it "creates spec file" do
      path = File.join(destination, "spec/toolboxes/orders_toolbox_spec.rb")
      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include("RSpec.describe OrdersToolbox")
      expect(content).to include("orders_show")
      expect(content).to include("orders_create")
    end
  end

  context "with Admin::Orders show" do
    let(:args) { ["Admin::Orders", "show"] }

    it "creates namespaced toolbox" do
      path = File.join(destination, "app/toolboxes/admin/orders_toolbox.rb")
      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include("class Admin::OrdersToolbox < Admin::ApplicationToolbox")
    end

    it "creates namespaced views" do
      path = File.join(destination, "app/views/toolboxes/admin/orders/show.json.jb")
      expect(File.exist?(path)).to be true
    end

    it "creates namespaced spec" do
      path = File.join(destination, "spec/toolboxes/admin/orders_toolbox_spec.rb")
      expect(File.exist?(path)).to be true
    end
  end
end
