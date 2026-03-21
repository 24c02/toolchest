require "spec_helper"

RSpec.describe Toolchest::Naming do
  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "OrdersToolbox"
    end
  end

  let(:namespaced_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "Admin::OrdersToolbox"
    end
  end

  describe ".generate" do
    it "generates underscored names" do
      expect(described_class.generate(toolbox_class, :show, :underscored)).to eq("orders_show")
    end

    it "generates dotted names" do
      expect(described_class.generate(toolbox_class, :show, :dotted)).to eq("orders.show")
    end

    it "generates slashed names" do
      expect(described_class.generate(toolbox_class, :show, :slashed)).to eq("orders/show")
    end

    it "handles namespaced toolboxes" do
      expect(described_class.generate(namespaced_class, :show, :underscored)).to eq("admin_orders_show")
    end

    it "supports custom lambda" do
      strategy = ->(prefix, method) { "#{prefix}__#{method}" }
      expect(described_class.generate(toolbox_class, :show, strategy)).to eq("orders__show")
    end
  end
end
