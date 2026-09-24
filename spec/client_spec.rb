# frozen_string_literal: true

require "json"
require "securerandom"
require "pathly"

RSpec.describe Pathly::Client do
  def client(handler, **kwargs)
    Pathly::Client.new(token: "sp_test", sleep: ->(_) {}, http_request: handler, **kwargs)
  end

  def ok(body, status: 200, headers: {})
    [status, body.is_a?(String) ? body : JSON.generate(body), headers]
  end

  it "requires a token" do
    ENV.delete("PATHLY_API_TOKEN")
    expect { Pathly::Client.new(token: "") }.to raise_error(ArgumentError, /PATHLY_API_TOKEN/)
  end

  it "defaults base_url and reads env" do
    ENV["PATHLY_API_TOKEN"] = "sp_env"
    ENV["PATHLY_API_URL"] = "https://example.test/"
    calls = []
    handler = lambda { |method, path, _payload, _key|
      calls << [method, path]
      ok({ "planId" => "p" })
    }
    c = Pathly::Client.new(sleep: ->(_) {}, http_request: handler)
    expect(c.base_url).to eq("https://example.test")
    c.ping
    expect(calls[0]).to eq(%w[GET /v1/usage])
  ensure
    ENV.delete("PATHLY_API_TOKEN")
    ENV.delete("PATHLY_API_URL")
  end

  it "uses DEFAULT_BASE_URL" do
    c = Pathly::Client.new(
      token: "sp_x",
      sleep: ->(_) {},
      http_request: ->(*) { ok({}) }
    )
    expect(c.base_url).to eq(Pathly::DEFAULT_BASE_URL)
  end

  it "ping accepts 403" do
    handler = ->(*) { [403, '{"error":"no"}', {}] }
    expect { client(handler).ping }.not_to raise_error
  end

  it "ping raises other errors" do
    handler = ->(*) { [401, '{"error":"no"}', {}] }
    expect { client(handler).ping }.to raise_error(Pathly::APIError) { |e|
      expect(e.status_code).to eq(401)
    }
  end

  it "retries 429 then succeeds" do
    n = 0
    handler = lambda { |*|
      n += 1
      return [429, '{"error":"slow"}', { "retry-after" => "1" }] if n == 1

      ok({ "id" => "mon_1", "name" => "A", "type" => "http" })
    }
    sc = client(handler).get_scenario("mon_1")
    expect(sc["id"]).to eq("mon_1")
    expect(n).to eq(2)
  end

  it "exhausts retries on 5xx" do
    handler = ->(*) { [503, '{"error":"down"}', {}] }
    expect { client(handler).get_scenario("mon_1") }.to raise_error(Pathly::APIError) { |e|
      expect(e.status_code).to eq(503)
    }
  end

  it "retries transport errors then fails" do
    handler = ->(*) { raise "boom" }
    expect { client(handler).get_scenario("mon_1") }.to raise_error(Pathly::APIError) { |e|
      expect(e.status_code).to eq(0)
    }
  end

  it "rejects invalid JSON" do
    handler = ->(*) { [200, "not-json", {}] }
    expect { client(handler).get_scenario("mon_1") }.to raise_error(Pathly::APIError, /unreadable/)
  end

  it "caps Retry-After and falls back on invalid" do
    c = Pathly::Client.new(token: "sp_t", sleep: ->(_) {}, http_request: ->(*) { ok({}) })
    expect(c.send(:wait_for, { "retry-after" => "nope" }, 2)).to eq(1.0)
    expect(c.send(:wait_for, { "retry-after" => "9999" }, 1)).to eq(Pathly::MAX_RETRY_WAIT)
    expect(c.send(:wait_for, { "retry-after" => "0" }, 3)).to eq(1.5)
  end

  it "covers scenario CRUD, mute and pagination" do
    pages = 0
    handler = lambda { |method, path, payload, key|
      if method == "POST" && path == "/v1/scenarios"
        body = JSON.parse(payload)
        expect(body["name"]).to eq("Checkout")
        expect(key).not_to be_nil
        return ok({ "id" => "mon_1", "name" => "Checkout", "type" => "http" }, status: 201)
      end
      return ok({ "id" => "mon_1", "name" => "Checkout", "type" => "http" }) if method == "GET" && path.include?("/v1/scenarios/mon_1")
      return ok({ "id" => "mon_1", "enabled" => false }) if method == "PATCH"
      return [204, "", {}] if method == "DELETE"
      return [204, "", {}] if method == "POST" && path.end_with?("/mute")

      if method == "GET" && path.include?("/v1/scenarios?")
        pages += 1
        if pages == 1
          return ok({ "items" => [{ "id" => "mon_1" }], "nextCursor" => "c1" })
        end
        return ok({ "items" => [{ "id" => "mon_2" }] })
      end
      raise "unexpected #{method} #{path}"
    }

    c = client(handler)
    expect(c.create_scenario({ name: "Checkout", url: "https://x", intervalSec: 60 })["id"]).to eq("mon_1")
    expect(c.get_scenario("mon_1")["name"]).to eq("Checkout")
    expect(c.update_scenario("mon_1", { enabled: false })["enabled"]).to eq(false)
    c.mute_scenario("mon_1", "2026-01-01T00:00:00Z")
    c.mute_scenario("mon_1", nil)
    listed = c.list_scenarios
    expect(listed.map { |s| s["id"] }).to eq(%w[mon_1 mon_2])
    c.delete_scenario("mon_1")
  end

  it "covers webhooks, maintenance and sla" do
    handler = lambda { |method, path, _payload, _key|
      if path.include?("webhooks")
        case method
        when "POST" then return ok({ "id" => "wh_1", "events" => ["run.failed"], "secret" => "sec" }, status: 201)
        when "GET"
          return ok({ "id" => "wh_1", "events" => ["run.failed"] }) if path.include?("wh_1")
          return ok({ "items" => [{ "id" => "wh_1", "events" => [] }] })
        when "DELETE" then return [204, "", {}]
        end
      end
      if path.include?("maintenance-windows")
        case method
        when "POST" then return ok({ "id" => "mw_1", "weekday" => 7 }, status: 201)
        when "GET"
          return ok({ "id" => "mw_1" }) if path.include?("mw_1")
          return ok({ "items" => [{ "id" => "mw_1" }] })
        when "DELETE" then return [204, "", {}]
        end
      end
      if path.include?("sla-targets")
        case method
        when "PUT" then return ok({ "id" => "sla_1", "objectivePct" => 99.9 })
        when "GET"
          return ok({ "id" => "sla_1" }) if path.include?("sla_1")
          return ok({ "items" => [{ "id" => "sla_1" }] })
        when "DELETE" then return [204, "", {}]
        end
      end
      raise path
    }

    c = client(handler)
    expect(c.create_webhook({ url: "https://hooks.example/x", events: ["run.failed"] })["secret"]).to eq("sec")
    expect(c.get_webhook("wh_1")["id"]).to eq("wh_1")
    expect(c.list_webhooks[0]["id"]).to eq("wh_1")
    c.delete_webhook("wh_1")

    expect(c.create_maintenance_window({ weekday: 7, startMinute: 180, durationMin: 120 })["id"]).to eq("mw_1")
    expect(c.get_maintenance_window("mw_1")["id"]).to eq("mw_1")
    expect(c.list_maintenance_windows[0]["id"]).to eq("mw_1")
    c.delete_maintenance_window("mw_1")

    expect(c.upsert_sla_target({ objectivePct: 99.9, windowDays: 30, monitorId: "mon_1" })["id"]).to eq("sla_1")
    expect(c.get_sla_target("sla_1")["id"]).to eq("sla_1")
    expect(c.list_sla_targets[0]["id"]).to eq("sla_1")
    c.delete_sla_target("sla_1")
  end

  it "raises on pagination overflow" do
    handler = ->(*) { ok({ "items" => [], "nextCursor" => "forever" }) }
    expect { client(handler).list_scenarios }.to raise_error(Pathly::APIError, /pagination exceeded/)
  end

  it "maps 404 to NotFoundError" do
    handler = ->(*) { [404, '{"error":"gone"}', {}] }
    expect { client(handler).get_scenario("missing") }.to raise_error(Pathly::NotFoundError) { |e|
      expect(Pathly.not_found?(e)).to eq(true)
    }
  end

  it "succeeds on final attempt" do
    n = 0
    handler = lambda { |*|
      n += 1
      return [503, '{"error":"down"}', {}] if n < 4

      ok({ "id" => "mon_ok", "name" => "OK", "type" => "http" })
    }
    expect(client(handler).get_scenario("mon_ok")["id"]).to eq("mon_ok")
    expect(n).to eq(4)
  end

  it "stops pagination when items key missing" do
    handler = ->(*) { ok({}) }
    expect(client(handler).list_scenarios).to eq([])
  end

  it "passes extra query to list_paged" do
    seen = []
    handler = lambda { |_m, path, _p, _k|
      seen << path
      ok({ "items" => [] })
    }
    client(handler).list_paged("/v1/scenarios", { "folder" => "Shop" })
    expect(seen[0]).to include("folder=Shop")
  end

  it "accepts objects responding to to_h" do
    body = Object.new
    def body.to_h
      { "name" => "M" }
    end
    handler = ->(*) { ok({ "id" => "mon_9", "name" => "M", "type" => "http" }, status: 201) }
    expect(client(handler).create_scenario(body)["id"]).to eq("mon_9")
  end

  it "rejects non-hash bodies" do
    handler = ->(*) { ok({}) }
    expect { client(handler).create_scenario("nope") }.to raise_error(ArgumentError)
  end

  it "default sleep delegates to Kernel.sleep" do
    allow(Kernel).to receive(:sleep)
    Pathly::Client::DEFAULT_SLEEP.call(0.01)
    expect(Kernel).to have_received(:sleep).with(0.01)
  end

  it "uses default Net::HTTP path for verbs" do
    responses = {
      "GET" => [200, '{"planId":"x"}'],
      "POST" => [201, '{"id":"mon_1"}'],
      "PATCH" => [200, '{"id":"mon_1"}'],
      "PUT" => [200, '{"id":"sla_1"}'],
      "DELETE" => [204, ""]
    }
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) do |req|
      status, body = responses.fetch(req.method)
      res = Object.new
      res.define_singleton_method(:code) { status.to_s }
      res.define_singleton_method(:body) { body }
      res.define_singleton_method(:each_header) do
        [["content-type", "application/json"]].to_enum
      end
      res
    end
    allow(Net::HTTP).to receive(:new).and_return(fake)

    c = Pathly::Client.new(token: "sp_t", sleep: ->(_) {})
    c.ping
    c.create_scenario({ name: "A" }, idempotency_key: "k1")
    c.update_scenario("mon_1", { enabled: false })
    c.upsert_sla_target({ objectivePct: 99.9, windowDays: 7 })
    c.delete_scenario("mon_1")
  end

  it "rejects unsupported HTTP methods" do
    c = Pathly::Client.new(token: "sp_t", sleep: ->(_) {}, http_request: ->(*) { ok({}) })
    expect {
      c.send(:default_http_request, "TRACE", "/v1/x", nil, nil)
    }.to raise_error(ArgumentError, /unsupported/)
  end

  it "parses details that are not a list" do
    err = Pathly.parse_api_error(400, "/v1", '{"error":"x","details":{"no":"list"}}')
    expect(err.message).to start_with("x")
  end
