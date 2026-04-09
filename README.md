# Toolchest

> **Research preview** — APIs may change, some features aren't great yet, and it is not yet recommended for production use (i'm still gonna though!). Feedback and bug reports are welcome.

 Every Ruby MCP library I could find is Ruby from an MCP perspective. Toolchest is MCP from a Rails perspective.

 Toolboxes are controllers, tools are actions.

## Why

Every Ruby MCP gem I found treats tools as isolated service objects. One file per tool, set_model reimplemented in every `call` method, a whole DSL that exists nowhere else in your app. Four tools for orders means four files.

A tool call *is* a controller action. Authenticated request, named action, structured params, do the thing, return JSON. Rails figured this out twenty years ago.

Toolboxes are controllers. Tools are actions. `before_action` works. `rescue_from` works. Views are views.

## Quick start

```bash
bundle add toolchest jb
rails g toolchest:install --auth=none
rails g toolchest Orders show create
rails s
# point your MCP client at http://localhost:3000/mcp
```

## Toolboxes

`app/toolboxes/`. They work like controllers because they basically are.

```ruby
# app/toolboxes/application_toolbox.rb
class ApplicationToolbox < Toolchest::Toolbox
  def current_user = auth&.resource_owner

  rescue_from ActiveRecord::RecordNotFound do |e|
    render_error "Couldn't find that #{e.model.downcase}"
  end
end
```

This is your ApplicationController. `auth` returns a `Toolchest::AuthContext` with `.resource_owner` (whatever your `authenticate` block returns), `.scopes` (always from the token), and `.token` (the raw record). Define `current_user` as a convenience, add shared error handling, include your gems.

```ruby
# app/toolboxes/orders_toolbox.rb
class OrdersToolbox < ApplicationToolbox
  default_param :order_id, :string, "The order ID", except: [:create, :search]
  before_action :set_order, except: [:create, :search]

  tool "Look up an order by ID" do
  end
  def show
    # implicit render: app/views/toolboxes/orders/show.json.jb
  end

  tool "Update order status" do
    param :status, :string, "New status", enum: %w[pending confirmed shipped]
    param :tracking, :string, "Tracking number", optional: true
  end
  def update
    if @order.update(params.permit(:status, :tracking).to_h)
      render :show
    else
      render_errors @order
    end
  end

  tool "Create a new order" do
    param :customer_id, :string, "Customer"
    param :items, [:object], "Line items" do
      param :product_id, :string, "Product SKU"
      param :quantity, :integer, "How many", default: 1
    end
  end
  def create
    @order = Order.new(params.permit(:customer_id).to_h)
    if @order.save
      render :show
      suggests :show, "Get the full order details"
    else
      render_errors @order
    end
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end
end
```

### halt

Stop execution early, usually in a `before_action`:

```ruby
before_action :require_admin!

def require_admin!
  halt error: "forbidden" unless current_user.admin?
end
```

### Rendering

```ruby
render :show                    # app/views/toolboxes/{toolbox}/show.json.jb
render "shared/status"          # explicit template path
render json: { ok: true }       # inline, no view file
render text: "done"             # plain text
# no render call = implicit render of current action name
render_error "Something broke"  # MCP error (isError: true), string
render_errors @order            # MCP error from ActiveModel errors
```

### Views

