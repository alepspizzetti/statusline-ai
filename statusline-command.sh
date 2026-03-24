#!/bin/bash
input=$(cat)
echo "$input" > ~/.claude/statusline/last_input.json

# ── extração de dados ─────────────────────────────────────────────────────────
parse_json() {
  if command -v jq >/dev/null 2>&1; then
    echo "$input" | jq -r '
      [
        .cwd,
        (.model.display_name // "Claude"),
        (.context_window.used_percentage // 0 | tostring),
        (.context_window.context_window_size // 200000 | tostring),
        (.context_window.current_usage.input_tokens // 0 | tostring),
        (.cost.total_cost_usd // 0 | tostring),
        (.rate_limits.five_hour.used_percentage // 0 | tostring),
        (.rate_limits.seven_day.used_percentage // 0 | tostring),
        (.rate_limits.five_hour.resets_at // 0 | tostring),
        (.rate_limits.seven_day.resets_at // 0 | tostring)
      ] | join("\t")
    '
  else
    local py
    py=$(command -v python 2>/dev/null || command -v python3 2>/dev/null)
    echo "$input" | "$py" -c "
import sys, json
try:
    d = json.load(sys.stdin)
except: d = {}
cw = d.get('context_window', {})
cu = cw.get('current_usage') or {}
rl = d.get('rate_limits', {})
def get_val(obj, key, default=0):
    v = obj.get(key)
    return v if v is not None else default

fields = [
    d.get('cwd', ''),
    get_val(d.get('model', {}), 'display_name', 'Claude'),
    str(get_val(cw, 'used_percentage', 0)),
    str(get_val(cw, 'context_window_size', 200000)),
    str(get_val(cu, 'input_tokens', 0)),
    str(get_val(d.get('cost', {}), 'total_cost_usd', 0)),
    str(get_val(rl.get('five_hour', {}), 'used_percentage', 0)),
    str(get_val(rl.get('seven_day', {}), 'used_percentage', 0)),
    str(get_val(rl.get('five_hour', {}), 'resets_at', 0)),
    str(get_val(rl.get('seven_day', {}), 'resets_at', 0)),
]
print('\t'.join(fields))
"
  fi
}

IFS=$'\t' read -r cwd model_name used_pct ctx_size ctx_input cost_usd limit_5h limit_7d reset_5h reset_7d \
  <<< "$(parse_json)"

# Limpeza de valores para garantir que sejam números
[[ "$used_pct" == "None" || "$used_pct" == "null" || -z "$used_pct" ]] && used_pct=0
[[ "$ctx_size" == "None" || "$ctx_size" == "null" || -z "$ctx_size" ]] && ctx_size=200000

# ── extração de mensagens de hoje (stats-cache.json) ──────────────────────────
STATS_FILE="$HOME/.claude/statusline/stats-cache.json"
TODAY=$(date +"%Y-%m-%d")
MSG_TODAY="0"

if [ -f "$STATS_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    MSG_TODAY=$(jq -r --arg TODAY "$TODAY" '.dailyActivity[] | select(.date == $TODAY) | .messageCount' "$STATS_FILE" 2>/dev/null || echo "0")
  else
    py=$(command -v python 2>/dev/null || command -v python3 2>/dev/null)
    if [ -n "$py" ]; then
      MSG_TODAY=$("$py" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
        for day in data.get('dailyActivity', []):
            if day.get('date') == sys.argv[2]:
                print(day.get('messageCount', 0))
                sys.exit(0)
except: pass
print(0)
" "$STATS_FILE" "$TODAY")
    fi
  fi
fi

# ── git branch ────────────────────────────────────────────────────────────────
git_info=""
if git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null | grep -q true; then
  branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)
  [ -n "$branch" ] && git_info=" [${branch}]"
fi

# ── helpers ───────────────────────────────────────────────────────────────────
fmt_k() {
  awk -v n="$1" 'BEGIN { if (n+0 >= 1000) printf "%.1fk", n/1000; else printf "%d", n+0 }'
}
ctx_input_fmt=$(fmt_k "$ctx_input")
ctx_size_fmt=$(fmt_k "$ctx_size")

# ── ANSI colors ───────────────────────────────────────────────────────────────
RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
WHITE=$'\033[97m'
GRAY=$'\033[90m'
RESET=$'\033[0m'

# ── context bar ───────────────────────────────────────────────────────────────
bar=$(awk -v p="$used_pct" 'BEGIN {
  filled = int(p / 10 + 0.5); if (filled > 10) filled = 10;
  bar = ""; for (i = 1; i <= filled; i++) bar = bar "#";
  for (i = filled+1; i <= 10; i++) bar = bar "-";
  print bar
}')
[ "$used_pct" -ge 90 ] && bar_color="$RED" || { [ "$used_pct" -ge 70 ] && bar_color="$YELLOW" || bar_color="$GREEN"; }
ctx_display="${WHITE}ctx: ${bar_color}${used_pct}% [${bar}]${GRAY}/${RED}${ctx_size_fmt}${RESET}"

# ── rate limits (msg count + quotas) ─────────────────────────────────────────
fmt_rate() {
  local val="$1" label="$2" reset="$3"
  [[ "$val" == "None" || "$val" == "null" || -z "$val" ]] && val=0

  local color="$CYAN"
  awk -v v="$val" 'BEGIN { exit !(v+0 >= 80) }' 2>/dev/null && color="$RED" || { awk -v v="$val" 'BEGIN { exit !(v+0 >= 50) }' 2>/dev/null && color="$YELLOW"; }

  local countdown=""
  if [[ "$reset" -gt 0 ]]; then
    local now=$(date +%s)
    local diff=$((reset - now))
    if [[ "$diff" -gt 0 ]]; then
      if [[ "$diff" -ge 86400 ]]; then
        local days=$((diff / 86400))
        local hours=$(( (diff % 86400) / 3600 ))
        countdown=" ${GRAY}@${days}d${hours}h${RESET}"
      elif [[ "$diff" -ge 3600 ]]; then
        local hours=$((diff / 3600))
        local mins=$(( (diff % 3600) / 60 ))
        countdown=" ${GRAY}@${hours}h${mins}m${RESET}"
      else
        countdown=" ${GRAY}@$((diff / 60))m${RESET}"
      fi
    fi
  fi

  echo -n "${WHITE}${label}:${color}${val}%${countdown}${RESET}"
}

usage_info="${GRAY} | ${WHITE}msgs: ${CYAN}${MSG_TODAY}${RESET}${GRAY} | ${WHITE}Limits($(fmt_rate "$limit_5h" "5h" "$reset_5h")${GRAY} | ${RESET}$(fmt_rate "$limit_7d" "7d" "$reset_7d")${WHITE})${RESET}"

# ── shorten model name ────────────────────────────────────────────────────────
model_short=$(echo "$model_name" | sed 's/Claude //' | sed 's/ [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//')

# ── final output ──────────────────────────────────────────────────────────────
printf "${CYAN}%s${BLUE}%s${GRAY} | %s${GRAY} | ${BLUE}prompt: ${WHITE}%s%s${GRAY} | ${YELLOW}\$%s${RESET}" \
  "$model_short" \
  "$git_info" \
  "$ctx_display" \
  "$ctx_input_fmt" \
  "$usage_info" \
  "$(printf "%.4f" "${cost_usd:-0}")"
