# frozen_string_literal: true

require "json"

module Pathly
  # Error returned by the Pathly API or the transport layer.
  class APIError < StandardError
    attr_reader :status_code, :message, :path

    def initialize(status_code, message, path = "")
      @status_code = status_code
      @message = message
      @path = path
      super(to_s)
    end

    def to_s
      if path && !path.empty?
        "#{path}: #{message} (HTTP #{status_code})"
      else
        "#{message} (HTTP #{status_code})"
      end
    end

    def not_found?
      status_code == 404
    end
  end

  # Resource missing from the authenticated organization.
  class NotFoundError < APIError
    def initialize(message, path = "")
      super(404, message, path)
    end
  end

  module_function

  # True when +err+ reports a missing resource (HTTP 404).
  def not_found?(err)
    err.is_a?(APIError) && err.not_found?
  end

  # Build an APIError from a raw response body.
  def parse_api_error(status, path, body)
    text = body.to_s.dup.force_encoding("UTF-8").scrub.strip
    message = text.empty? ? status_phrase(status) : text
    parsed = {}
    begin
      parsed = JSON.parse(text) unless text.empty?
    rescue JSON::ParserError
      parsed = {}
    end

    if parsed.is_a?(Hash) && parsed["error"]
      message = parsed["error"].to_s
      details = parsed["details"] || []
      if details.is_a?(Array)
        details.each do |detail|
          next unless detail.is_a?(Hash)

          field = field_of(detail["path"] || [])
          detail_msg = detail["message"] || ""
          message += " [#{field}: #{detail_msg}]"
        end
      end
    end

    case status
    when 401
      message +=
        " Check PATHLY_API_TOKEN: an expired, revoked or truncated key " \
        "gives the same response."
    when 403
      message +=
        " Widen the scopes of the key, or check that the plan includes " \
        "the feature."
    end

    return NotFoundError.new(message, path) if status == 404

    APIError.new(status, message, path)
  end

  # Render a validation path as +events.0+, or +body+ when empty.
  def field_of(path)
    parts = []
    Array(path).each do |item|
      case item
      when String
        parts << item
      when Numeric
        parts << item.to_i.to_s
      end
    end
    parts.empty? ? "body" : parts.join(".")
  end

  def status_phrase(status)
    {
      400 => "Bad Request",
      401 => "Unauthorized",
      403 => "Forbidden",
      404 => "Not Found",
      418 => "I'm a teapot",
      422 => "Unprocessable Entity",
      429 => "Too Many Requests",
      500 => "Internal Server Error",
      503 => "Service Unavailable"
    }.fetch(status, "HTTP #{status}")
  end
  private_class_method :status_phrase
end
