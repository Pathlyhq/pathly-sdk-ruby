# Contributing

Thanks for helping improve Pathly integrations.

## Before you start

1. Read the product docs: https://pathlyhq.com/en/developers
2. Use only Pathly domains (`pathlyhq.com`, `api.pathlyhq.com`)
3. Never commit API tokens (`PATHLY_API_TOKEN` / `sp_…` keys)

## Workflow

1. Open an issue or discuss the change when it alters public API behaviour
2. Fork, branch from `main`, keep commits focused
3. Add or update unit tests (packages that require 100% coverage must stay at 100%)
4. Run the project test suite locally before opening a pull request
5. Link related docs or examples when behaviour changes

## Auth env var

Use **`PATHLY_API_TOKEN`** (not `PATHLY_API_KEY`). Optional base URL: `PATHLY_API_URL`.

## Security

Report vulnerabilities privately via [SECURITY.md](./SECURITY.md) — **security@pathlyhq.com**. Privacy: **privacy@pathlyhq.com**.

## Code of conduct

Be respectful. Harassment or abuse is not tolerated. Maintainers may decline contributions that violate this.
