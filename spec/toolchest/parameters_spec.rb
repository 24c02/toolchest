require "spec_helper"

RSpec.describe Toolchest::Parameters do
  let(:tool_definition) do
    Toolchest::ToolDefinition.new(
      method_name: :update,
      description: "Update",
      params: [
        Toolchest::ParamDefinition.new(name: :status, type: :string),
        Toolchest::ParamDefinition.new(name: :note, type: :string, optional: true)
      ],
      toolbox_class: Class.new(Toolchest::Toolbox)
    )
  end

  describe "schema filtering" do
    it "drops undeclared keys" do
      params = described_class.new(
        { status: "shipped", hacker: "evil" },
        tool_definition: tool_definition
      )
      expect(params[:status]).to eq("shipped")
      expect(params[:hacker]).to be_nil
    end

    it "keeps declared keys" do
      params = described_class.new(
        { status: "shipped", note: "fast" },
        tool_definition: tool_definition
      )
      expect(params[:status]).to eq("shipped")
      expect(params[:note]).to eq("fast")
    end
  end

  describe "#permit" do
    it "returns only permitted keys" do
      params = described_class.new({ status: "shipped", note: "fast" })
      result = params.permit(:status)
      expect(result).to eq("status" => "shipped")
    end

    it "handles nested hash params" do
      params = described_class.new({ items: [{ product_id: "p1", quantity: 2, evil: "x" }] })
      result = params.permit(items: [:product_id, :quantity])
      expect(result["items"].first.keys).to contain_exactly("product_id", "quantity")
    end
  end

  describe "#require" do
    it "returns value when present" do
      params = described_class.new({ status: "shipped" })
      expect(params.require(:status)).to eq("shipped")
    end

    it "raises when missing" do
      params = described_class.new({})
      expect { params.require(:status) }.to raise_error(Toolchest::ParameterMissing)
    end
  end

  describe "#slice" do
    it "returns subset" do
      params = described_class.new({ a: 1, b: 2, c: 3 })
      expect(params.slice(:a, :b)).to eq("a" => 1, "b" => 2)
    end
  end
end
