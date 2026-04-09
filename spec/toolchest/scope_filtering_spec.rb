require "spec_helper"

RSpec.describe "Scope filtering" do
  let(:orders_toolbox) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "OrdersToolbox"

      tool "Show order" do
        param :id, :string, "ID"
      end
      def show = render_error "stub"

      tool "Cancel order" do
        param :id, :string, "ID"
      end
      def cancel = render_error "stub"

      tool "Search orders" do
      end
      def search = render_error "stub"

      tool "Force sync", access: :write do
      end
      def force_sync = render_error "stub"
    end
  end

  let(:users_toolbox) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "UsersToolbox"

      tool "List users" do
      end
      def index = render_error "stub"
    end
  end

  let(:tickets_toolbox) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "TicketsToolbox"

      tool "List tickets" do
      end
      def list = render_error "stub"

      tool "Move ticket", scope: "admin" do
        param :status, :string, "New status"
      end
      def move = render_error "stub"

      tool "Escalate ticket", scope: ["admin", "superuser"] do
        param :id, :string, "ID"
      end
      def escalate = render_error "stub"
    end
  end

  let(:router) { Toolchest.router }

  before do
    Toolchest.configure do |config|
      config.filter_tools_by_scope = true
    end
    router.register(orders_toolbox)
    router.register(users_toolbox)
  end

  it "shows all tools when no auth" do
    expect(router.tools_for_handler.length).to eq(5)
  end

  it "filters tools by scope prefix" do
    auth = Struct.new(:scopes).new("orders:read")
    Toolchest::Current.set(auth: auth) do
      names = router.tools_for_handler.map { |t| t[:name] }
      expect(names).to include("orders_show")
      expect(names).not_to include("users_index")
    end
  end

  it "read scope only grants read actions (show, index, search)" do
    auth = Struct.new(:scopes).new("orders:read")
    Toolchest::Current.set(auth: auth) do
      names = router.tools_for_handler.map { |t| t[:name] }
      expect(names).to include("orders_show", "orders_search")
      expect(names).not_to include("orders_cancel", "orders_force_sync")
    end
  end

  it "write scope grants both read and write actions" do
    auth = Struct.new(:scopes).new("orders:write")
    Toolchest::Current.set(auth: auth) do
      names = router.tools_for_handler.map { |t| t[:name] }
      expect(names).to contain_exactly("orders_show", "orders_cancel", "orders_search", "orders_force_sync")
    end
  end

  it "bare scope (no :read/:write suffix) grants full access" do
    auth = Struct.new(:scopes).new("orders")
    Toolchest::Current.set(auth: auth) do
      names = router.tools_for_handler.map { |t| t[:name] }
      expect(names).to contain_exactly("orders_show", "orders_cancel", "orders_search", "orders_force_sync")
    end
  end

  it "respects explicit access: override" do
    # force_sync is not in READ_ACTIONS but could look like one by name.
    # We explicitly set access: :write, so orders:read should NOT include it.
    auth = Struct.new(:scopes).new("orders:read")
    Toolchest::Current.set(auth: auth) do
      names = router.tools_for_handler.map { |t| t[:name] }
      expect(names).not_to include("orders_force_sync")
    end
  end

  it "shows all tools when filter_tools_by_scope is false" do
    Toolchest.configuration.filter_tools_by_scope = false
    auth = Struct.new(:scopes).new("orders:read")
    Toolchest::Current.set(auth: auth) do
      expect(router.tools_for_handler.length).to eq(5)
    end
  end

  # --- per-tool scope override ---

  describe "tool-level scope:" do
    before { router.register(tickets_toolbox) }

    it "hides scoped tool when token lacks the required scope" do
      auth = Struct.new(:scopes).new("tickets:write")
      Toolchest::Current.set(auth: auth) do
        names = router.tools_for_handler.map { |t| t[:name] }
        expect(names).to include("tickets_list")
        expect(names).not_to include("tickets_move")
      end
    end

    it "shows scoped tool when token has the exact scope" do
      auth = Struct.new(:scopes).new("tickets:write admin")
      Toolchest::Current.set(auth: auth) do
        names = router.tools_for_handler.map { |t| t[:name] }
        expect(names).to include("tickets_list", "tickets_move")
      end
    end

    it "convention-based scopes don't grant access to scoped tools" do
      auth = Struct.new(:scopes).new("tickets")
      Toolchest::Current.set(auth: auth) do
        names = router.tools_for_handler.map { |t| t[:name] }
        expect(names).to include("tickets_list")
        expect(names).not_to include("tickets_move")
      end
    end

    it "accepts any scope from an array (OR)" do
      auth = Struct.new(:scopes).new("superuser")
      Toolchest::Current.set(auth: auth) do
        names = router.tools_for_handler.map { |t| t[:name] }
        expect(names).to include("tickets_escalate")
        expect(names).not_to include("tickets_move")
      end
    end

    it "enforces scope on dispatch too" do
      Toolchest.configuration.auth = :token
      auth = Struct.new(:scopes).new("tickets:write")
      Toolchest::Current.set(auth: auth) do
        result = router.dispatch("tickets_move", { "status" => "closed" })
        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include("Forbidden")
      end
    end
  end

  # --- dispatch enforcement ---

  describe "dispatch scope enforcement" do
    it "blocks tool execution when scope is insufficient" do
      Toolchest.configuration.auth = :token
      auth = Struct.new(:scopes).new("orders:read")
      Toolchest::Current.set(auth: auth) do
        result = router.dispatch("orders_cancel", {})
        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include("Forbidden")
      end
    end

    it "allows tool execution when scope matches" do
      Toolchest.configuration.auth = :token
      auth = Struct.new(:scopes).new("orders:write")
      Toolchest::Current.set(auth: auth) do
        result = router.dispatch("orders_cancel", { "id" => "1" })
        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).not_to include("Forbidden")
      end
    end

    it "blocks dispatch when auth is missing and auth is not :none" do
      Toolchest.configuration.auth = :token
      result = router.dispatch("orders_show", { "id" => "1" })
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include("Forbidden")
    end

    it "allows dispatch without auth when auth is :none" do
      Toolchest.configuration.auth = :none
      result = router.dispatch("orders_show", { "id" => "1" })
      # should reach the stub, not get blocked
      expect(result[:content].first[:text]).not_to include("Forbidden")
    end

    it "skips scope enforcement when filter_tools_by_scope is false" do
      Toolchest.configuration.auth = :token
      Toolchest.configuration.filter_tools_by_scope = false
      auth = Struct.new(:scopes).new("orders:read")
      Toolchest::Current.set(auth: auth) do
        result = router.dispatch("orders_cancel", { "id" => "1" })
        expect(result[:content].first[:text]).not_to include("Forbidden")
      end
    end
  end
end
