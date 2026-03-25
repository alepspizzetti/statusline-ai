#!/usr/bin/env bash
set -euo pipefail

REPO_DEFAULT="https://github.com/alepspizzetti/statusline-ai.git"
DEST="${DEST:-"$HOME/.claude/statusline"}"

log() { printf '%s\n' "$*" >&2; }
die() { log "Erro: $*"; exit 1; }

command -v git >/dev/null 2>&1 || die "git não encontrado. Instale o Git e tente novamente."

repo="$REPO_DEFAULT"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  origin=$(git config --get remote.origin.url 2>/dev/null || true)
  if [[ -n "${origin:-}" ]]; then
    repo="$origin"
  fi
fi

mkdir -p "$(dirname "$DEST")"

if [[ -d "$DEST/.git" ]]; then
  log "Atualizando: $DEST"
  git -C "$DEST" pull --ff-only
elif [[ -e "$DEST" ]]; then
  die "$DEST existe mas não é um repositório git. Remova/renomeie a pasta e rode novamente."
else
  log "Clonando: $repo -> $DEST"
  git clone "$repo" "$DEST"
fi

chmod +x "$DEST/statusline-command.sh" 2>/dev/null || true

settings_path="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings_path")"

status_cmd='bash -lc "~/.claude/statusline/statusline-command.sh"'

update_with_python() {
  local py="$1"
  SETTINGS_PATH="$settings_path" STATUS_CMD="$status_cmd" "$py" - <<'PY'
import json, os

settings_path = os.path.expanduser(os.environ["SETTINGS_PATH"])
os.makedirs(os.path.dirname(settings_path), exist_ok=True)

status_cmd = os.environ["STATUS_CMD"]

data = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, 'r', encoding='utf-8') as f:
            data = json.load(f) or {}
    except Exception:
        data = {}

data['statusLine'] = {
  'type': 'command',
  'command': status_cmd,
}

with open(settings_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
}

update_with_jq() {
  command -v jq >/dev/null 2>&1 || return 1

  local tmp="${settings_path}.tmp.$$"
  if [[ -s "$settings_path" ]]; then
    jq --arg cmd "$status_cmd" '.statusLine = {type:"command", command:$cmd}' "$settings_path" >"$tmp" || return 1
  else
    printf '{}' | jq --arg cmd "$status_cmd" '.statusLine = {type:"command", command:$cmd}' >"$tmp" || return 1
  fi
  mv "$tmp" "$settings_path"
}

if command -v python3 >/dev/null 2>&1; then
  log "Atualizando settings.json via python3"
  update_with_python python3
elif command -v python >/dev/null 2>&1; then
  log "Atualizando settings.json via python"
  update_with_python python
elif update_with_jq; then
  log "Atualizando settings.json via jq"
  :
else
  die "Precisa de python3/python ou jq para atualizar $settings_path"
fi

log "Pronto. Para atualizar depois: git -C \"$DEST\" pull --ff-only"
log "Obs: no Windows, rode este script no Git Bash ou WSL (não no PowerShell)."
