#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="https://kimi-k2.ai/api/user/credits"
API_KEY="${KIMI_K2_API_KEY:-${KIMI_API_KEY:-${1:-}}}"

if [[ -z "${API_KEY}" ]]; then
  echo "错误: 缺少 API Key。请设置 KIMI_K2_API_KEY / KIMI_API_KEY 或作为第一个参数传入。" >&2
  exit 2
fi

TMP_BODY="$(mktemp)"
TMP_HEADERS="$(mktemp)"
trap 'rm -f "$TMP_BODY" "$TMP_HEADERS"' EXIT

HTTP_CODE="$(curl -sS \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Accept: application/json" \
  -D "$TMP_HEADERS" \
  -o "$TMP_BODY" \
  -w "%{http_code}" \
  "$ENDPOINT")"

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "请求失败，HTTP $HTTP_CODE" >&2
  echo "---- 响应头 ----" >&2
  cat "$TMP_HEADERS" >&2
  echo "---- 响应体 ----" >&2
  cat "$TMP_BODY" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  echo "请求成功，原始响应："
  jq . "$TMP_BODY"
else
  echo "请求成功（系统未安装 jq，输出原始 JSON）："
  cat "$TMP_BODY"
fi
