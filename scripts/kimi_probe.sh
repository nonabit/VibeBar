#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages"
BODY='{"scope":["FEATURE_CODING"]}'

TOKEN="${KIMI_AUTH_TOKEN:-${1:-}}"
if [[ -z "${TOKEN}" ]]; then
  echo "错误: 缺少 token。请设置环境变量 KIMI_AUTH_TOKEN 或作为第一个参数传入。" >&2
  exit 2
fi

if [[ "${TOKEN}" != *.*.* ]]; then
  echo "提示: 当前 token 不是 JWT 形态，可能是 API Key（sk-kimi-*）。" >&2
  echo "提示: BillingService/GetUsages 通常要求 kimi-auth cookie 的 JWT，而不是 API Key。" >&2
fi

b64_decode() {
  if base64 --decode </dev/null >/dev/null 2>&1; then
    base64 --decode 2>/dev/null || true
  else
    base64 -D 2>/dev/null || true
  fi
}

jwt_payload_json() {
  local token="$1"
  local payload
  IFS='.' read -r _ payload _ <<<"$token" || true
  if [[ -z "${payload:-}" ]]; then
    return 0
  fi
  payload="${payload//-/+}"
  payload="${payload//_/\/}"
  local mod=$(( ${#payload} % 4 ))
  if [[ $mod -eq 2 ]]; then
    payload+="=="
  elif [[ $mod -eq 3 ]]; then
    payload+="="
  elif [[ $mod -eq 1 ]]; then
    return 0
  fi
  printf '%s' "$payload" | b64_decode
}

JWT_JSON="$(jwt_payload_json "$TOKEN")"

DEVICE_ID=""
SESSION_ID=""
TRAFFIC_ID=""
if command -v jq >/dev/null 2>&1 && [[ -n "${JWT_JSON}" ]]; then
  DEVICE_ID="$(printf '%s' "$JWT_JSON" | jq -r '.device_id // empty' 2>/dev/null || true)"
  SESSION_ID="$(printf '%s' "$JWT_JSON" | jq -r '.ssid // empty' 2>/dev/null || true)"
  TRAFFIC_ID="$(printf '%s' "$JWT_JSON" | jq -r '.sub // empty' 2>/dev/null || true)"
fi

TIMEZONE_NAME="${R_TIMEZONE:-${TZ:-Etc/UTC}}"
TMP_BODY="$(mktemp)"
TMP_HEADERS="$(mktemp)"
trap 'rm -f "$TMP_BODY" "$TMP_HEADERS"' EXIT

CURL_ARGS=(
  -sS
  -X POST "$ENDPOINT"
  -H "Content-Type: application/json"
  -H "Authorization: Bearer $TOKEN"
  -H "Cookie: kimi-auth=$TOKEN"
  -H "Origin: https://www.kimi.com"
  -H "Referer: https://www.kimi.com/code/console"
  -H "Accept: */*"
  -H "Accept-Language: en-US,en;q=0.9"
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
  -H "connect-protocol-version: 1"
  -H "x-language: en-US"
  -H "x-msh-platform: web"
  -H "r-timezone: $TIMEZONE_NAME"
  --data "$BODY"
  -D "$TMP_HEADERS"
  -o "$TMP_BODY"
  -w "%{http_code}"
)

if [[ -n "$DEVICE_ID" ]]; then
  CURL_ARGS+=( -H "x-msh-device-id: $DEVICE_ID" )
fi
if [[ -n "$SESSION_ID" ]]; then
  CURL_ARGS+=( -H "x-msh-session-id: $SESSION_ID" )
fi
if [[ -n "$TRAFFIC_ID" ]]; then
  CURL_ARGS+=( -H "x-traffic-id: $TRAFFIC_ID" )
fi

HTTP_CODE="$(curl "${CURL_ARGS[@]}")"

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "请求失败，HTTP $HTTP_CODE" >&2
  echo "---- 响应头 ----" >&2
  cat "$TMP_HEADERS" >&2
  echo "---- 响应体 ----" >&2
  cat "$TMP_BODY" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo "请求成功，已解析 FEATURE_CODING 用量："
  jq -r '
    .usages[] | select(.scope=="FEATURE_CODING") |
    {
      weekly_limit: (.detail.limit|tonumber?),
      weekly_used: (.detail.used|tonumber?),
      weekly_remaining: (.detail.remaining|tonumber?),
      weekly_reset_time: .detail.resetTime,
      rate_limit_window_minutes: (.limits[0].window.duration // null),
      rate_limit_limit: (.limits[0].detail.limit|tonumber?),
      rate_limit_used: (.limits[0].detail.used|tonumber?),
      rate_limit_remaining: (.limits[0].detail.remaining|tonumber?),
      rate_limit_reset_time: .limits[0].detail.resetTime
    }
  ' "$TMP_BODY"
else
  echo "请求成功（系统未安装 jq，输出原始 JSON）："
  cat "$TMP_BODY"
fi
