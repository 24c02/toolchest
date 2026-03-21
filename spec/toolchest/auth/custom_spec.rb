require "spec_helper"

RSpec.describe "Custom auth strategy" do
  let(:custom_strategy) do
    Class.new(Toolchest::Auth::Base) do
      def authenticate(request)
        request.env["app.current_user"]
      end
    end.new
  end

  it "authenticates via a custom object" do
    request = Struct.new(:env).new({"app.current_user" => "nora"})
    expect(custom_strategy.authenticate(request)).to eq("nora")
  end

  it "returns nil when env key is missing" do
    request = Struct.new(:env).new({})
    expect(custom_strategy.authenticate(request)).to be_nil
  end

  it "can use extract_bearer_token from Base" do
    strategy = Class.new(Toolchest::Auth::Base) do
      def authenticate(request)
        token = extract_bearer_token(request)
        token&.reverse
      end
    end.new

    request = Struct.new(:env).new({"HTTP_AUTHORIZATION" => "Bearer abc123"})
    expect(strategy.authenticate(request)).to eq("321cba")
  end

  it "works without inheriting from Base" do
    strategy = Class.new do
      def authenticate(request)
        request.env["X_API_KEY"] == "secret" ? :authorized : nil
      end
    end.new

    Toolchest.configure { |c| c.auth = strategy }
    expect(Toolchest.configuration.auth).to eq(strategy)
  end
end
