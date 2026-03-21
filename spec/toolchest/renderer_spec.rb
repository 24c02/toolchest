require "spec_helper"
require "action_view"
require "jb/handler"
require "jb/action_view_monkeys"
require "tmpdir"

RSpec.describe Toolchest::Renderer do
  let(:view_dir) { Dir.mktmpdir }

  before do
    Toolchest.configuration.additional_view_paths = [view_dir]
    described_class.send(:reset!)
  end

  after do
    FileUtils.rm_rf(view_dir)
  end

  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "OrdersToolbox"
    end
  end

  def create_template(path, content)
    full_path = File.join(view_dir, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  describe ".render" do
    it "renders a jb template with instance variables" do
      create_template("orders/show.json.jb", '{ id: @order[:id], status: @order[:status] }')

      toolbox = toolbox_class.new(params: {})
      toolbox.instance_variable_set(:@order, { id: "123", status: "shipped" })

      result = described_class.render(toolbox, :show)
      expect(result).to eq("id" => "123", "status" => "shipped")
    end

    it "renders a template by explicit path" do
      create_template("shared/status.json.jb", '{ ok: true }')

      toolbox = toolbox_class.new(params: {})
      result = described_class.render(toolbox, "shared/status")
      expect(result).to eq("ok" => true)
    end

    it "raises MissingTemplate when template not found" do
      toolbox = toolbox_class.new(params: {})

      expect {
        described_class.render(toolbox, :nonexistent)
      }.to raise_error(Toolchest::MissingTemplate)
    end

    it "supports partials" do
      create_template("orders/_item.json.jb", '{ name: item[:name] }')
      create_template("orders/show.json.jb", <<~JB)
        {
          items: @items.map { |item| render(partial: "orders/item", locals: { item: item }) }
        }
      JB

      toolbox = toolbox_class.new(params: {})
      toolbox.instance_variable_set(:@items, [{ name: "Widget" }, { name: "Gadget" }])

      result = described_class.render(toolbox, :show)
      expect(result["items"].length).to eq(2)
    end
  end
end
