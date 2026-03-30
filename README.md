# Claude Statusline Customizer

Este projeto contém um script customizado para a `statusLine` do Claude CLI, fornecendo informações em tempo real sobre a sessão, uso de modelos, custos e limites de taxa de forma visual e organizada.

## 🚀 Como Funciona

O script `statusline-command.sh` é executado pelo Claude CLI a cada interação. Ele funciona da seguinte forma:

1. **Captura de Dados:** Recebe um JSON contendo o estado atual da sessão via `stdin`.
2. **Snapshot de Depuração:** Salva o JSON recebido em `last_input.json` para permitir inspeção manual dos dados brutos (tokens, custos exatos, etc).
3. **Processamento:** Extrai os campos necessários usando `jq` (ou `python` como fallback).
4. **Estatísticas Persistentes:** Lê o arquivo `stats-cache.json` para recuperar o histórico de mensagens do dia.
5. **Saída Visual:** Imprime uma linha única formatada com cores ANSI para o terminal.

## 📂 Estrutura de Arquivos

- `statusline-command.sh`: O "motor" que processa os dados e gera a barra de status.
- `last_input.json`: Snapshot da última interação. Útil para verificar como o Claude CLI reporta tokens de cache e limites de taxa.
- `stats-cache.json`: Banco de dados local (JSON) que armazena:
    - `dailyActivity`: Contagem de mensagens, sessões e chamadas de ferramentas (`toolCallCount`) por dia.
    - `dailyModelTokens`: Distribuição de uso de tokens por modelo específico.
    - `modelUsage`: Métricas acumulativas de tokens de entrada, saída e **cache** (read/creation).

## ✨ Funcionalidades

- **Identificação do Modelo:** Exibe o nome do modelo de forma compacta (remove o prefixo "Claude" e sufixos de data).
- **Integração com Git:** Mostra a branch atual se você estiver dentro de um repositório Git.
- **Monitoramento de Contexto:** Uma barra de progresso visual (0-100%) com cores dinâmicas (Verde < 70%, Amarelo < 90%, Vermelho >= 90%).
- **Contagem de Tokens:** Exibe os tokens acumulados da sessão (entrada `↑` e saída `↓`, formatados em `k`) para evitar resets visuais entre atualizações.
- **Estatísticas Diárias:** Mostra quantas mensagens foram enviadas hoje com base no `stats-cache.json`.
- **Limites de Taxa (Rate Limits):** Alertas visuais para o uso das cotas de 5 horas e 7 dias.
- **Rastreamento de Custo:** Exibe o custo total acumulado da sessão em USD com precisão de 4 casas decimais.

## 🛠️ Instalação (Git clone + updates via `git pull`)

A forma mais simples de distribuir e manter todo mundo atualizado é instalar via **Git** em `~/.claude/statusline` e atualizar com `git pull`.

### ✅ Pré-requisitos
- **Claude CLI**
- **Git**
- **Bash**
  - Windows: **Git for Windows** (Git Bash) já resolve.
  - macOS: bash/zsh nativo.
- **jq (opcional)** ou **python/python3** (fallback já usado pelo script)

### ⭐ Instalação via script (recomendado)
No **macOS/Linux**: rode no Terminal.

No **Windows**: rode no **Git Bash** (Git for Windows) ou via **WSL** (o `.sh` não executa nativamente no PowerShell).

**1 comando (recomendado):**

```bash
curl -fsSL https://raw.githubusercontent.com/alepspizzetti/statusline-ai/HEAD/install.sh | bash
```

Isso vai:
- clonar/atualizar em `~/.claude/statusline`
- configurar `~/.claude/settings.json` com o `statusLine`

---

### 1) Windows (PowerShell) — instalar/atualizar + configurar
Copie/cole no PowerShell:

```powershell
$repo = "https://github.com/alepspizzetti/statusline-ai.git"
$dest = Join-Path $HOME ".claude\statusline"

if (Test-Path (Join-Path $dest ".git")) {
  git -C $dest pull --ff-only
} else {
  New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
  git clone $repo $dest
}

$settingsPath = Join-Path $HOME ".claude\settings.json"
New-Item -ItemType Directory -Path (Split-Path $settingsPath) -Force | Out-Null

$settings = @{}
if (Test-Path $settingsPath) {
  try { $settings = (Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable) } catch { $settings = @{} }
}

$settings["statusLine"] = @{ type = "command"; command = 'bash -lc "~/.claude/statusline/statusline-command.sh"' }
$settings | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $settingsPath
```

> Se o `bash` não estiver no PATH, abra o **Git Bash** uma vez (ele geralmente ajusta o PATH), ou use o caminho completo do `bash.exe`.

### 2) macOS (zsh/bash) — instalar/atualizar + configurar
Copie/cole no terminal:

```bash
REPO="https://github.com/alepspizzetti/statusline-ai.git"
DEST="$HOME/.claude/statusline"

mkdir -p "$HOME/.claude"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  git clone "$REPO" "$DEST"
fi

chmod +x "$DEST/statusline-command.sh"

python3 - <<'PY'
import json, os
settings_path = os.path.expanduser('~/.claude/settings.json')
os.makedirs(os.path.dirname(settings_path), exist_ok=True)

data = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception:
        data = {}

data['statusLine'] = {
  'type': 'command',
  'command': 'bash -lc "~/.claude/statusline/statusline-command.sh"'
}

with open(settings_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
```

### 🔄 Atualizar depois
A qualquer momento:

```bash
git -C ~/.claude/statusline pull --ff-only
```

### ♻️ Auto-update (opcional)
Se quiser automatizar, a ideia é agendar um `git pull --ff-only`:
- **Windows (Task Scheduler):** rodar no logon ou daily: `powershell.exe -NoProfile -Command "git -C $HOME\.claude\statusline pull --ff-only"`
- **macOS (LaunchAgent):** rodar periodicamente: `bash -lc 'git -C ~/.claude/statusline pull --ff-only'`

(Se preferir, a gente pode adicionar scripts `update.ps1/update.sh` e os arquivos de agendamento no repo.)

## 📝 Legenda da Statusline

A saída segue este padrão visual:
`Modelo [branch] | ctx: 25% [###-------]/200k | tokens: ↑1.2k ↓567 | Limits(5h:10% | 7d:5%) | $0.0045`

| Campo | Descrição | Cores |
| :--- | :--- | :--- |
| **Modelo** | Nome abreviado do modelo em uso. | Ciano |
| **[branch]** | Branch Git atual (se disponível). | Azul |
| **ctx: X%** | Percentual de uso da janela de contexto. | Verde/Amarelo/Vermelho |
| **[###---]** | Barra visual de uso do contexto. | Colorida conforme o % |
| **200k** | Tamanho total da janela de contexto. | Vermelho |
| **tokens** | Fluxo da interação atual: entrada (↑) e saída (↓). | Ciano (↑) / Verde (↓) |
| **5h / 7d** | Uso das cotas de rate limit. | Ciano (baixo) / Amarelo (médio) / Vermelho (alto) |
| **$0.0000** | Custo total da sessão em dólares. | Amarelo |

## 📦 Dependências

- **Bash:** Ambiente de execução.
- **jq (Recomendado):** Para processamento rápido de JSON.
- **Python (Fallback):** Caso o `jq` não esteja instalado, o script utiliza Python para processar os dados.
- **Git:** Necessário para exibir informações de branch.
