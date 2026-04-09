module Toolchest
  class SamplingBuilder
    attr_reader :messages, :system_value, :max_tokens_value, :temperature_value,
                :model_preferences_value, :stop_sequences_value

    def initialize
      @messages = []
    end

    def system(text)
      @system_value = text
    end

    def user(text)
      @messages << { role: "user", content: { type: "text", text: text } }
    end

    def assistant(text)
      @messages << { role: "assistant", content: { type: "text", text: text } }
    end

    def max_tokens(n)
      @max_tokens_value = n
    end

    def temperature(t)
      @temperature_value = t
    end

    def model_preferences(prefs)
      @model_preferences_value = prefs
    end

    def stop_sequences(seqs)
      @stop_sequences_value = seqs
    end
  end
end
