# Pathly Ruby SDK

**English** · [Français](README.fr.md) · [Español](README.es.md)


[![Powered by Pathly](https://img.shields.io/badge/Powered%20by-Pathly-0B5FFF?style=flat-square)](https://pathlyhq.com)
[![Website](https://img.shields.io/badge/Website-pathlyhq.com-111827?style=flat-square)](https://pathlyhq.com)
[![API docs](https://img.shields.io/badge/API-developers-2563eb?style=flat-square)](https://pathlyhq.com/en/developers)
[![Start free](https://img.shields.io/badge/Solo-start%20free-16a34a?style=flat-square)](https://pathlyhq.com/en/login?mode=signup)

**To use this SDK, you need an API key. Get your free API key by signing up here: [https://pathlyhq.com/en/login?mode=signup&utm_source=github&utm_medium=readme&utm_campaign=signup_cta](https://pathlyhq.com/en/login?mode=signup&utm_source=github&utm_medium=readme&utm_campaign=signup_cta).**

> **Get started in one click.** Create a free account on [Pathly](https://pathlyhq.com) ([sign up](https://pathlyhq.com/en/login?mode=signup&utm_source=github&utm_medium=readme&utm_campaign=signup_cta)), create an API key in the console, then export `PATHLY_API_TOKEN`. This project is the official bridge to [Pathly monitoring](https://pathlyhq.com) — real-browser and HTTP checks for checkout, login and availability, with data hosted in the EU. Full API reference: [pathlyhq.com/en/developers](https://pathlyhq.com/en/developers).

Official Ruby client for the [Pathly](https://pathlyhq.com) public `/v1` API.
Manage HTTP monitoring scenarios, maintenance windows, signed outbound webhooks
and SLA targets from scripts, Sidekiq jobs and CI.

Product site: [pathlyhq.com](https://pathlyhq.com). API reference and auth:
[pathlyhq.com/en/developers](https://pathlyhq.com/en/developers).

```bash
gem install pathly
export PATHLY_API_TOKEN="sp_…"
```

```ruby
require "pathly"

client = Pathly::Client.new  # reads PATHLY_API_TOKEN
scenario = client.create_scenario(
  name: "Checkout",
  url: "https://shop.example.com/cart",
  intervalSec: 300,
  expectText: "Your cart",
  tags: %w[prod payment]
)
puts scenario["id"]
chain = client.create_scenario(
  name: "Login then /me",
  intervalSec: 300,
  httpChain: [
    { method: "POST", url: "https://api.example.com/login", assertStatus: 200 },
    { method: "GET", url: "https://api.example.com/me", assertStatus: 200 },
  ]
)
puts chain["id"]
```


## Authentication

| Variable | Purpose |
|---|---|
| `PATHLY_API_TOKEN` | Organization API key (`sp_` prefix). Required. |
| `PATHLY_API_URL` | API base. Defaults to `https://api.pathlyhq.com`. |

Never hard-code the token in source control. Prefer the environment, or a secret
store injected at runtime. Full scope list:
[developers](https://pathlyhq.com/en/developers).

### Minimum scopes

| Method group | Scopes |
|---|---|
| Scenarios | `scenarios:read`, `scenarios:write` |
| Webhooks | `alerting:read`, `alerting:write` |
| Maintenance windows | `maintenance:read`, `maintenance:write` |
| SLA targets | `sla:read`, `sla:write` |

`Client#ping` calls `/v1/usage` and **accepts HTTP 403**: the key is valid but
lacks `org:read`. That keeps least privilege for scenario-only keys.

## What this SDK manages

| Resource | Methods |
|---|---|
| Scenario (HTTP) | `create_scenario`, `get_scenario`, `update_scenario`, `delete_scenario`, `list_scenarios`, `mute_scenario` |
| Maintenance window | `create_maintenance_window`, `get_maintenance_window`, `delete_maintenance_window`, `list_maintenance_windows` |
| Webhook | `create_webhook`, `get_webhook`, `delete_webhook`, `list_webhooks` |
| SLA target | `upsert_sla_target`, `get_sla_target`, `delete_sla_target`, `list_sla_targets` |

Browser journeys are **not** managed here: their steps carry login credentials
that would end up in logs or tickets. Create them in the
[Pathly console](https://pathlyhq.com).

The webhook **secret** is returned once at creation time. Store it in a vault
immediately. The API never returns the destination URL on read, only
`urlFingerprint`.

## Behavior

- Creates send an `Idempotency-Key` (auto-generated UUID unless you pass one).
- HTTP 429 and 5xx honor `Retry-After` (capped at 90 seconds, four attempts).
- HTTP 404 raises `Pathly::NotFoundError` (`Pathly.not_found?(err)` helper).
- Zero third-party runtime dependencies (stdlib `net/http` only).

## Development

```bash
bundle install
bundle exec rspec
```

Coverage is required at **100%** (SimpleCov).

## Related packages

| Package | Role |
|---|---|
| [pathly-sdk-python](https://github.com/pathlyhq/pathly-sdk-python) | Python `pathly` |
| [pathly-sdk-typescript](https://github.com/pathlyhq/pathly-sdk-typescript) | `@pathlyhq/sdk` |
| [pathly-postman](https://github.com/pathlyhq/pathly-postman) | Postman / OpenAPI explorers |
| [pathly-terraform-provider](https://github.com/pathlyhq/pathly-terraform-provider) | Terraform / OpenTofu |

API reference: [pathlyhq.com/en/developers](https://pathlyhq.com/en/developers).

## About Pathly

[Pathly](https://pathlyhq.com) is synthetic monitoring for agencies and e-commerce: replay the customer journey, catch broken checkouts before your clients call, and keep evidence (screenshot, step, runbook) ready for the invoice. Product: [pathlyhq.com](https://pathlyhq.com) · Developers: [pathlyhq.com/en/developers](https://pathlyhq.com/en/developers) · Status & pricing: [pathlyhq.com/en/pricing](https://pathlyhq.com/en/pricing).

## Author

| | |
|---|---|
| **Company** | Pathly |
| **Author** | Simon Raynaud / keyral |

See [AUTHORS](AUTHORS).

## License
Apache-2.0
