#!/usr/bin/env bash
set -u

check_quanticdata() {
  if [ -z "${QD_KEY:-}" ]; then
    echo "[QuanticData] QD_KEY is not set (skipping API check)"
    return 0
  fi

  echo "[QuanticData] QD_KEY detected; checking API status..."
  local resp http_code body
  resp="$(curl -s -w "\n%{http_code}" --max-time 10 \
    -H "Authorization: Bearer ${QD_KEY}" \
    -H "Accept: application/json" \
    "https://api.quanticdata.io/v1/public/balance" 2>&1)" || {
    echo "[QuanticData] Curl request failed: $resp"
    return 0
  }

  http_code="$(printf '%s\n' "$resp" | tail -n1)"
  body="$(printf '%s\n' "$resp" | sed '$d')"

  echo "[QuanticData] HTTP Status: ${http_code}"
  if [ "$http_code" = "200" ]; then
    printf '%s\n' "$body" | head -c 300
    echo ""
  else
    echo "[QuanticData] Non-200 response received (check key or balance)"
  fi
}

check_quanticdata

# ကိုယ့် Service / Startup command ကို အောက်မှာ ဆက်ထည့်ပါ
# ဥပမာ-
# exec /start.sh

