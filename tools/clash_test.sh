#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/clash_test.sh [options]

Options:
  --config PATH    Config file (default: conf/config.yaml)
  --base URL       Mihomo API base URL (default: from config external-controller)
  --url URL        Test URL (default: first url-test group url or gstatic generate_204)
  --timeout MS     Timeout in milliseconds (default: 5000)
  --secret TOKEN   Mihomo API secret (default: CLASH_SECRET or config secret)
  --source MODE    Node source: api|yaml|auto (default: auto)
  --filter REGEX   Only test nodes whose names match REGEX
  --exclude REGEX  Exclude nodes whose names match REGEX
  --limit N        Only test the first N nodes after filtering
  --top N          Only show the N lowest-latency nodes (numeric delays, default: 10)
  --jobs N         Number of concurrent tests (default: 8)
  --sort           Sort results by delay (ERR at end)
  -h, --help       Show this help

Examples:
  tools/clash_test.sh --filter "日本" --limit 5
  tools/clash_test.sh --source yaml --sort
  CLASH_SECRET=xxx tools/clash_test.sh --timeout 8000
EOF
}

CONFIG="conf/config.yaml"
BASE=""
TEST_URL=""
TIMEOUT="5000"
SECRET="${CLASH_SECRET:-}"
SOURCE="auto"
FILTER=""
EXCLUDE_REGEX="^(自动选择|故障转移)$|剩余流量|套餐到期|香港"
LIMIT=""
TOP="10"
JOBS="8"
SORT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --url) TEST_URL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --secret) SECRET="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --filter) FILTER="$2"; shift 2 ;;
    --exclude) EXCLUDE_REGEX="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --top) TOP="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --sort) SORT="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 1
fi

YQ="./bin/yq"
if [[ ! -x "$YQ" ]]; then
  YQ="yq"
fi

if [[ -z "$BASE" ]]; then
  BASE="$($YQ eval '.external-controller // ""' "$CONFIG" 2>/dev/null || true)"
fi
BASE="${BASE//\"/}"
if [[ -z "$BASE" || "$BASE" == "null" ]]; then
  BASE="http://127.0.0.1:9090"
fi
if [[ "$BASE" != http://* && "$BASE" != https://* ]]; then
  BASE="http://$BASE"
fi

if [[ -z "$TEST_URL" ]]; then
  TEST_URL="$($YQ eval '.["proxy-groups"][] | select(.type=="url-test") | .url' "$CONFIG" 2>/dev/null | head -n1 | tr -d '"' || true)"
fi
if [[ -z "$TEST_URL" || "$TEST_URL" == "null" ]]; then
  TEST_URL="http://www.gstatic.com/generate_204"
fi

if [[ -z "$SECRET" || "$SECRET" == "null" ]]; then
  SECRET="$($YQ eval '.secret // ""' "$CONFIG" 2>/dev/null | tr -d '"' || true)"
fi

api_headers=()
if [[ -n "$SECRET" && "$SECRET" != "null" ]]; then
  api_headers=(-H "Authorization: Bearer $SECRET")
fi

fetch_nodes_api() {
  local resp code body
  resp=$(curl -s --max-time 5 -w '\n%{http_code}' "${api_headers[@]}" "$BASE/proxies" || true)
  code="$(printf "%s" "$resp" | tail -n1)"
  body="$(printf "%s" "$resp" | sed '$d')"
  if [[ "$code" != 2* ]]; then
    return 1
  fi
  python3 - <<'PY' "$body"
import json,sys
data=json.loads(sys.argv[1])
proxies=data.get("proxies",{})
skip_types={"Direct","Reject","RejectDrop","Pass","Compatible","Relay","Selector","Fallback","URLTest","LoadBalance","Unknown"}
names=[]
for name,info in proxies.items():
    t=info.get("type")
    if t in skip_types:
        continue
    if isinstance(info.get("all"), list):
        continue
    names.append(name)
print("\n".join(names))
PY
}

fetch_nodes_yaml() {
  "$YQ" eval '.proxies[].name' "$CONFIG" 2>/dev/null | tr -d '"'
}

node_list=""
case "$SOURCE" in
  api)
    if ! node_list="$(fetch_nodes_api)"; then
      echo "Failed to read nodes from API ($BASE). Provide --secret or use --source yaml." >&2
      exit 1
    fi
    ;;
  yaml)
    node_list="$(fetch_nodes_yaml)"
    ;;
  auto)
    if node_list="$(fetch_nodes_api)"; then
      :
    else
      node_list="$(fetch_nodes_yaml)"
    fi
    ;;
  *)
    echo "Invalid --source: $SOURCE (use api|yaml|auto)" >&2
    exit 1
    ;;
