# frozen_string_literal: true

# Examples for the Pathly Ruby SDK. Requires PATHLY_API_TOKEN.
# Docs: https://pathlyhq.com/en/developers

require "pathly"

client = Pathly::Client.new
client.ping

scenario = client.create_scenario(
  name: "Checkout funnel",
  url: "https://shop.example.com/cart",
  intervalSec: 300,
  expectedStatus: 200,
  expectText: "Your cart",
  severity: "critical",
  tags: %w[prod payment],
  runbook: "https://wiki.example.com/ops/checkout"
)

window = client.create_maintenance_window(
  monitorId: scenario["id"],
  weekday: 7,
  startMinute: 180,
  durationMin: 120,
  reason: "Weekly backup"
)

webhook = client.create_webhook(
  url: "https://hooks.example.com/pathly",
  events: %w[run.failed run.recovered]
)
# Store webhook["secret"] in your vault immediately — it is shown once.

sla = client.upsert_sla_target(
  monitorId: scenario["id"],
  name: "Checkout — 99.9 %",
  objectivePct: 99.9,
  windowDays: 30,
  excludeMaintenance: true,
  warnAtBudgetRatio: 0.8
)

puts({
  scenario: scenario["id"],
  window: window["id"],
  webhook: webhook["id"],
  sla: sla["id"]
})
