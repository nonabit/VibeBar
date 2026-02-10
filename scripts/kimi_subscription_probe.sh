#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="https://www.kimi.com/apiv2/kimi.gateway.order.v1.SubscriptionService/GetSubscription"
if [[ -n "${KIMI_SUBSCRIPTION_ENDPOINT:-}" ]]; then
  ENDPOINT="${KIMI_SUBSCRIPTION_ENDPOINT}"
fi
TOKEN=""

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

normalize_level() {
  local raw="${1:-}"
  raw="${raw#LEVEL_}"
  raw="${raw,,}"
  # shellcheck disable=SC2206
  local parts=( ${raw//_/ } )
  local out=()
  local p
  for p in "${parts[@]}"; do
    out+=( "$(tr '[:lower:]' '[:upper:]' <<<"${p:0:1}")${p:1}" )
  done
  (IFS=' '; echo "${out[*]}")
}

extract_plan_from_json() {
  local json_file="$1"
  if command -v jq >/dev/null 2>&1; then
    local title
    title="$(jq -r '.subscription.goods.title // .purchaseSubscription.goods.title // empty' "$json_file" 2>/dev/null || true)"
    if [[ -n "$title" ]]; then
      echo "$title"
      return 0
    fi

    local level
    level="$(jq -r '.subscription.goods.membershipLevel // .purchaseSubscription.goods.membershipLevel // empty' "$json_file" 2>/dev/null || true)"
    if [[ -n "$level" ]]; then
      normalize_level "$level"
      return 0
    fi

    local coding_level
    coding_level="$(jq -r '.memberships[]? | select(.feature=="FEATURE_CODING") | .level // empty' "$json_file" 2>/dev/null | head -n1 || true)"
    if [[ -n "$coding_level" ]]; then
      normalize_level "$coding_level"
      return 0
    fi

    return 1
  fi

  # jq 不可用时做极简兜底
  local title
  title="$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json_file" | head -n1 || true)"
  if [[ -n "$title" ]]; then
    echo "$title"
    return 0
  fi
  return 1
}

MODE="online"
PARSE_INPUT=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --parse-json)
      MODE="parse"
      PARSE_INPUT="${2:-}"
      shift 2
      ;;
    --endpoint)
      ENDPOINT="${2:-}"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ "${MODE}" == "parse" ]]; then
  input="${PARSE_INPUT:-}"
  if [[ -z "$input" ]]; then
    echo "错误: --parse-json 需要一个 JSON 文件路径，或使用 '-' 从 stdin 读取。" >&2
    exit 2
  fi

  tmp_json="$(mktemp)"
  trap 'rm -f "$tmp_json"' EXIT
  if [[ "$input" == "-" ]]; then
    cat >"$tmp_json"
  else
    cat "$input" >"$tmp_json"
  fi

  if plan="$(extract_plan_from_json "$tmp_json")"; then
    echo "套餐名: $plan"
    exit 0
  fi
  echo "未解析到套餐名。"
  exit 1
fi

TOKEN="${KIMI_AUTH_TOKEN:-${POSITIONAL[0]:-}}"
if [[ -z "${TOKEN}" ]]; then
  echo "错误: 缺少 token。请设置环境变量 KIMI_AUTH_TOKEN 或作为第一个参数传入。" >&2
  echo "也可离线测试：scripts/kimi_subscription_probe.sh --parse-json <file|->" >&2
  exit 2
fi

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

request_once() {
  local method="$1"
  local body="$2"
  local body_mode="$3"

  local curl_args=(
    -sS
    -X "$method" "$ENDPOINT"
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
    -D "$TMP_HEADERS"
    -o "$TMP_BODY"
    -w "%{http_code}"
  )

  if [[ -n "$DEVICE_ID" ]]; then
    curl_args+=( -H "x-msh-device-id: $DEVICE_ID" )
  fi
  if [[ -n "$SESSION_ID" ]]; then
    curl_args+=( -H "x-msh-session-id: $SESSION_ID" )
  fi
  if [[ -n "$TRAFFIC_ID" ]]; then
    curl_args+=( -H "x-traffic-id: $TRAFFIC_ID" )
  fi

  if [[ "$method" == "POST" ]]; then
    curl_args+=( -H "Content-Type: application/json" )
    if [[ "$body_mode" == "with-body" ]]; then
      curl_args+=( --data "$body" )
    fi
  fi

  curl "${curl_args[@]}"
}

attempts=(
  "POST|{}|with-body"
  "POST|{\"scope\":[\"FEATURE_CODING\"]}|with-body"
  "POST||without-body"
  "GET||without-body"
)

attempt_logs=()
last_successful_body=""
last_successful_code=""

for attempt in "${attempts[@]}"; do
  IFS='|' read -r method body body_mode <<<"$attempt"
  code="$(request_once "$method" "$body" "$body_mode")"
  attempt_logs+=( "$method $body_mode -> HTTP $code" )

  if [[ "$code" != 2* ]]; then
    continue
  fi

  last_successful_code="$code"
  last_successful_body="$(cat "$TMP_BODY")"
  if plan="$(extract_plan_from_json "$TMP_BODY")"; then
    echo "请求成功: $method ($body_mode), HTTP $code"
    echo "endpoint: $ENDPOINT"
    echo "套餐名: $plan"
    exit 0
  fi
done

echo "请求完成，但未解析到套餐名。" >&2
echo "endpoint: $ENDPOINT" >&2
echo "---- 尝试状态 ----" >&2
printf '%s\n' "${attempt_logs[@]}" >&2
if [[ -n "$last_successful_code" ]]; then
  echo "---- 最近一次 2xx 响应体 ----" >&2
  printf '%s\n' "$last_successful_body" >&2
fi
echo "---- 最后一次响应头 ----" >&2
cat "$TMP_HEADERS" >&2
echo "---- 最后一次响应体 ----" >&2
cat "$TMP_BODY" >&2
echo "提示: 如果全是 404，请在浏览器 DevTools 里复制 GetSubscription 的 Request URL，用 --endpoint 指定。" >&2
exit 1
