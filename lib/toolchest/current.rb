require "active_support/current_attributes"

module Toolchest
  class Current < ActiveSupport::CurrentAttributes
    attribute :auth, :mount_key, :mcp_session, :mcp_request_id, :mcp_progress_token
  end
end