end

RSpec.describe Pathly do
  it "formats APIError" do
    expect(Pathly::APIError.new(400, "bad", "/v1/x").to_s).to eq("/v1/x: bad (HTTP 400)")
    expect(Pathly::APIError.new(400, "bad").to_s).to eq("bad (HTTP 400)")
    expect(Pathly::APIError.new(404, "x").not_found?).to eq(true)
    expect(Pathly.not_found?(Pathly::NotFoundError.new("gone"))).to eq(true)
    expect(Pathly.not_found?(Pathly::APIError.new(400, "bad"))).to eq(false)
    expect(Pathly.not_found?(StandardError.new("x"))).to eq(false)
  end

  it "parses API errors" do
    err = Pathly.parse_api_error(400, "/v1/s", "plain")
    expect(err.message).to eq("plain")

    err = Pathly.parse_api_error(
      422, "/v1/s",
      '{"error":"Invalid","details":[{"path":["events",0],"message":"bad"}]}'
    )
    expect(err.message).to include("Invalid", "events.0")

    err = Pathly.parse_api_error(422, "/v1/s", '{"error":"x","details":["skip"]}')
    expect(err.message).to include("x")

    err = Pathly.parse_api_error(400, "/v1/s", "{")
    expect(err.message).to eq("{")

    err = Pathly.parse_api_error(418, "/v1/s", "")
    expect(err.message.downcase).to include("teapot")

    err = Pathly.parse_api_error(599, "/v1/s", "")
    expect(err.message).to include("599")

    err = Pathly.parse_api_error(422, "/v1/s", '{"error":"x","details":[{"path":[],"message":"whole"}]}')
    expect(err.message).to include("body")

    expect(Pathly.parse_api_error(401, "/v1", '{"error":"no"}').message).to include("PATHLY_API_TOKEN")
    expect(Pathly.parse_api_error(403, "/v1", '{"error":"no"}').message).to include("scopes")
    expect(Pathly.parse_api_error(404, "/v1", '{"error":"gone"}')).to be_a(Pathly::NotFoundError)

    expect(Pathly.field_of([])).to eq("body")
    expect(Pathly.field_of(["a", 1, 2.0])).to eq("a.1.2")
    expect(Pathly.field_of(["ok", nil, Object.new])).to eq("ok")
  end

  it "exposes VERSION" do
    expect(Pathly::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
