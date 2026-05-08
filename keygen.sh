#!/usr/bin/env bash
set -euo pipefail

# Load LITELLM_MASTER_KEY from .env if not already set
if [[ -z "${LITELLM_MASTER_KEY:-}" && -f "$(dirname "$0")/.env" ]]; then
  source "$(dirname "$0")/.env"
fi

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "Error: LITELLM_MASTER_KEY is not set. Run from the project directory or export it first." >&2
  exit 1
fi

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"

read -rp "Key alias (e.g. opencode): " ALIAS

# TPM — Tokens Per Minute
#   Caps the total number of tokens (prompt + response) the key can consume per minute.
#   Sensible values:
#     500000  — light personal use
#     1000000 — comfortable coding sessions (default)
#     5000000 — heavy multi-file context or long conversations
read -rp "TPM limit  [1000000]: " TPM;  TPM="${TPM:-1000000}"

# RPM — Requests Per Minute
#   Caps how many API calls the key can make per minute.
#   opencode sends one request per message, so this is effectively messages/min.
#   Sensible values:
#     20  — relaxed, prevents any runaway loops
#     60  — one per second, plenty for interactive use (default)
#     120 — if you use opencode in agentic/auto mode heavily
read -rp "RPM limit  [60]:      " RPM;  RPM="${RPM:-60}"

RESPONSE=$(curl -sf -X POST "$LITELLM_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"models\": [\"qwen3-coder\"],
    \"key_alias\": \"$ALIAS\",
    \"tpm_limit\": $TPM,
    \"rpm_limit\": $RPM
  }")

KEY=$(echo "$RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

echo ""
echo "Key:   $KEY"
echo "Alias: $ALIAS"
echo "TPM:   $TPM  |  RPM: $RPM"
echo ""
echo "opencode config:"
echo "  \"apiKey\": \"$KEY\""