esac

if [[ -z "$node_list" ]]; then
  echo "No nodes found." >&2
  exit 1
fi

filter_cmd=()
if [[ -n "$FILTER" ]]; then
  if command -v rg >/dev/null 2>&1; then
    filter_cmd=(rg "$FILTER")
  else
    filter_cmd=(grep -E "$FILTER")
  fi
fi

exclude_cmd=()
if [[ -n "$EXCLUDE_REGEX" ]]; then
  if command -v rg >/dev/null 2>&1; then
    exclude_cmd=(rg -v "$EXCLUDE_REGEX")
  else
    exclude_cmd=(grep -Ev "$EXCLUDE_REGEX")
  fi
fi

tmp="$(mktemp)"
tmpdir="$(mktemp -d)"
trap 'rm -f "$tmp"; rm -rf "$tmpdir"' EXIT

if [[ -n "$LIMIT" ]]; then
  limit_cmd=(head -n "$LIMIT")
else
  limit_cmd=()
fi

node_stream=$(printf "%s\n" "$node_list")
if [[ ${#filter_cmd[@]} -gt 0 ]]; then
  node_stream="$(printf "%s\n" "$node_stream" | "${filter_cmd[@]}")"
fi
if [[ ${#exclude_cmd[@]} -gt 0 ]]; then
  node_stream="$(printf "%s\n" "$node_stream" | "${exclude_cmd[@]}")"
fi
if [[ ${#limit_cmd[@]} -gt 0 ]]; then
  node_stream="$(printf "%s\n" "$node_stream" | "${limit_cmd[@]}")"
fi

total=$(printf "%s\n" "$node_stream" | sed '/^$/d' | wc -l | tr -d ' ')

test_one() {
  local idx="$1"
  local name="$2"
  [[ -z "$name" ]] && return 0
  printf "[%s/%s] %s\n" "$idx" "$total" "$name" >&2
  local enc resp delay
  enc=$(python3 - <<'PY' "$name"
import urllib.parse,sys
print(urllib.parse.quote(sys.argv[1]))
PY
)
  resp=$(curl -s -G "${api_headers[@]}" "$BASE/proxies/$enc/delay" \
    --data-urlencode "url=$TEST_URL" \
    --data-urlencode "timeout=$TIMEOUT" || true)
  delay=$(python3 - <<'PY' "$resp"
import json,sys
try:
    print(json.loads(sys.argv[1]).get("delay","ERR"))
except Exception:
    print("ERR")
PY
)
  printf "%s\t%s\n" "$delay" "$name" > "$tmpdir/$idx"
}

if [[ "$JOBS" -le 1 ]]; then
  idx=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    idx=$((idx+1))
    test_one "$idx" "$name"
  done <<< "$node_stream"
else
  idx=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    idx=$((idx+1))
    test_one "$idx" "$name" &
    while (( $(jobs -pr | wc -l) >= JOBS )); do
      wait -n
    done
  done <<< "$node_stream"
  wait
fi

cat "$tmpdir"/* > "$tmp" 2>/dev/null || true

if [[ "$SORT" == "true" || -n "$TOP" ]]; then
  python3 - <<'PY' "$tmp" "$TOP"
import sys
path=sys.argv[1]
top=sys.argv[2].strip()
lines=[l.rstrip("\n") for l in open(path, encoding="utf-8", errors="ignore")]
def key(line):
    delay=line.split("\t",1)[0]
    try:
        return (0,int(delay))
    except Exception:
        return (1,99999999)
sorted_lines=sorted(lines, key=key)
if top:
    out=[]
    for line in sorted_lines:
        delay=line.split("\t",1)[0]
        try:
            int(delay)
        except Exception:
            continue
        out.append(line)
        if len(out) >= int(top):
            break
    for line in out:
        print(line)
else:
    for line in sorted_lines:
        print(line)
PY
else
  cat "$tmp"
fi
