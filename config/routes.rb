Toolchest::Engine.routes.draw do
  # OAuth endpoints (within engine mount)
  get    "oauth/authorize", to: "oauth/authorizations#new"
  post   "oauth/authorize", to: "oauth/authorizations#create"
  delete "oauth/authorize", to: "oauth/authorizations#deny"
  post "oauth/token",     to: "oauth/tokens#create"
  post "oauth/register",  to: "oauth/registrations#create"

  # User-facing management UI
  resources :oauth_authorized_applications, only: [:index, :destroy],
    path: "oauth/authorized_applications",
    controller: "oauth/authorized_applications"

  # MCP protocol endpoint (catch-all)
  endpoint = Toolchest::Endpoint.new
  match "/", to: endpoint, via: [:get, :post, :delete]
  match "/*path", to: endpoint, via: [:get, :post, :delete]
end
