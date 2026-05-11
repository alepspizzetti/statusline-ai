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
        (.context_window.total_input_tokens // .context_window.current_usage.input_tokens // 0 | tostring),
        (.context_window.total_output_tokens // .context_window.current_usage.output_tokens // 0 | tostring),
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
    str(get_val(cw, 'total_input_tokens', get_val(cu, 'input_tokens', 0))),
    str(get_val(cw, 'total_output_tokens', get_val(cu, 'output_tokens', 0))),
    str(get_val(rl.get('five_hour', {}), 'used_percentage', 0)),
    str(get_val(rl.get('seven_day', {}), 'used_percentage', 0)),
    str(get_val(rl.get('five_hour', {}), 'resets_at', 0)),
    str(get_val(rl.get('seven_day', {}), 'resets_at', 0)),
]
print('\t'.join(fields))
"
  fi
}

IFS=$'\t' read -r cwd model_name used_pct ctx_size ctx_input ctx_output limit_5h limit_7d reset_5h reset_7d \
  <<< "$(parse_json)"

# Limpeza de valores para garantir que sejam números
[[ "$used_pct" == "None" || "$used_pct" == "null" || -z "$used_pct" ]] && used_pct=0
[[ "$ctx_size" == "None" || "$ctx_size" == "null" || -z "$ctx_size" ]] && ctx_size=200000

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

fmt_compact() {
  awk -v n="$1" 'BEGIN {
    n += 0
    if (n >= 1000) {
      scaled = n / 1000
      if (scaled == int(scaled)) printf "%dk", scaled
      else printf "%.1fk", scaled
    } else {
      printf "%d", n
    }
  }'
}

normalize_num() {
  local v="$1"
  [[ "$v" == "None" || "$v" == "null" || -z "$v" ]] && { echo "0"; return; }
  v="${v//,/.}"
  awk -v n="$v" 'BEGIN { printf "%.12f", n+0 }'
}

format_reset_time() {
  local ts="$1"
  local formatted=""

  formatted=$(date -d "@$ts" +%H:%M 2>/dev/null) || formatted=""
  if [[ -z "$formatted" ]]; then
    formatted=$(date -r "$ts" +%H:%M 2>/dev/null) || formatted=""
  fi

  echo "$formatted"
}

format_reset_day_time() {
  local ts="$1"
  local formatted=""

  formatted=$(date -d "@$ts" +'%a %H:%M' 2>/dev/null) || formatted=""
  if [[ -z "$formatted" ]]; then
    formatted=$(date -r "$ts" +'%a %H:%M' 2>/dev/null) || formatted=""
  fi

  formatted=$(echo "$formatted" | tr '[:upper:]' '[:lower:]')
  case "$formatted" in
    mon\ *) formatted="seg ${formatted#mon }" ;;
    tue\ *) formatted="ter ${formatted#tue }" ;;
    wed\ *) formatted="qua ${formatted#wed }" ;;
    thu\ *) formatted="qui ${formatted#thu }" ;;
    fri\ *) formatted="sex ${formatted#fri }" ;;
    sat\ *) formatted="sab ${formatted#sat }" ;;
    sun\ *) formatted="dom ${formatted#sun }" ;;
  esac

  echo "$formatted"
}

fmt_pct() {
  local n out
  n=$(normalize_num "$1")
  out=$(awk -v n="$n" 'BEGIN { printf "%.2f", n+0 }')
  echo "${out/./,}"
}

fmt_pct_int() {
  local n
  n=$(normalize_num "$1")
  awk -v n="$n" 'BEGIN { printf "%d", n + 0.5 }'
}

ctx_input_fmt=$(fmt_k "$ctx_input")
ctx_output_fmt=$(fmt_k "$ctx_output")
ctx_size_fmt=$(fmt_compact "$ctx_size")
used_pct_num=$(normalize_num "$used_pct")
limit_5h_num=$(normalize_num "$limit_5h")
limit_7d_num=$(normalize_num "$limit_7d")
ctx_used_tokens=$(awk -v p="$used_pct_num" -v size="$ctx_size" 'BEGIN { printf "%.0f", (p * size) / 100 }')
ctx_used_fmt=$(fmt_compact "$ctx_used_tokens")
ctx_pct_fmt=$(fmt_pct_int "$used_pct_num")

# ── ANSI colors ───────────────────────────────────────────────────────────────
RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
WHITE=$'\033[97m'
GRAY=$'\033[90m'
RESET=$'\033[0m'

# ── context summary ───────────────────────────────────────────────────────────
awk -v v="$used_pct_num" 'BEGIN { exit !(v >= 90) }' && bar_color="$RED" || {
  awk -v v="$used_pct_num" 'BEGIN { exit !(v >= 70) }' && bar_color="$YELLOW" || bar_color="$GREEN"
}
ctx_display="${WHITE}ctx: ${bar_color}${ctx_pct_fmt}% ${GRAY}[${bar_color}${ctx_used_fmt}${GRAY}/${RED}${ctx_size_fmt}${GRAY}]${RESET}"

# ── rate limits (msg count + quotas) ─────────────────────────────────────────
fmt_rate() {
  local val="$1" label="$2" reset="$3"
  val=$(normalize_num "$val")
  local val_fmt
  val_fmt=$(fmt_pct "$val")

  local color="$CYAN"
  awk -v v="$val" 'BEGIN { exit !(v+0 >= 80) }' 2>/dev/null && color="$RED" || { awk -v v="$val" 'BEGIN { exit !(v+0 >= 50) }' 2>/dev/null && color="$YELLOW"; }

  local countdown=""
  if [[ "$reset" -gt 0 ]]; then
    local now=$(date +%s)
    local diff=$((reset - now))
    if [[ "$diff" -gt 0 ]]; then
      local reset_at
      if [[ "$label" == "7d" ]]; then
        reset_at=$(format_reset_day_time "$reset")
      else
        reset_at=$(format_reset_time "$reset")
      fi
      local remaining=""

      if [[ "$diff" -ge 86400 ]]; then
        local days=$((diff / 86400))
        local hours=$(( (diff % 86400) / 3600 ))
        remaining="${days}d${hours}h"
      elif [[ "$diff" -ge 3600 ]]; then
        local hours=$((diff / 3600))
        local mins=$(( (diff % 3600) / 60 ))
        remaining="${hours}h:${mins}m"
      else
        remaining="$((diff / 60))m"
      fi

      if [[ -n "$reset_at" ]]; then
        countdown=" ${GRAY}@${reset_at}(${remaining})${RESET}"
      else
        countdown=" ${GRAY}@${remaining}${RESET}"
      fi
    fi
  fi

  echo -n "${WHITE}${label}:${color}${val_fmt}%${countdown}${RESET}"
}

token_flow="${WHITE}tokens: ${CYAN}↑${ctx_input_fmt}${GRAY} ${GREEN}↓${ctx_output_fmt}${RESET}"
usage_info="${GRAY} | ${token_flow}${GRAY} | ${WHITE}Limits($(fmt_rate "$limit_5h_num" "5h" "$reset_5h")${GRAY} | ${RESET}$(fmt_rate "$limit_7d_num" "7d" "$reset_7d")${WHITE})${RESET}"

# ── shorten model name ────────────────────────────────────────────────────────
model_short=$(echo "$model_name" | sed 's/Claude //' | sed 's/ [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//')

# ── final output ──────────────────────────────────────────────────────────────
printf "${CYAN}%s${BLUE}%s${GRAY} | %s%s${RESET}" \
  "$model_short" \
  "$git_info" \
  "$ctx_display" \
  "$usage_info"
