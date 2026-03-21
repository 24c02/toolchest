require "active_support/current_attributes"

module Toolchest
  class Current < ActiveSupport::CurrentAttributes
    attribute :auth, :mount_key
  end
end
