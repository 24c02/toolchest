Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.active_support.deprecation = :stderr
  config.action_dispatch.show_exceptions = :none
  config.action_controller.allow_forgery_protection = false
end
