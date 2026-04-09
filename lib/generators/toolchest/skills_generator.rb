require "rails/generators"
require "rails/generators/base"

module Toolchest
  module Generators
    class SkillsGenerator < Rails::Generators::Base
      def create_skills
        create_file ".claude/skills/toolchest-add-toolbox.md", add_toolbox_skill
        create_file ".claude/skills/toolchest-add-tool.md", add_tool_skill
        create_file ".claude/skills/toolchest-auth.md", auth_skill

        say ""
        say "Claude Code skills installed!", :green
        say ""
        say "  /add-toolbox  — generate and fill in a new toolbox"
        say "  /add-tool     — add a tool to an existing toolbox"
        say "  /toolchest-auth — set up or change auth"
        say ""
      end

      private

      def add_toolbox_skill
        <<~'SKILL'
          ---
          description: Add a new toolbox to this app. Give it a model name and actions, or describe what you want.
          ---

          The user wants to add a new toolbox. A toolbox is a controller for MCP tools — it lives in `app/toolboxes/`.

          ## Steps

          1. **Determine the model and actions.** If the user says "Orders" or "add tools for orders", look at the `Order` model (columns, associations, validations, scopes) to decide which actions make sense.

          2. **Run the generator:** `rails g toolchest:toolbox <Name> <actions...>`

          3. **Fill in the toolbox** with real tool descriptions, params, and implementations. Don't leave TODOs.

          4. **Create a partial** for the primary model: `app/views/toolboxes/<name>/_<singular>.json.jb`. This is the canonical representation — every tool that returns this model should render this partial.

          5. **Fill in views** to use the partial. `show.json.jb` should just render the partial. `index.json.jb` should map a collection through the partial.

          6. **Fill in the spec** at `spec/toolboxes/<name>_toolbox_spec.rb` with real test cases.

          ## Toolbox patterns

          ```ruby
          class OrdersToolbox < ApplicationToolbox
            # default_param adds a param to every tool (except those listed)
            default_param :order_id, :string, "The order ID", except: [:create, :search]
            before_action :set_order, except: [:create, :search]

            rescue_from ActiveRecord::RecordNotFound do |e|
              render_error "Couldn't find that #{e.model.downcase}"
            end

            tool "Look up an order", access: :read do
            end
            def show; end  # implicit render of show.json.jb

            tool "Search orders", access: :read do
              param :status, :string, "Filter by status", optional: true, enum: %w[pending confirmed shipped]
              param :customer_id, :string, "Filter by customer", optional: true
            end
            def search
              @orders = Order.all
              @orders = @orders.where(status: params[:status]) if params[:status]
              @orders = @orders.where(customer_id: params[:customer_id]) if params[:customer_id]
              render :index
            end

            tool "Create an order", access: :write do
              param :customer_id, :string, "Customer"
            end
            def create
              @order = Order.create!(params.permit(:customer_id).to_h)
              render :show
              suggests :show, "View the created order"
            end

            tool "Update an order", access: :write do
              param :status, :string, "New status", enum: %w[pending confirmed shipped]
            end
            def update
              if @order.update(params.permit(:status).to_h)
                render :show
              else
                render_errors @order
              end
            end

            private
            def set_order = @order = Order.find(params[:order_id])
          end
          ```

          ## View patterns — use partials

          The partial is the single source of truth for how a record is rendered. Don't build bespoke views that manually list fields — use the partial.

          Check the Gemfile to see whether the project uses **jb** or **jbuilder**, then use the matching syntax:

          ### jb views (`.json.jb`)

          ```ruby
          # app/views/toolboxes/orders/_order.json.jb
          {
            id: order.id,
            status: order.status,
            customer: order.customer.name,
            total: order.total.to_f,
            created_at: order.created_at.iso8601
          }
          ```

          ```ruby
          # app/views/toolboxes/orders/show.json.jb
          render partial: "orders/order", locals: { order: @order }
          ```

          ```ruby
          # app/views/toolboxes/orders/index.json.jb
          @orders.map { |order| render partial: "orders/order", locals: { order: order } }
          ```

          ### jbuilder views (`.json.jbuilder`)

          ```ruby
          # app/views/toolboxes/orders/_order.json.jbuilder
          json.id order.id
          json.status order.status
          json.customer order.customer.name
          json.total order.total.to_f
          json.created_at order.created_at.iso8601
          ```

          ```ruby
          # app/views/toolboxes/orders/show.json.jbuilder
          json.partial! "orders/order", order: @order
          ```

          ```ruby
          # app/views/toolboxes/orders/index.json.jbuilder
          json.array! @orders, partial: "orders/order", as: :order
          ```

          ## Tool DSL quick reference

          ```ruby
          tool "Description", access: :read do  # or :write
            param :name, :string, "description"
            param :name, :string, "description", optional: true
            param :name, :string, "description", enum: %w[a b c]
            param :name, :integer, "description", default: 1
            param :items, [:object], "array of objects" do
              param :field, :string, "nested"
            end
          end
          ```

          Types: `:string`, `:integer`, `:number`, `:boolean`, `:object`, `[:object]`, `[:string]`

          ### access and annotations

          Always set `access:` on tools — it controls both scope filtering and client hints:
          - `access: :read` → `readOnlyHint: true, destructiveHint: false`
          - `access: :write` → `readOnlyHint: false, destructiveHint: true`

          Override with `annotations:` for edge cases:
          ```ruby
          tool "Export data", access: :read, annotations: { openWorldHint: true } do
          end
          ```

          ### default_param

          Adds a param to every tool in the toolbox. Use for the primary record ID:
          ```ruby
          default_param :order_id, :string, "The order ID", except: [:create, :search]
          ```
          `except:` and `only:` control which tools get it.

          ### progress for long-running tools

          ```ruby
          def import
            items.each_with_index do |item, i|
              process(item)
              mcp_progress i + 1, total: items.size, message: "Importing #{item.name}"
            end
            render text: "Done"
          end
          ```

          ### sampling (ask the client's LLM)

          ```ruby
          def summarize
            summary = mcp_sample("Summarize this order", context: @order.to_json)
            render text: summary
          end
          ```

          Block form: `mcp_sample { |s| s.system "..."; s.user "..."; s.max_tokens 500 }`

          Raises `Toolchest::Error` if client doesn't support sampling — handle with `rescue_from`.

          ## Testing

          ```ruby
          require "toolchest/rspec"

          RSpec.describe OrdersToolbox, type: :toolbox do
            it "shows an order" do
              order = create(:order)
              call_tool "orders_show", params: { order_id: order.id.to_s }, as: auth_context
              expect(tool_response).to be_success
            end
          end
          ```

          Matchers: `be_success`, `be_error`, `include_text("str")`, `suggest("tool_name")`
        SKILL
      end

      def add_tool_skill
        <<~'SKILL'
          ---
          description: Add a new tool (action) to an existing toolbox.
          ---

          The user wants to add a tool to an existing toolbox.

          ## Steps

          1. **Find the toolbox** in `app/toolboxes/`. Read it to understand the existing patterns — params, callbacks, error handling.

          2. **Add the tool** — a `tool` macro + `def` pair. Follow the conventions already in the file.

          3. **Add a view** if the tool renders (most do). If a partial already exists for the model, use it.

          4. **Add a test** in the existing spec file.

          ## Quick reference

          ```ruby
          tool "Description for the LLM", access: :read do
            param :query, :string, "Search query"
            param :limit, :integer, "Max results", optional: true, default: 10
          end
          def search
            @results = SomeModel.where("name LIKE ?", "%#{params[:query]}%").limit(params[:limit])
            render :index
          end
          ```

          Always set `access: :read` or `access: :write` on tools.

          Instance methods available:

          ```
          auth.resource_owner     # the user (from authenticate block)
          auth.scopes             # token scopes
          params                  # declared params only
          render :action          # render a view
          render json: { ... }    # inline
          render text: "..."      # plain text
          render_error "msg"      # MCP error
          render_errors @record   # from ActiveModel errors
          suggests :action, "hint"
          mcp_log :info, "msg"
          mcp_sample "prompt"     # ask client's LLM
          mcp_progress n, total: t, message: "..."
          halt error: "forbidden"
          ```

          Options on `tool`:
          - `access: :read` / `:write` — scope filtering + annotations
          - `name: "custom_name"` — override generated tool name
          - `annotations: { openWorldHint: true }` — override hints

          For long-running tools, use `mcp_progress`. For tools that need LLM help, use `mcp_sample`.
        SKILL
      end

      def auth_skill
        <<~'SKILL'
          ---
          description: Set up or change toolchest auth strategy (none, token, oauth).
          ---

          The user wants to configure or change auth for their toolchest MCP endpoint.

          ## Auth strategies

          ### :none
          No auth. `auth` is nil in toolboxes. Good for local dev.

          ### :token
          Bearer tokens. Simplest real auth.

          ```ruby
          # config/initializers/toolchest.rb
          config.auth = :token
          config.authenticate do |token|
            User.find(token.owner_id)  # becomes auth.resource_owner
          end
          ```

          Dev setup (no DB): set `TOOLCHEST_TOKEN`, `TOOLCHEST_TOKEN_OWNER`, `TOOLCHEST_TOKEN_SCOPES` env vars.

          Production: `rails g toolchest:auth token && rails db:migrate`, then `rails toolchest:token:generate OWNER=user:1`.

          ### :oauth
          Full OAuth 2.1 + PKCE + DCR. For Claude Desktop, Cursor, etc.

          ```ruby
          config.auth = :oauth
          config.login_path = "/login"
          config.current_user_for_oauth do |request|
            request.env["warden"]&.user  # or session lookup
          end
          config.authenticate do |token|
            User.find(token.resource_owner_id)
          end
          ```

          Needs: `rails g toolchest:auth oauth && rails db:migrate`

          Routes: `mount Toolchest.app => "/mcp"` + `toolchest_oauth`

          ### Scopes

          ```ruby
          config.scopes = {
            "orders:read"  => "View orders",
            "orders:write" => "Modify orders"
          }
          # Optional: checkboxes on consent
          config.optional_scopes = true
          config.required_scopes = ["orders:read"]
          ```

          ## AuthContext

          `auth` returns `Toolchest::AuthContext`:
          - `auth.resource_owner` — whatever authenticate block returns
          - `auth.scopes` — from the token, never lost
          - `auth.token` — raw token record

          The generator creates `def current_user = auth&.resource_owner` in ApplicationToolbox.
        SKILL
      end
    end
  end
end
