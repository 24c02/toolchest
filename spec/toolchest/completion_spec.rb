require "spec_helper"

RSpec.describe "Completion" do
  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "StatusToolbox"

      tool "Update status" do
        param :status, :string, "Status", enum: %w[pending confirmed shipped delivered]
        param :note, :string, "Note", optional: true
      end
      def update = render_error "stub"
    end
  end

  let(:router) { Toolchest.router }

  before { router.register(toolbox_class) }

  describe "Router#completion_values" do
    it "returns enum values for a param name" do
      values = router.completion_values(:status)
      expect(values).to eq(%w[pending confirmed shipped delivered])
    end

    it "returns empty for params without enums" do
      values = router.completion_values(:note)
      expect(values).to be_empty
    end

    it "returns empty for unknown params" do
      values = router.completion_values(:nonexistent)
      expect(values).to be_empty
    end
  end
end
