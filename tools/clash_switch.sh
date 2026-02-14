#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: clash_switch [options] [-- clash_test options...]

测速并交互式切换节点。默认测试日本|美国|新加坡节点，展示 top 10，输入编号即可切换。

Options:
  --config PATH    Config file (default: conf/config.yaml)
  --group NAME     要切换的 proxy-group 名称 (default: 自动检测第一个 select 组)
  --top N          展示前 N 个最快节点 (default: 10)
  -h, --help       Show this help

Examples:
  clash_switch                              # 默认测速日本|美国|新加坡，展示 top 10
  clash_switch -- --filter "日本"            # 只测日本节点
  clash_switch -- --exclude "香港|美国"      # 自定义排除
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG="$PROJECT_DIR/conf/config.yaml"
GROUP=""
TOP="10"
CLASH_TEST_ARGS=()
DEFAULT_FILTER="日本|美国|新加坡"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --group) GROUP="$2"; shift 2 ;;
    --top) TOP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; CLASH_TEST_ARGS=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

YQ="$PROJECT_DIR/bin/yq"
if [[ ! -x "$YQ" ]]; then
  YQ="yq"
fi

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---------- 读取 API 配置 ----------
BASE=""
SECRET="${CLASH_SECRET:-}"

if [[ -f "$CONFIG" ]]; then
  BASE="$("$YQ" eval '.external-controller // ""' "$CONFIG" 2>/dev/null | tr -d '"' || true)"
  if [[ -z "$SECRET" || "$SECRET" == "null" ]]; then
    SECRET="$("$YQ" eval '.secret // ""' "$CONFIG" 2>/dev/null | tr -d '"' || true)"
  fi
fi
if [[ -z "$BASE" || "$BASE" == "null" ]]; then
  BASE="http://127.0.0.1:9090"
fi
if [[ "$BASE" != http://* && "$BASE" != https://* ]]; then
  BASE="http://$BASE"
fi

API_HEADERS=(-H "Content-Type: application/json")
if [[ -n "$SECRET" && "$SECRET" != "null" ]]; then
  API_HEADERS+=(-H "Authorization: Bearer $SECRET")
fi

# ---------- 检测 select 组 ----------
if [[ -z "$GROUP" ]]; then
  GROUP="$("$YQ" eval '.proxy-groups[] | select(.type == "select") | .name' "$CONFIG" 2>/dev/null | head -n1 | tr -d '"' || true)"
  if [[ -z "$GROUP" || "$GROUP" == "null" ]]; then
    echo -e "${RED}错误：未找到 select 类型的 proxy-group，请用 --group 指定${NC}" >&2
    exit 1
  fi
fi

echo -e "${CYAN}[*] 目标代理组: ${GROUP}${NC}"

# ---------- 默认 filter ----------
has_filter=false
for arg in "${CLASH_TEST_ARGS[@]}"; do
  if [[ "$arg" == "--filter" || "$arg" == "--exclude" ]]; then
    has_filter=true
    break
  fi
done

if [[ "$has_filter" == false ]]; then
  CLASH_TEST_ARGS=(--filter "$DEFAULT_FILTER" "${CLASH_TEST_ARGS[@]}")
fi

# ---------- 测速 ----------
echo -e "${YELLOW}[*] 正在测速...${NC}"

test_output=$(cd "$PROJECT_DIR" && bash "$SCRIPT_DIR/clash_test.sh" --top "$TOP" --sort "${CLASH_TEST_ARGS[@]}" 2>/dev/null) || true

if [[ -z "$test_output" ]]; then
  echo -e "${RED}错误：测速无结果${NC}" >&2
  exit 1
fi

echo ""
echo "$test_output"
echo ""

# 提取结果行 (格式: "1. 123 ms\tNodeName")
mapfile -t result_lines < <(echo "$test_output" | grep -E '^[0-9]+\.')

if [[ ${#result_lines[@]} -eq 0 ]]; then
  echo -e "${RED}错误：无可用节点${NC}" >&2
  exit 1
fi

# ---------- 交互选择 ----------
while true; do
  echo -ne "${CYAN}输入编号切换节点 (q 退出): ${NC}"
  read -r choice </dev/tty

  if [[ "$choice" == "q" || "$choice" == "Q" || "$choice" == "quit" ]]; then
    echo -e "${YELLOW}已退出${NC}"
    exit 0
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}请输入数字编号${NC}"
    continue
  fi

  node_name=""
  for line in "${result_lines[@]}"; do
    if echo "$line" | grep -qE "^${choice}\."; then
      node_name=$(echo "$line" | sed "s/^${choice}\.[[:space:]]*[0-9]* ms[[:space:]]*//")
      break
    fi
  done

  if [[ -z "$node_name" ]]; then
    echo -e "${RED}编号 ${choice} 不存在，请重新输入${NC}"
    continue
  fi

  enc_group=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$GROUP")

  resp=$(curl -s -w '\n%{http_code}' -X PUT "${API_HEADERS[@]}" \
    "$BASE/proxies/$enc_group" \
    -d "{\"name\": \"$node_name\"}" 2>/dev/null || true)

  http_code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')

  if [[ "$http_code" == 2* || "$http_code" == "204" ]]; then
    echo -e "${GREEN}[✓] 已切换「${GROUP}」-> ${node_name}${NC}"
  else
    echo -e "${RED}[✗] 切换失败 (HTTP $http_code): $body${NC}" >&2
  fi
  break
done
