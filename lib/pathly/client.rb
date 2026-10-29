# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"

require_relative "errors"
require_relative "version"

module Pathly
  DEFAULT_BASE_URL = "https://api.pathlyhq.com"
  MAX_ATTEMPTS = 4
  MAX_RETRY_WAIT = 90.0
  PAGE_SIZE = 200
  MAX_PAGES = 200

  # Thread-safe HTTP client for the Pathly public +/v1+ API.
  # The token is never logged.
  class Client
    attr_reader :base_url, :timeout, :user_agent

    DEFAULT_SLEEP = ->(seconds) { Kernel.sleep(seconds) }

    def initialize(
      token: nil,
      base_url: nil,
      timeout: 30.0,
      user_agent: "pathly-sdk-ruby/#{Pathly::VERSION}",
      sleep: DEFAULT_SLEEP,
      http_request: nil
    )
      resolved = (token.nil? ? ENV.fetch("PATHLY_API_TOKEN", "") : token).to_s.strip
      if resolved.empty?
        raise ArgumentError,
              "PATHLY_API_TOKEN is required. Export it, or pass token: to Client.new."
      end

      url = (base_url.nil? ? ENV.fetch("PATHLY_API_URL", "") : base_url).to_s.strip
      url = DEFAULT_BASE_URL if url.empty?

      @base_url = url.sub(%r{/\z}, "")
      @token = resolved
      @timeout = timeout
      @user_agent = user_agent
      @sleep = sleep
      @http_request = http_request || method(:default_http_request)
    end

    # Perform an HTTP request with retries for 429 / 5xx / transport errors.
    def request(method, path, body: nil, idempotency_key: nil, expect_json: true)
      payload = body.nil? ? nil : JSON.generate(body)
      last_error = nil

      (1...MAX_ATTEMPTS).each do |attempt|
        wait, result, err = attempt_request(
          method, path, payload, idempotency_key, expect_json, attempt, last: false
        )
        return result if wait <= 0 && err.nil?
        raise err if wait <= 0 && err

        last_error = err
        @sleep.call(wait)
      end

      _wait, result, err = attempt_request(
        method, path, payload, idempotency_key, expect_json, MAX_ATTEMPTS, last: true
      )
      raise err if err

      result
    end

    # Verify the token. A 403 is accepted (key valid, missing +org:read+).
    def ping
      request("GET", "/v1/usage")
    rescue APIError => e
      return if e.status_code == 403

      raise
    end

    # --- Scenarios ----------------------------------------------------------

    def create_scenario(data = nil, idempotency_key: nil, **kwargs)
      body = normalize_body(data || kwargs)
      request(
        "POST", "/v1/scenarios",
        body: body,
        idempotency_key: idempotency_key || SecureRandom.uuid
      )
    end

    def get_scenario(scenario_id)
      request("GET", "/v1/scenarios/#{esc(scenario_id)}")
    end

    def update_scenario(scenario_id, data = nil, **kwargs)
      request("PATCH", "/v1/scenarios/#{esc(scenario_id)}", body: normalize_body(data || kwargs))
    end

    def delete_scenario(scenario_id)
      request("DELETE", "/v1/scenarios/#{esc(scenario_id)}", expect_json: false)
      nil
    end

    def list_scenarios
      list_paged("/v1/scenarios")
    end

    def mute_scenario(scenario_id, muted_until = nil)
      request(
        "POST",
        "/v1/scenarios/#{esc(scenario_id)}/mute",
        body: { "mutedUntil" => muted_until },
        expect_json: false
      )
      nil
    end

    # --- Maintenance windows ------------------------------------------------

    def create_maintenance_window(data = nil, idempotency_key: nil, **kwargs)
      request(
        "POST", "/v1/maintenance-windows",
        body: normalize_body(data || kwargs),
        idempotency_key: idempotency_key || SecureRandom.uuid
      )
    end

    def get_maintenance_window(window_id)
      request("GET", "/v1/maintenance-windows/#{esc(window_id)}")
    end

    def delete_maintenance_window(window_id)
      request("DELETE", "/v1/maintenance-windows/#{esc(window_id)}", expect_json: false)
      nil
    end

    def list_maintenance_windows
      list_paged("/v1/maintenance-windows")
    end

    # --- Webhooks -----------------------------------------------------------

    def create_webhook(data = nil, idempotency_key: nil, **kwargs)
      request(
        "POST", "/v1/webhooks",
        body: normalize_body(data || kwargs),
        idempotency_key: idempotency_key || SecureRandom.uuid
      )
    end

    def get_webhook(webhook_id)
      request("GET", "/v1/webhooks/#{esc(webhook_id)}")
    end

    def delete_webhook(webhook_id)
      request("DELETE", "/v1/webhooks/#{esc(webhook_id)}", expect_json: false)
      nil
    end

    def list_webhooks
      list_paged("/v1/webhooks")
    end

    # --- SLA targets --------------------------------------------------------

    def upsert_sla_target(data = nil, idempotency_key: nil, **kwargs)
      request(
        "PUT", "/v1/sla-targets",
        body: normalize_body(data || kwargs),
        idempotency_key: idempotency_key || SecureRandom.uuid
      )
    end

    def get_sla_target(target_id)
      request("GET", "/v1/sla-targets/#{esc(target_id)}")
    end

    def delete_sla_target(target_id)
      request("DELETE", "/v1/sla-targets/#{esc(target_id)}", expect_json: false)
      nil
    end

    def list_sla_targets
      list_paged("/v1/sla-targets")
    end

    # --- Pagination ---------------------------------------------------------

    def list_paged(base, extra = nil)
      items = []
      cursor = ""
      MAX_PAGES.times do
        query = { "limit" => PAGE_SIZE.to_s }
        query.merge!(extra.transform_keys(&:to_s)) if extra
        query["cursor"] = cursor unless cursor.empty?
        path = "#{base}?#{URI.encode_www_form(query)}"
        page = request("GET", path)
        batch = page.is_a?(Hash) ? (page["items"] || []) : []
        items.concat(batch)
        next_cursor = page.is_a?(Hash) ? page["nextCursor"] : nil
        return items if next_cursor.nil? || next_cursor.to_s.empty?

        cursor = next_cursor.to_s
      end
      raise APIError.new(0, "pagination exceeded #{MAX_PAGES} pages for #{base}", base)
    end

    private

    def normalize_body(data)
      raise ArgumentError, "expected Hash, got #{data.class}" if data.nil?

      case data
      when Hash
        omit_nil(stringify_keys(data))
      else
        raise ArgumentError, "expected Hash, got #{data.class}" unless data.respond_to?(:to_h)

        omit_nil(stringify_keys(data.to_h))
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), out|
        out[k.to_s] = v
      end
    end

    def omit_nil(hash)
      hash.reject { |_k, v| v.nil? }
    end

    def esc(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    def attempt_request(method, path, payload, idempotency_key, expect_json, attempt, last:)
      status, raw, headers = @http_request.call(method, path, payload, idempotency_key)

      if status == 429 || status >= 500
        failure = Pathly.parse_api_error(status, path, raw)
        return [0.0, nil, failure] if last

        return [wait_for(headers, attempt), nil, failure]
      end

      if status >= 400
        return [0.0, nil, Pathly.parse_api_error(status, path, raw)]
      end

      return [0.0, nil, nil] if !expect_json || raw.nil? || raw.empty?

      begin
        [0.0, JSON.parse(raw), nil]
      rescue JSON::ParserError => e
        [
          0.0,
          nil,
          APIError.new(status, "unreadable response from #{method} #{path}: #{e.message}", path)
        ]
      end
    rescue StandardError => e
      wrapped = APIError.new(0, "calling #{method} #{path}: #{e.message}", path)
      return [0.0, nil, wrapped] if last

      [backoff(attempt), nil, wrapped]
    end

    def default_http_request(method, path, payload, idempotency_key)
      uri = URI.parse(@base_url + path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      req_class = {
        "GET" => Net::HTTP::Get,
        "POST" => Net::HTTP::Post,
        "PATCH" => Net::HTTP::Patch,
        "PUT" => Net::HTTP::Put,
        "DELETE" => Net::HTTP::Delete
      }.fetch(method.upcase) { raise ArgumentError, "unsupported method #{method}" }

      req = req_class.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      req["User-Agent"] = @user_agent
      if payload
        req["Content-Type"] = "application/json"
        req.body = payload
      end
      req["Idempotency-Key"] = idempotency_key if idempotency_key

      res = http.request(req)
      headers = res.each_header.to_h.transform_keys(&:downcase)
      [res.code.to_i, res.body.to_s, headers]
    end

    def backoff(attempt)
      attempt * 0.5
    end

    def wait_for(headers, attempt)
      raw = headers["retry-after"].to_s
      unless raw.empty?
        begin
          secs = Float(raw.strip)
          return [secs, MAX_RETRY_WAIT].min if secs.positive?
        rescue ArgumentError, TypeError
          # fall through
        end
      end
      backoff(attempt)
    end
  end
end
