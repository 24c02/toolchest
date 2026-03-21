require "active_support/hash_with_indifferent_access"

module Toolchest
  class Parameters
    def initialize(raw = {}, tool_definition: nil)
      @raw = raw.is_a?(Hash) ? raw : {}

      if tool_definition
        allowed_keys = tool_definition.params.map { |p| p.name.to_s }
        filtered = @raw.select { |k, _| allowed_keys.include?(k.to_s) }
        @params = ActiveSupport::HashWithIndifferentAccess.new(filtered)
      else
        @params = ActiveSupport::HashWithIndifferentAccess.new(@raw)
      end
    end

    def [](key)
      @params[key]
    end

    def fetch(key, *args, &block) = @params.fetch(key, *args, &block)

    def key?(key) = @params.key?(key)
    alias_method :has_key?, :key?
    alias_method :include?, :key?

    def to_h = @params.to_h
    alias_method :to_hash, :to_h

    def slice(*keys) = @params.slice(*keys.map(&:to_s))

    def except(*keys) = @params.except(*keys.map(&:to_s))

    def require(key)
      value = @params[key]
      if value.nil? && !@params.key?(key.to_s)
        raise Toolchest::ParameterMissing, "param is missing or the value is empty: #{key}"
      end
      value
    end

    def permit(*keys)
      permitted = {}
      keys.each do |key|
        case key
        when Symbol, String
          permitted[key.to_s] = @params[key] if @params.key?(key.to_s)
        when Hash
          key.each do |k, v|
            if @params.key?(k.to_s) && @params[k].is_a?(Array)
              permitted[k.to_s] = @params[k].map do |item|
                item.is_a?(Hash) ? item.slice(*v.map(&:to_s)) : item
              end
            elsif @params.key?(k.to_s) && @params[k].is_a?(Hash)
              permitted[k.to_s] = @params[k].slice(*v.map(&:to_s))
            end
          end
        end
      end
      ActiveSupport::HashWithIndifferentAccess.new(permitted)
    end

    def empty? = @params.empty?

    def each(&block) = @params.each(&block)

    def merge(other) = self.class.new(@params.merge(other))

    def inspect = "#<Toolchest::Parameters #{@params.inspect}>"
  end
end