`app/views/toolboxes/`, using [jb](https://github.com/amatsuda/jb) or jbuilder:

```ruby
# app/views/toolboxes/orders/show.json.jb
{
  id: @order.id,
  status: @order.status,
  customer: @order.customer.name,
  total: @order.total.to_f
}
```

`render :show` after mutations. Most toolboxes need one or two views.

### Resources and prompts

Supported, though most toolboxes won't need them.

```ruby
class OrdersToolbox < ApplicationToolbox
  resource "orders://schema", name: "Order schema", description: "Order field structure" do
    { fields: Order.column_names, statuses: Order::STATUSES }
  end

  resource "orders://{order_id}", name: "Order details", description: "Full order by ID" do |order_id:|
    Order.find(order_id).as_json(include: :items)
  end

  prompt "debug-order", description: "Investigate order issues",
    arguments: { order_id: { type: :string, required: true } } do |order_id:|
    order = Order.find(order_id)
    [{ role: "user", content: "Debug this order:\n#{order.to_json}" }]
  end
end
```

### Suggests

Tell the LLM what to call next:

```ruby
suggests :show, "Call orders_show for full details"
```

### Params

Like `ActionController::Parameters`:

```ruby
params[:order_id]
params.require(:order_id)        # raises Toolchest::ParameterMissing if absent
params.permit(:status, :tracking)
params.slice(:status)
params.except(:internal_field)
```

Params are automatically filtered to only keys declared in the tool's `param` block. Undeclared keys get dropped.

### Sampling

Ask the client's LLM to do work from inside a tool action:

```ruby
tool "Summarize an order" do
  param :order_id, :string, "Order ID"
end
def summarize
  @order = Order.find(params[:order_id])
  summary = mcp_sample("Summarize this order for a support agent", context: @order.to_json)
  render text: summary
end
```

Block form for more control:

```ruby
summary = mcp_sample do |s|
  s.system "You are a support analyst"
  s.user "Analyze this order:\n#{@order.to_json}"
  s.max_tokens 500
  s.temperature 0.3
end
```

Raises `Toolchest::Error` if the client doesn't support sampling. Handle it with `rescue_from` in your toolbox.

### Progress

Report progress during long-running actions. Clients that support it show a progress bar:

```ruby
tool "Import customers" do
  param :file_url, :string, "CSV URL"
end
def import
  rows = CSV.parse(download(params[:file_url]))
  rows.each_with_index do |row, i|
    Customer.create!(row.to_h)
    mcp_progress i + 1, total: rows.size, message: "Importing #{row[:name]}"
  end
  render text: "Imported #{rows.size} customers"
end
```

No-op if the client doesn't send a progress token.

### Annotations

Tool annotations tell the client about a tool's behavior. They're derived automatically from `access:`:

```ruby
tool "Show order", access: :read do    # → readOnlyHint: true, destructiveHint: false
end

tool "Delete order", access: :write do  # → readOnlyHint: false, destructiveHint: true
end
```

Override or add hints with `annotations:`:

```ruby
tool "Export data", access: :read, annotations: { openWorldHint: true } do
end
```

### Logging

```ruby
mcp_log :info, "Processing order #{@order.id}"
```

### Completion

If a param has `enum:`, those values automatically power MCP's `completion/complete`. Clients that support autocomplete get it for free.

### Server instructions

Tell the LLM how to use your tools:

```ruby
Toolchest.configure do |config|
  config.server_instructions = "You are a support agent. Always look up the customer before modifying orders."
end
```

This shows up in the MCP initialize response. `server_name` and `server_description` are also available.

## Auth

Three built-in strategies, or bring your own. Default is `:none`.

### :token

Bearer tokens. In dev, set env vars and you're done:

```bash
TOOLCHEST_TOKEN=tcht_dev_secret
TOOLCHEST_TOKEN_OWNER=user:1
TOOLCHEST_TOKEN_SCOPES="orders:read orders:write"  # optional
```

For production, run the migration and manage with rake:

```bash
rails g toolchest:auth token
rails db:migrate
rails toolchest:token:generate OWNER=user:1 NAME="claude desktop"
rails toolchest:token:list
rails toolchest:token:revoke TOKEN=tcht_...
```

```ruby
Toolchest.configure do |config|
  config.auth = :token

  config.authenticate do |token|
    User.find(token.owner_id)
  end
end
```

`authenticate` resolves the token to a user (or anything). The return value becomes `auth.resource_owner` in your toolboxes. Scopes are preserved from the token automatically — you can't lose them here.

### :oauth

MCP clients like Claude Desktop and Cursor need OAuth 2.1 with PKCE and Dynamic Client Registration. Toolchest ships a built-in OAuth provider so you can get this working without wiring up Doorkeeper.

It's intentionally minimal — enough to make MCP auth work, completely isolated from the rest of your app. Its tables are all `toolchest_`-prefixed, it doesn't know Doorkeeper exists. It will not break your existing OAuth setup.

If you already have an OAuth provider, you probably want `:token` instead and validate your own tokens in the `authenticate` block. The built-in provider exists so you don't have to figure all that out before you can connect Claude Desktop.

```bash
rails g toolchest:install --auth=oauth
rails db:migrate
```

```ruby
Toolchest.configure do |config|
  config.auth = :oauth
  config.login_path = "/login"

  config.current_user_for_oauth do |request|
    # return the logged-in user for the consent screen, or nil to redirect
    request.env["warden"]&.user  # devise example
  end

  config.authenticate do |token|
    User.find(token.resource_owner_id)
  end
end
```

`authenticate` resolves the token to `auth.resource_owner`. Scopes come from the token and are never lost, even if you return a plain User.

You also need `toolchest_oauth` in your routes for `.well-known` discovery:

```ruby
# config/routes.rb
mount Toolchest.app => "/mcp"
toolchest_oauth
```

This adds the endpoints MCP clients expect:

```
/.well-known/oauth-authorization-server   ← discovery (app root)
/.well-known/oauth-protected-resource     ← discovery (app root)
/mcp/oauth/authorize                      ← consent screen
/mcp/oauth/token                          ← token exchange
/mcp/oauth/register                       ← dynamic client registration
```

Customize the consent view: `rails g toolchest:consent`

There's a built-in "connected applications" page at `/mcp/oauth/authorized_applications` where users can revoke access. Link to it from your account settings.

You can also query tokens directly:

```ruby
Toolchest::OauthAccessToken.revoke_all_for(app, user.id)
Toolchest::OauthAccessGrant.revoke_all_for(app, user.id)
app.destroy  # cascades to all grants and tokens
```

### Custom

If the built-in strategies don't fit, pass any object that responds to `#authenticate(request)`:

```ruby
Toolchest.configure do |config|
  config.auth = WardenAuth.new
end
```

```ruby
class WardenAuth
  def authenticate(request)
    user = request.env["warden"]&.user
    return nil unless user
    Toolchest::AuthContext.new(resource_owner: user, scopes: [], token: nil)
  end
end
```

Custom strategies return an `AuthContext` (or nil for unauthenticated). If you return something else, `auth` will be that object directly — but scope filtering only works with `AuthContext`.

You can inherit from `Toolchest::Auth::Base` to get `extract_bearer_token` for free:

```ruby
class ApiKeyAuth < Toolchest::Auth::Base
  def authenticate(request)
    key = request.env["HTTP_X_API_KEY"]
    ApiKey.active.find_by(key: key)&.owner
  end
end
```

## Scopes

Scopes work with both `:token` and `:oauth` auth. Define them in your config:

```ruby
config.scopes = {
  "orders:read"  => "View order details",
  "orders:write" => "Create and modify orders",
  "users:read"   => "View user profiles"
}
```

The pattern is `{toolbox}:{access}`. Toolchest maps tools to scopes automatically: actions named `show`, `index`, `list`, or `search` are `:read`, everything else is `:write`. A client granted `orders:read` sees `orders_show` and `orders_search` but not `orders_cancel`. `orders:write` gets everything. `orders` with no suffix also gets everything.

With OAuth, scopes show up on the consent screen and filter `tools/list` by what was granted. With token auth, set scopes via `TOOLCHEST_TOKEN_SCOPES` (env var) or the `scopes` column on the token record.

Override when the convention is wrong:

```ruby
tool "Export data", access: :read do
end
def export
  # ...
end
```

Turn it off: `config.filter_tools_by_scope = false`

### Optional scopes (checkboxes)

By default, the consent screen is all-or-nothing — approve all requested scopes or deny. Enable `optional_scopes` and users get checkboxes:

```ruby
config.optional_scopes = true
```

All scopes start checked. Users uncheck what they don't want. The token only gets the scopes the user approved. That's it — no other config needed.

Layer on more control when you need it:

```ruby
# These scopes are always granted (checked + disabled on the consent screen)
config.required_scopes = ["orders:read"]

# Per-user gating — hide scopes from users who shouldn't grant them
config.allowed_scopes_for do |user, requested_scopes|
  user.admin? ? requested_scopes : requested_scopes - ["admin:write"]
end
```

Scopes hidden by `allowed_scopes_for` never appear on the consent screen and can't be granted even if the POST is tampered with.

## Multi-mount

Separate MCP endpoints, different auth, different toolboxes:

```ruby
Toolchest.configure do |config|
  config.auth = :oauth
  config.toolbox_module = "Public"
end

Toolchest.configure(:admin) do |config|
  config.auth = :token
  config.toolbox_module = "Admin"
end
```

```ruby
# config/routes.rb
mount Toolchest.app => "/mcp"
mount Toolchest.app(:admin) => "/admin-mcp"
toolchest_oauth
```

Namespace your toolboxes under modules (`Admin::OrdersToolbox`, `Public::OrdersToolbox`) and they route to the right mount.

With multiple OAuth mounts, `.well-known` discovery uses the path suffix per [RFC 8414](https://datatracker.ietf.org/doc/html/rfc8414) — e.g. `/.well-known/oauth-authorization-server/admin-mcp`. Some clients (notably Cursor) hit the bare path without a suffix. Set `default_mount` so Toolchest knows which mount to use:

```ruby
toolchest_oauth default_mount: :default
```

With a single OAuth mount this isn't needed.

## Tool naming

```ruby
config.tool_naming = :underscored  # orders_show (default)
config.tool_naming = :dotted       # orders.show
config.tool_naming = :slashed      # orders/show
config.tool_naming = ->(prefix, method) { "#{prefix}__#{method}" }
```

Per-tool: `tool "description", name: "custom_name"`

## Generators

```bash
rails g toolchest:install             # initializer, app toolbox, routes
rails g toolchest Orders show create  # toolbox + views + spec
rails g toolchest Admin::Orders show  # namespaced
rails g toolchest:auth oauth          # add auth migration + views
rails g toolchest:consent             # eject consent view
rails g toolchest:oauth_views         # eject all OAuth views + controllers
```

## Introspection

```bash
rails toolchest:tools
```

## Testing

```ruby
RSpec.describe OrdersToolbox, type: :toolbox do
  it "shows an order" do
    call_tool "orders_show", params: { order_id: "123" }, as: user
    expect(tool_response).to be_success
    expect(tool_response.text).to include("shipped")
  end

  it "returns errors for invalid updates" do
    call_tool "orders_update", params: { order_id: "123", status: "pending" }, as: user
    expect(tool_response).to be_error
  end

  it "suggests next tool after create" do
    call_tool "orders_create", params: { customer_id: "c1" }, as: user
    expect(tool_response).to suggest("orders_show")
  end
end
```

`require "toolchest/rspec"` in your `rails_helper.rb`.

## Security notes

- **Rate limiting**: Toolchest doesn't include rate limiting. Use [rack-attack](https://github.com/rack/rack-attack) or your reverse proxy to protect token and registration endpoints.
- **HTTPS**: OAuth endpoints should always run behind TLS in production.

## Internals

Transport is the [MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk) (`mcp` gem).

OAuth provider is cribbed from [Doorkeeper](https://github.com/doorkeeper-gem/doorkeeper). Same table layout, same controller shapes. Not a dependency, just stole the design.

## For agents

If you're implementing this with an agent (or you're the agent reading this), consider the contents of [LLMS.txt](LLMS.txt).

## Requirements

- Ruby >= 3.2
- Rails >= 7.0
- [jb](https://github.com/amatsuda/jb) (recommended) or jbuilder

## Disclaimer

This is slop by LLMs for LLMs and only a fool would use it in production. However, I am a fool.
No implied warranty of any kind, if you trust this and it explodes you please cry to someone else.

## License

MIT
