require_relative "../rails_helper"
require "generators/toolchest/install_generator"

RSpec.describe Toolchest::Generators::InstallGenerator do
  include FileUtils

  let(:destination) { Dir.mktmpdir("toolchest_gen_test") }

  before do
    # route helper needs config/routes.rb to exist
    mkdir_p(File.join(destination, "config"))
    File.write(File.join(destination, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
    described_class.start(args, destination_root: destination)
  end

  after { rm_rf(destination) }

  context "with --auth=none" do
    let(:args) { ["--auth=none"] }

    it "creates application_toolbox.rb" do
      path = File.join(destination, "app/toolboxes/application_toolbox.rb")
      expect(File.exist?(path)).to be true
      expect(File.read(path)).to include("class ApplicationToolbox < Toolchest::Toolbox")
    end

    it "creates initializer" do
      path = File.join(destination, "config/initializers/toolchest.rb")
      expect(File.exist?(path)).to be true
      content = File.read(path)
      expect(content).to include("config.auth = :none")
    end

    it "creates toolboxes view directory" do
      expect(Dir.exist?(File.join(destination, "app/views/toolboxes"))).to be true
    end

    it "does not create migrations" do
      expect(Dir.glob(File.join(destination, "db/migrate/*.rb"))).to be_empty
    end

    it "mounts the engine in routes" do
      content = File.read(File.join(destination, "config/routes.rb"))
      expect(content).to include('mount Toolchest::Engine => "/mcp"')
    end
  end

  context "with --auth=token" do
    let(:args) { ["--auth=token"] }

    it "creates token migration" do
      migrations = Dir.glob(File.join(destination, "db/migrate/*create_toolchest_tokens.rb"))
      expect(migrations.size).to eq(1)
      expect(File.read(migrations.first)).to include("toolchest_tokens")
    end

    it "sets auth to :token in initializer" do
      content = File.read(File.join(destination, "config/initializers/toolchest.rb"))
      expect(content).to include("config.auth = :token")
      expect(content).to include("config.authenticate")
    end
  end

  context "with --auth=oauth" do
    let(:args) { ["--auth=oauth"] }

    it "creates OAuth migration" do
      migrations = Dir.glob(File.join(destination, "db/migrate/*create_toolchest_oauth.rb"))
      expect(migrations.size).to eq(1)
      content = File.read(migrations.first)
      expect(content).to include("toolchest_oauth_applications")
      expect(content).to include("toolchest_oauth_access_tokens")
      expect(content).to include("toolchest_oauth_access_grants")
    end

    it "creates OAuth consent view" do
      path = File.join(destination, "app/views/toolchest/oauth/authorizations/new.html.erb")
      expect(File.exist?(path)).to be true
    end

    it "sets auth to :oauth in initializer" do
      content = File.read(File.join(destination, "config/initializers/toolchest.rb"))
      expect(content).to include("config.auth = :oauth")
      expect(content).to include("current_user_for_oauth")
    end
  end
end
