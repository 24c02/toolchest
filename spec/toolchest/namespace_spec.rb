require "spec_helper"

RSpec.describe "Multi-mount" do
  let(:public_toolbox) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "OrdersToolbox"

      tool "Show order" do
        param :id, :string, "ID"
      end
      def show = render_error "stub"
    end
  end

  let(:admin_toolbox) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "Admin::OrdersToolbox"

      tool "Refund order" do
        param :id, :string, "ID"
      end
      def refund = render_error "stub"
    end
  end

  describe "per-mount configuration" do
    it "stores separate configs" do
      Toolchest.configure do |c|
        c.auth = :oauth
      end

      Toolchest.configure(:admin) do |c|
        c.auth = :token
      end

      expect(Toolchest.configuration.auth).to eq(:oauth)
      expect(Toolchest.configuration(:admin).auth).to eq(:token)
    end

    it "configure without name is sugar for :default" do
      Toolchest.configure { |c| c.server_name = "Public" }
      expect(Toolchest.configuration(:default).server_name).to eq("Public")
    end
  end

  describe "per-mount routers" do
    it "registers toolboxes independently" do
      Toolchest.router(:default).register(public_toolbox)
      Toolchest.router(:admin).register(admin_toolbox)

      default_tools = Toolchest.router(:default).tools_list
      admin_tools = Toolchest.router(:admin).tools_list

      expect(default_tools.map { |t| t[:name] }).to eq(["orders_show"])
      expect(admin_tools.map { |t| t[:name] }).to eq(["admin_orders_refund"])
    end

    it "dispatches within mount only" do
      Toolchest.router(:default).register(public_toolbox)
      Toolchest.router(:admin).register(admin_toolbox)

      # admin router can't see default tools
      response = Toolchest.router(:admin).dispatch("orders_show", {})
      expect(response[:isError]).to be true
      expect(response[:content].first[:text]).to include("Unknown tool")
    end
  end

  describe "mount_keys" do
    it "tracks configured mounts" do
      Toolchest.configure { |c| c.auth = :none }
      Toolchest.configure(:admin) { |c| c.auth = :token }

      expect(Toolchest.mount_keys).to contain_exactly(:default, :admin)
    end
  end
end
