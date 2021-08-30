module RBSJsonSchema
  class ValidationError < StandardError
    attr_reader :message

    def initialize(message:)
      @message = message

      super message
    end
  end
end
