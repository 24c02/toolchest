namespace :toolchest do
  desc "List all registered MCP tools"
  task tools: :environment do
    Toolchest::Engine.ensure_initialized!
    router = Toolchest.router

    router.toolbox_classes.each do |klass|
      tools = klass.tool_definitions.values
      resources = klass.resources
      prompts = klass.prompts

      parts = []
      parts << "#{tools.length} tool#{"s" unless tools.length == 1}"
      parts << "#{resources.length} resource#{"s" unless resources.length == 1}" if resources.any?
      parts << "#{prompts.length} prompt#{"s" unless prompts.length == 1}" if prompts.any?

      puts "#{klass.name} (#{parts.join(", ")})"

      tools.each do |tool|
        puts "  #{tool.tool_name.ljust(25)} #{tool.description.inspect}"

        required = tool.params.select(&:required?)
        optional = tool.params.reject(&:required?)

        if required.any?
          params_str = required.map { |p|
            s = "#{p.name} (#{p.type})"
            s += " [#{p.enum.join("|")}]" if p.enum
            s
          }.join(", ")
          puts "    Params: #{params_str}"
        end

        if optional.any?
          optional.each do |p|
            s = "#{p.name} (#{p.type}, optional)"
            s += " [#{p.enum.join("|")}]" if p.enum
            puts "            #{s}"
          end
        end
      end

      resources.each do |r|
        puts "  Resource: #{r[:uri]} #{r[:name].inspect}"
      end

      prompts.each do |p|
        puts "  Prompt:   #{p[:name]} #{p[:description].inspect}"
      end

      puts
    end

    if router.toolbox_classes.empty?
      puts "No toolboxes registered."
      puts "Generate one: rails g toolchest YourModel show create"
    end
  end

  namespace :token do
    desc "Generate a new API token"
    task generate: :environment do
      owner = ENV["OWNER"]
      name = ENV["NAME"] || "cli-generated"
      scopes = ENV["SCOPES"]

      if defined?(Toolchest::Token) && Toolchest::Token.table_exists?
        record = Toolchest::Token.generate(owner: owner, name: name, scopes: scopes)
        puts "Token created: #{record.raw_token}"
        puts "  Owner: #{owner}" if owner
        puts "  Name:  #{name}"
        puts "  Scopes: #{scopes}" if scopes
      else
        token = "tcht_#{SecureRandom.hex(24)}"
        puts "Token: #{token}"
        puts ""
        puts "No toolchest_tokens table found. Use as env var:"
        puts "  TOOLCHEST_TOKEN=#{token}"
        puts "  TOOLCHEST_TOKEN_OWNER=#{owner}" if owner
      end
    end

    desc "List all tokens"
    task list: :environment do
      unless defined?(Toolchest::Token) && Toolchest::Token.table_exists?
        if ENV["TOOLCHEST_TOKEN"]
          puts "Env token configured: TOOLCHEST_TOKEN=#{ENV["TOOLCHEST_TOKEN"][0..8]}..."
          puts "  Owner: #{ENV["TOOLCHEST_TOKEN_OWNER"]}" if ENV["TOOLCHEST_TOKEN_OWNER"]
        else
          puts "No tokens configured."
        end
        next
      end

      tokens = Toolchest::Token.where(revoked_at: nil).order(:created_at)
      if tokens.empty?
        puts "No active tokens."
      else
        tokens.each do |t|
          puts "#{t.token_digest[0..8]}...  #{t.name || "(unnamed)"}  owner=#{t.owner_type}:#{t.owner_id}  created=#{t.created_at.to_date}"
          puts "  scopes=#{t.scopes}" if t.scopes.present?
          puts "  last_used=#{t.last_used_at}" if t.last_used_at
        end
      end
    end

    desc "Revoke a token"
    task revoke: :environment do
      token = ENV["TOKEN"]
      abort "Usage: rails toolchest:token:revoke TOKEN=tcht_..." unless token

      unless defined?(Toolchest::Token) && Toolchest::Token.table_exists?
        abort "No toolchest_tokens table. Can't revoke env tokens — just unset TOOLCHEST_TOKEN."
      end

      record = Toolchest::Token.find_by_raw_token(token)
      abort "Token not found." unless record

      record.revoke!
      puts "Token revoked: #{record.name || record.token_digest[0..8]}..."
    end
  end
end
