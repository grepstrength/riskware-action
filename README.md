# ⛓ RiskwareSupplyChain — GitHub Action

Scan your open-source dependencies for CVEs, public exploits, and supply chain compromises on every pull request.

Powered by [RiskwareSupplyChain](https://riskwaresupplychain.com) — supply chain risk intelligence for developers, appsec engineers, and GRC professionals.

## Features

- **Auto-discovers manifests** — Finds `package.json`, `go.mod`, `requirements.txt`, `Cargo.toml`, `pom.xml`, and more
- **Multi-source intelligence** — Scans against NVD, OSV, npm advisories, public exploits, and supply chain breach data
- **PR comments** — Posts a vulnerability summary directly on your pull request
- **Fail thresholds** — Optionally block PRs that introduce critical or high vulnerabilities
- **Remediation guidance** — Shows exact upgrade commands for each vulnerable package

## Quick Start

1. Get an API key at [riskwaresupplychain.com](https://riskwaresupplychain.com) (requires Pro tier — $4.99/mo)
2. Add your API key as a repository secret: **Settings → Secrets → New repository secret** → Name: `RSC_API_KEY`
3. Create `.github/workflows/riskware.yml`:

```yaml
name: RiskwareSupplyChain Scan

on:
  pull_request:
    branches: [main]

permissions:
  pull-requests: write
  contents: read

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: grepstrength/riskware-action@v1
        with:
          api-key: ${{ secrets.RSC_API_KEY }}
```

That's it. Every PR to `main` will now be scanned.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-key` | Yes | — | Your RiskwareSupplyChain API key (`rsk_...`). Store as a GitHub secret. |
| `fail-on` | No | `none` | Fail the workflow at this severity: `critical`, `high`, `medium`, `low`, or `none`. |
| `comment` | No | `true` | Post scan results as a PR comment. |
| `api-url` | No | Production URL | Override for self-hosted or staging environments. |

## Examples

### Block PRs with critical vulnerabilities

```yaml
- uses: grepstrength/riskware-action@v1
  with:
    api-key: ${{ secrets.RSC_API_KEY }}
    fail-on: critical
```

### Scan on push to main (no PR comment)

```yaml
name: RiskwareSupplyChain Scan

on:
  push:
    branches: [main]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: grepstrength/riskware-action@v1
        with:
          api-key: ${{ secrets.RSC_API_KEY }}
          comment: 'false'
```

### Scan on both push and PR

```yaml
name: RiskwareSupplyChain Scan

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  pull-requests: write
  contents: read

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: grepstrength/riskware-action@v1
        with:
          api-key: ${{ secrets.RSC_API_KEY }}
          fail-on: high
```

## PR Comment Preview

The Action posts a comment like this on your PR:

> ## ⛓ RiskwareSupplyChain — Dependency Scan
>
> **🔴 CRITICAL** — 47 packages scanned across 1 manifest(s)
>
> | Severity | Count |
> |----------|-------|
> | 🔴 Critical | 2 |
> | 🟠 High | 5 |
> | 🟡 Medium | 8 |
> | 🔵 Low | 3 |
>
> <details>
> <summary>📋 Vulnerable packages (click to expand)</summary>
>
> | Package | Version | CVEs | Risk | Fix |
> |---------|---------|------|------|-----|
> | `lodash` | 4.17.15 | 3 CVE(s) | CRITICAL | Upgrade to 4.17.21 |
> | `tough-cookie` | 4.0.0 | 1 CVE(s) | CRITICAL | Upgrade to 4.1.3 |
>
> </details>

## Supported Manifest Files

| File | Ecosystem |
|------|-----------|
| `package.json` | npm |
| `requirements.txt` | PyPI |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` | Maven |
| `build.gradle` | Gradle |
| `Gemfile` | Ruby |
| `composer.json` | PHP |

## Requirements

- **RiskwareSupplyChain Pro tier** ($4.99/mo) or higher
- A valid API key stored as a GitHub secret

## CORS Note

The GitHub Action calls the RiskwareSupplyChain API server-side from GitHub's runners — not from a browser. No CORS configuration is needed.

## License

MIT

## Links

- [RiskwareSupplyChain](https://riskwaresupplychain.com)
- [grepStrength Security](https://grepstrength.com)
- [Report an issue](https://github.com/grepstrength/riskware-action/issues)
