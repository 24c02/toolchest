Rails.application.routes.draw do
  mount Toolchest.app => "/mcp"
  toolchest_oauth
end
