require "spec_helper"
require "toolchest/rspec"

RSpec.describe "RSpec helpers", type: :toolbox do
  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "WidgetsToolbox"

      tool "Show a widget" do
        param :widget_id, :string, "Widget ID"
      end
      def show
        render_error "not found" unless params[:widget_id] == "exists"
      end

      tool "Create a widget" do
        param :name, :string, "Name"
      end
      def create = suggests :show, "Get the widget"
    end
  end

  before do
    Toolchest.router.register(toolbox_class)
  end

  describe "call_tool + matchers" do
    it "dispatches and returns response" do
      allow(Toolchest::Renderer).to receive(:render).and_return({ id: "exists" })

      call_tool "widgets_show", params: { widget_id: "exists" }
      expect(tool_response).to be_success
    end

    it "detects errors" do
      call_tool "widgets_show", params: { widget_id: "nope" }
      expect(tool_response).to be_error
      expect(tool_response).to include_text("not found")
    end

    it "detects suggests" do
      allow(Toolchest::Renderer).to receive(:render).and_return({ id: "new" })

      call_tool "widgets_create", params: { name: "thing" }
      expect(tool_response).to suggest("widgets_show")
    end

    it "passes auth via as:" do
      allow(Toolchest::Renderer).to receive(:render).and_return({})

      user = Struct.new(:id).new(1)
      call_tool "widgets_show", params: { widget_id: "exists" }, as: user

      # auth is reset after call, but it was set during
      expect(tool_response).to be_success
    end
  end
end
