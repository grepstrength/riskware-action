#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════
# RiskwareSupplyChain GitHub Action — Dependency  Scanner
# ═══════════════════════════════════════════════════

API_URL="${RSC_API_URL:-https://riskware-supply-chain-production.up.railway.app}"
API_KEY="${RSC_API_KEY}"
FAIL_ON="${RSC_FAIL_ON:-none}"
POST_COMMENT="${RSC_COMMENT:-true}"

# ── Manifest discovery ──────────────────────────────
echo "::group::Discovering manifest files"

MANIFESTS=()
MANIFEST_NAMES=(
  "package.json"
  "go.mod"
  "requirements.txt"
  "Cargo.toml"
  "pom.xml"
  "build.gradle"
  "Gemfile"
  "composer.json"
)

for name in "${MANIFEST_NAMES[@]}"; do
  while IFS= read -r file; do
    # Skip node_modules, vendor, and other dependency directories.
    if [[ "$file" == *node_modules* ]] || [[ "$file" == *vendor* ]] || [[ "$file" == *__pycache__* ]]; then
      continue
    fi
    MANIFESTS+=("$file")
    echo "  Found: $file"
  done < <(find . -name "$name" -type f 2>/dev/null || true)
done

if [ ${#MANIFESTS[@]} -eq 0 ]; then
  echo "No manifest files found. Nothing to scan."
  echo "::endgroup::"
  exit 0
fi

echo "Found ${#MANIFESTS[@]} manifest file(s)."
echo "::endgroup::"

# ── Scan each manifest ──────────────────────────────
TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_MEDIUM=0
TOTAL_LOW=0
TOTAL_PACKAGES=0
ALL_RESULTS=""

for manifest in "${MANIFESTS[@]}"; do
  echo "::group::Scanning $manifest"

  CONTENT=$(cat "$manifest")

  # POST to the paste endpoint — it auto-detects format.
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${API_URL}/api/v1/scan/paste" \
    -H "Authorization: ApiKey ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$CONTENT" '{ text: $text }')")

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [ "$HTTP_CODE" -ne 200 ]; then
    echo "::warning::Scan failed for $manifest (HTTP $HTTP_CODE): $(echo "$BODY" | jq -r '.error // "unknown error"')"
    echo "::endgroup::"
    continue
  fi

  # Parse results — API returns { "results": [...], ... }
  RESULTS=$(echo "$BODY" | jq -r '.results // []')
  PKG_COUNT=$(echo "$RESULTS" | jq 'length')
  TOTAL_PACKAGES=$((TOTAL_PACKAGES + PKG_COUNT))

  # Count vulnerabilities by severity.
  # API field: .risk_score with lowercase values: "critical", "high", "medium", "low"
  CRIT=$(echo "$RESULTS" | jq '[.[] | select(.risk_score == "critical")] | length')
  HIGH=$(echo "$RESULTS" | jq '[.[] | select(.risk_score == "high")] | length')
  MED=$(echo "$RESULTS" | jq '[.[] | select(.risk_score == "medium")] | length')
  LOW=$(echo "$RESULTS" | jq '[.[] | select(.risk_score == "low")] | length')

  TOTAL_CRITICAL=$((TOTAL_CRITICAL + CRIT))
  TOTAL_HIGH=$((TOTAL_HIGH + HIGH))
  TOTAL_MEDIUM=$((TOTAL_MEDIUM + MED))
  TOTAL_LOW=$((TOTAL_LOW + LOW))

  echo "  Packages: $PKG_COUNT | Critical: $CRIT | High: $HIGH | Medium: $MED | Low: $LOW"

  # Build per-manifest results for the comment.
  if [ "$PKG_COUNT" -gt 0 ]; then
    # Extract vulnerable packages (those with CVEs).
    # API fields: .package_name, .declared_version, .vulnerabilities[], .risk_score
    VULN_ROWS=$(echo "$RESULTS" | jq -r '
      .[] | select(.vulnerabilities != null and (.vulnerabilities | length) > 0) |
      "| `\(.package_name)` | \(.declared_version) | \(.vulnerabilities | length) CVE(s) | \(.risk_score | ascii_upcase) | \([ .vulnerabilities[] | select(.fixed != null and .fixed != "") | .fixed ] | unique | join(", ") | if . == "" then "—" else . end) |"
    ')

    if [ -n "$VULN_ROWS" ]; then
      ALL_RESULTS="${ALL_RESULTS}

### 📂 \`${manifest}\`

| Package | Version | CVEs | Risk | Fix |
|---------|---------|------|------|-----|
${VULN_ROWS}"
    fi
  fi

  echo "::endgroup::"
done

# ── Summary ─────────────────────────────────────────
echo "::group::Summary"
TOTAL_VULNS=$((TOTAL_CRITICAL + TOTAL_HIGH + TOTAL_MEDIUM + TOTAL_LOW))
echo "Total packages scanned: $TOTAL_PACKAGES"
echo "Total vulnerable: $TOTAL_VULNS"
echo "  Critical: $TOTAL_CRITICAL"
echo "  High:     $TOTAL_HIGH"
echo "  Medium:   $TOTAL_MEDIUM"
echo "  Low:      $TOTAL_LOW"
echo "::endgroup::"

# ── Post PR comment ─────────────────────────────────
if [ "$POST_COMMENT" = "true" ] && [ -n "${GITHUB_EVENT_NAME:-}" ] && [ "${GITHUB_EVENT_NAME}" = "pull_request" ]; then
  echo "::group::Posting PR comment"

  PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")

  if [ "$PR_NUMBER" != "null" ] && [ -n "$PR_NUMBER" ]; then

    # Build severity badge.
    if [ "$TOTAL_CRITICAL" -gt 0 ]; then
      BADGE="🔴 CRITICAL"
    elif [ "$TOTAL_HIGH" -gt 0 ]; then
      BADGE="🟠 HIGH"
    elif [ "$TOTAL_MEDIUM" -gt 0 ]; then
      BADGE="🟡 MEDIUM"
    elif [ "$TOTAL_LOW" -gt 0 ]; then
      BADGE="🔵 LOW"
    else
      BADGE="🟢 CLEAN"
    fi

    # Build the comment body.
    COMMENT_BODY="## ⛓ RiskwareSupplyChain — Dependency Scan

**${BADGE}** — ${TOTAL_PACKAGES} packages scanned across ${#MANIFESTS[@]} manifest(s)

| Severity | Count |
|----------|-------|
| 🔴 Critical | ${TOTAL_CRITICAL} |
| 🟠 High | ${TOTAL_HIGH} |
| 🟡 Medium | ${TOTAL_MEDIUM} |
| 🔵 Low | ${TOTAL_LOW} |
"

    if [ -n "$ALL_RESULTS" ]; then
      COMMENT_BODY="${COMMENT_BODY}

<details>
<summary>📋 Vulnerable packages (click to expand)</summary>
${ALL_RESULTS}
</details>"
    fi

    COMMENT_BODY="${COMMENT_BODY}

---
<sub>Scanned by [RiskwareSupplyChain](https://riskwaresupplychain.com) · [Get your API key](https://riskwaresupplychain.com)</sub>"

    # Post comment via GitHub API.
    curl -s -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
      -d "$(jq -n --arg body "$COMMENT_BODY" '{ body: $body }')" > /dev/null

    echo "  Comment posted on PR #${PR_NUMBER}"
  else
    echo "  Not a PR event or PR number not found — skipping comment."
  fi

  echo "::endgroup::"
fi

# ── Fail threshold ──────────────────────────────────
case "$FAIL_ON" in
  critical)
    if [ "$TOTAL_CRITICAL" -gt 0 ]; then
      echo "::error::Found ${TOTAL_CRITICAL} critical vulnerability(ies). Failing workflow (fail-on: critical)."
      exit 1
    fi
    ;;
  high)
    if [ "$TOTAL_CRITICAL" -gt 0 ] || [ "$TOTAL_HIGH" -gt 0 ]; then
      echo "::error::Found critical/high vulnerabilities. Failing workflow (fail-on: high)."
      exit 1
    fi
    ;;
  medium)
    if [ "$TOTAL_CRITICAL" -gt 0 ] || [ "$TOTAL_HIGH" -gt 0 ] || [ "$TOTAL_MEDIUM" -gt 0 ]; then
      echo "::error::Found critical/high/medium vulnerabilities. Failing workflow (fail-on: medium)."
      exit 1
    fi
    ;;
  low)
    if [ "$TOTAL_VULNS" -gt 0 ]; then
      echo "::error::Found vulnerabilities. Failing workflow (fail-on: low)."
      exit 1
    fi
    ;;
  none|*)
    # Never fail.
    ;;
esac

echo "✅ Scan complete."
