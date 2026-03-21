require "spec_helper"

RSpec.describe "Request logging" do
  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "LoggingToolbox"

      tool "Do a thing" do
        param :id, :string, "ID"
      end
      def action = render_error "done"
    end
  end

  let(:router) { Toolchest.router }
  let(:logger) { instance_double("Logger", info: nil) }

  before do
    router.register(toolbox_class)
    # Inject a logger
    router.instance_variable_set(:@logger, logger)
  end

  it "logs tool dispatch with toolbox name and action" do
    router.dispatch("logging_action", { id: "42" })

    expect(logger).to have_received(:info).with(/LoggingToolbox#action/)
    expect(logger).to have_received(:info).with(/Parameters:.*id/)
    expect(logger).to have_received(:info).with(/Completed.*in.*ms/)
  end

  it "logs error status for error responses" do
    router.dispatch("logging_action", { id: "42" })

    expect(logger).to have_received(:info).with(/Completed Error/)
  end
end
