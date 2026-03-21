class ApplicationController < ActionController::Base
  prepend_view_path File.expand_path("../../../../app/views", __dir__)
end
